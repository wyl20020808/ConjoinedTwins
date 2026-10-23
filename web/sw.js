// 共生连线网页版 Service Worker：把引擎与数据包按内容哈希缓存在本机（Cache Storage）。
// prepare_web.py 导出时把 __BUILD__ 与 __FILES__ 替换为本次构建的文件清单（相对路径 → 内容哈希）。
// - 清单内文件缓存优先：命中即直接返回，刷新页面不再下载；未命中才走网络并写入缓存。
// - 缓存键是“路径?h=哈希”，内容变化的文件自动换新；新版本激活时删除清单外的旧条目，
//   未变化的章节包保留，更新游戏不必重新下载全部章节。
// - index.html、packs.json、sw.js 与 /ws 联机不在清单内，始终走网络，保证版本一致。
const BUILD = '__BUILD__';
const FILES = __FILES__;
// v2：v1 里存过带 Content-Encoding 的章节包响应（长度头与内容不符，会让下载截断），整体弃用。
const CACHE = 'ct-files-v2';

function scopePath() {
	return new URL(self.registration.scope).pathname;
}

function cacheKey(relative) {
	return new URL(relative + '?h=' + FILES[relative], self.registration.scope).href;
}

self.addEventListener('install', () => {
	self.skipWaiting();
});

self.addEventListener('activate', (event) => {
	event.waitUntil((async () => {
		for (const name of await caches.keys()) {
			if (name.startsWith('ct-files-') && name !== CACHE) {
				await caches.delete(name);
			}
		}
		const cache = await caches.open(CACHE);
		const keep = new Set(Object.keys(FILES).map(cacheKey));
		for (const request of await cache.keys()) {
			if (!keep.has(request.url)) {
				await cache.delete(request);
			}
		}
		await self.clients.claim();
	})());
});

self.addEventListener('fetch', (event) => {
	const request = event.request;
	if (request.method !== 'GET') {
		return;
	}
	const url = new URL(request.url);
	if (url.origin !== self.location.origin || !url.pathname.startsWith(scopePath())) {
		return;
	}
	const relative = url.pathname.slice(scopePath().length);
	if (!Object.prototype.hasOwnProperty.call(FILES, relative)) {
		return;
	}
	event.respondWith((async () => {
		const cache = await caches.open(CACHE);
		const key = cacheKey(relative);
		const hit = await cache.match(key);
		if (hit) {
			return hit;
		}
		const response = await fetch(request);
		if (response.status === 200) {
			// 写入缓存与页面读取同时进行；空间不足时只放弃缓存，不影响本次游戏。
			event.waitUntil(cache.put(key, response.clone()).catch((err) => console.warn('[ct-sw ' + BUILD + '] cache put failed', relative, err)));
		}
		return response;
	})());
});
