# 归航 Demo 资产来源与许可

本轮通过普通 HTTPS 请求实际访问官方页面、检索其公开下载链接并下载资源，没有浏览器登录、购买或 API Key。官方网页原文证据为 `build-tools/art-demo/mech.html`、`industrial.html`；下载与 SHA256 清单为 `build-tools/art-demo/sources.json`。所用两组均由官方页面声明 CC0，可修改并随测试包再分发。

| 作者 / 资源组 | 官方页面 / 下载文件 | 许可 | 实际使用位置 |
| --- | --- | --- | --- |
| Quaternius / Animated Mech Pack | https://quaternius.com/packs/animatedmech.html；官方页面链接公共 Drive 目录 `1sueV_4CGMpZC8y30mWfgKK9UaT3mkHBX`，Flat Colors / glTF 中 George.gltf 与 Leela.gltf | CC0：https://creativecommons.org/publicdomain/zero/1.0/ | `assets/mechs/George.gltf`：01 青色识别、宽肩四肢轮廓；`Leela.gltf`：02 橙色识别、柱状头身轮廓；生产 `build_robots()` 实际加载 |
| Kenney / City Kit Industrial 2.0 | https://kenney.nl/assets/city-kit-industrial；https://kenney.nl/media/pages/assets/city-kit-industrial/0ec35b139d-1788171848/kenney_city-kit-industrial_2.0.zip | CC0；原文 `assets/industrial/License.txt` | building-a/f/k/p：道路两侧建筑与远景；detail-tank/chimney-large：侧边设施；shipping-container-a：可碰撞货箱；Textures/colormap.png：共享调色板，全部由生产场景加载 |

角色直接下载：George `https://drive.google.com/uc?export=download&id=1CEATvzzC1w198kD9DLTamgMD8LsRwV1I`；Leela `https://drive.google.com/uc?export=download&id=1BOAP-hwB8VlR6S9veirq5407h4dp0Vfq`。每个 glTF 自含模型数据；仅下载两个角色，没有下载全套角色工程。工业归档 SHA256：`5b381164e5760f3830a2dbee43b972deee38b2a695d091b56e238ab2910c96d2`。仅选七份 GLB 和其贴图进入运行资产目录；FBX、其他道具和来源网页留在制作目录。

加工与呈现：保持原模型网格和调色板，按包围盒统一尺度；工业模型额外限制宽度以避免遮挡道路，材质绑定原共享贴图并适度调暗。上轮使用原 Idle 动画的静态采样姿态和程序滑行底座，没有使用 T-pose。本轮双人移动任务移除滑行底座，复用两台机甲已有的 Idle、Run、Jump、HitRecieve_1、Death 骨骼动画，接入生产动作切换与基础混合过渡；没有新增下载、许可依赖或 Blender 加工。

本项目程序制作：道路模块、车道线、边界/栏杆、灯杆与灯带、透明能量屏障、区段/终点门架、角色识别灯和双人能量线、天空与定向灯、HUD 和菜单。它们补齐下载资产的环境和交互表达；两个机器人、建筑、货箱与设施均为实际下载资产。

决策者审查返修：相同 Kenney building-k/p/f 资源另用于三排城市尺度远景，新增程序连续港区承托面；没有新增下载或许可依赖。屏障显示改为与逻辑矩形一致的完整能量体积和地面危险投影。

0.3.0 无限双人版本：继续复用上述两组 CC0 资源，无新下载或许可变化。程序生成低栏、固定/活动地刺、扫描束和三种高度飞行物、危险包围体与预警轨迹；角色原骨骼动画按跳跃物理阶段采样。移除生产终点拱门，工业道路及设施进入循环节点池。历史屏障/终点记录仅描述上轮实现。新版资源实际进入 Mac PCK，检查证据见 `builds/macos/evidence-20261012T115750573615Z/validation.json`。

2026-10-13 悬崖场景与真人角色：生产场景改为程序生成的山脊、崖壁、石峰和云海，不再加载上述机甲与工业建筑（文件保留）。新增两名角色：

| 作者 / 资源 | 页面 / 下载文件 | 许可 | 实际使用位置 |
| --- | --- | --- | --- |
| Quaternius / Adventurer | https://poly.pizza/m/5EGWBMpuXq ；`https://static.poly.pizza/bbe369ee-a686-42c7-adad-14356f5f2f15.glb`，1,944,116 字节，SHA256 `4a8639cd8eee9d8a150464edc25eb0536ced464790704a64e40c8620d99f66db` | 页面标注 CC0 1.0 | `assets/humans/Adventurer_A.glb`：01 |
| Quaternius / Adventurer | https://poly.pizza/m/ZwF0K7WBmu ；`https://static.poly.pizza/69689495-028d-4b81-8678-792338a5693e.glb`，1,585,676 字节，SHA256 `38e4e6429d8af5849bb23e9585266f8c17dfe3e987bda89dec58f606aaedcf31` | 页面标注 CC0 1.0 | `assets/humans/Adventurer_B.glb`：02 |

Quaternius 官网 Animated Men / Women 与 RPG Characters 的公共 Drive 目录当时返回“Quota exceeded”，改从 poly.pizza 上同一作者的条目下载。使用其自带的 Idle、Run、Roll、HitRecieve、Death 动画，未做 Blender 加工。`build-tools/playfix-20261013/downloads/` 里另有一个下载后未使用的 `Hooded_Adventurer.glb`，以及 6 个 2 KB 的 Drive 报错页（扩展名为 .fbx / .gltf，不是模型）。

2026-10-13 岩鹰与矿车模型（**CC-BY 3.0，分发时必须署名**，与此前全部 CC0 的资源不同）：

| 作者 / 资源 | 页面 / 下载文件 | 许可 | 实际使用位置 |
| --- | --- | --- | --- |
| Poly by Google / Eagle | https://poly.pizza/m/d7CSLvsHULY ；`https://static.poly.pizza/903c859a-1f1a-45dd-a6bc-55b505244597.glb`，35,168 字节，SHA256 `caf57256ed85fe6820e840f5c0f5da7e368b2cfc28b07232cf0c0316e5abb491` | CC-BY 3.0：https://creativecommons.org/licenses/by/3.0/ | `assets/props/Eagle_PolyByGoogle.glb`：俯冲岩鹰，等比缩放并前倾，未改网格 |
| Hunter Paramore / Minecart | https://poly.pizza/m/fjvk6xVJ3u3 ；`https://static.poly.pizza/444fe116-492c-4c29-a4ed-f77528828862.glb`，683,876 字节，SHA256 `9cdc7cc2af97f6e633cc4542912a6e3ee398ec3115c058cdc3a5f45419249a9f` | CC-BY 3.0 | `assets/props/Minecart_HunterParamore.glb`：横冲矿车车体，等比缩放，未改网格 |

署名文本：“Eagle” by Poly by Google、“Minecart” by Hunter Paramore，均经 poly.pizza 以 CC-BY 3.0 提供。游戏内目前没有署名页面，对外分发前需要加上。`assets/props/` 里的 `Bird.glb`、`Minecart.glb`（Quaternius，CC0）和 `GoldenEagle_PolyByGoogle.glb`（CC-BY 3.0）是试用后未采用的候选，生产场景不加载。

2026-10-13 飞行岩鹰（上述 Eagle 的改作，仍为 CC-BY 3.0，署名时须注明已修改）：`assets/props/Eagle_Flying.glb`，54,200 字节，SHA256 `599475f25030b578c2d00730777164011317e7d66df0166c7477102715da0529`。由 `build-tools/playfix-20261013/blender/build_flying_eagle.py` 在 Blender 5.2 后台模式生成：保留原身体网格和贴图，把站姿转成水平飞行姿态，新增两段式翅膀（左右各两块程序网格，颜色取自原贴图深色区）、四根翼骨和 Flap、Dive 两个循环动画。生产场景加载的是这个文件；`Eagle_PolyByGoogle.glb` 只作为脚本输入保留。

2026-10-13 场景氛围素材（全部 CC0，无需署名）：天空全景图和三套石材贴图来自 Poly Haven（https://polyhaven.com ，CC0），十个装饰模型是 poly.pizza 上 Quaternius 的 CC0 条目。完整下载地址和 SHA256 在 `build-tools/playfix-20261013/downloads/env-downloads.json`。

| 文件 | 来源 | 字节 | SHA256 前 16 位 |
| --- | --- | --- | --- |
| `assets/env/belfast_sunset_puresky_2k.hdr` | https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/2k/belfast_sunset_puresky_2k.hdr | 4,563,204 | `273003109ca1cfb7` |
| `assets/env/monastery_stone_floor_diff.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/monastery_stone_floor/monastery_stone_floor_diff_1k.jpg | 766,525 | `8e52ec982469ce9d` |
| `assets/env/monastery_stone_floor_nor.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/monastery_stone_floor/monastery_stone_floor_nor_gl_1k.jpg | 1,063,115 | `f2f1c3e8d52c1e3a` |
| `assets/env/monastery_stone_floor_rough.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/monastery_stone_floor/monastery_stone_floor_rough_1k.jpg | 477,972 | `8d987222b727442c` |
| `assets/env/rock_face_03_diff.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_face_03/rock_face_03_diff_1k.jpg | 927,082 | `ea48e0e47ad42c8b` |
| `assets/env/rock_face_03_nor.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_face_03/rock_face_03_nor_gl_1k.jpg | 1,146,788 | `c6423169583f3171` |
| `assets/env/rock_face_03_rough.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_face_03/rock_face_03_rough_1k.jpg | 638,904 | `9e3d9a2fd7524489` |
| `assets/env/rock_boulder_dry_diff.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_boulder_dry/rock_boulder_dry_diff_1k.jpg | 859,211 | `20f653a42fb24f42` |
| `assets/env/rock_boulder_dry_nor.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_boulder_dry/rock_boulder_dry_nor_gl_1k.jpg | 802,497 | `5915fea28a97357c` |
| `assets/env/rock_boulder_dry_rough.jpg` | https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/rock_boulder_dry/rock_boulder_dry_rough_1k.jpg | 668,127 | `cc5229dd6bbdc4e8` |
| `assets/decor/DeadTree_A.glb` | https://poly.pizza/m/Mcd2zYqyww | 2,623,500 | `7650b888de1b85a3` |
| `assets/decor/DeadTree_B.glb` | https://poly.pizza/m/MlmK5488ou | 2,607,636 | `ef1ccb1f47ace965` |
| `assets/decor/Pine.glb` | https://poly.pizza/m/igSu0cPoBz | 2,147,312 | `b2cc7f2e672f94a4` |
| `assets/decor/Bush.glb` | https://poly.pizza/m/ooG6CkLyE8 | 131,172 | `917de9eee116cd43` |
| `assets/decor/Column.glb` | https://poly.pizza/m/wLubNpOTX4 | 30,328 | `801df4da3026c50a` |
| `assets/decor/ColumnRound.glb` | https://poly.pizza/m/n8ZvVFcJhl | 10,748 | `d321b2fd28e16570` |
| `assets/decor/ArchRound.glb` | https://poly.pizza/m/B9QABewqLv | 103,428 | `1592d1c51a5a8833` |
| `assets/decor/Torch.glb` | https://poly.pizza/m/Gq38E7hFZw | 23,492 | `f6a8c78b5a79175d` |
| `assets/decor/Banner.glb` | https://poly.pizza/m/svYG8KZxjq | 34,888 | `7e29fd7a4142ad3f` |
| `assets/decor/TallGrass.glb` | https://poly.pizza/m/JSIYtscPmP | 88,020 | `497f6303b662b2f6` |

使用位置：`belfast_sunset_puresky_2k.hdr` 作天空和环境光；`monastery_stone_floor` 铺路面，`rock_face_03` 用于崖壁、孤峰、石台和缺口壁，`rock_boulder_dry` 用于巨岩和路沿碎石；`assets/decor/` 的树、灌木、草、残柱、拱门、旗帜、火把摆在崖壁和路外石台上。孤峰、扶壁、石台、巨石的形状由程序用噪声生成，不是下载的模型。

2026-10-14 网页版中文字体（SIL Open Font License 1.1，原文 `assets/fonts/OFL.txt`）：浏览器里的 Godot 不能使用系统字体，中文会显示成方框，所以网页版携带字体子集。只在网页版生效（`project.godot` 的 `gui/theme/custom_font.web`），桌面和 iOS 仍用系统字体。

| 文件 | 来源 | 字节 | SHA256 前 16 位 |
| --- | --- | --- | --- |
| `assets/fonts/NotoSansSC-web-subset.otf` | Noto Sans SC Regular：https://github.com/notofonts/noto-cjk/raw/main/Sans/SubsetOTF/SC/NotoSansSC-Regular.otf（源文件 8,331,336 字节，SHA256 前 16 位 `faa6c9df652116dd`），由 `build-tools/make_web_font.py` 截取 ASCII、常用标点、GB2312 一级汉字和项目源码中出现的字符 | 1,022,080 | `45dec88092aa33c3` |

OFL 允许随游戏分发和修改（含子集化），须附带许可原文；Noto CJK 的保留字体名为 “Source”，子集文件名与字体名不含该词。对外正式发布前复核。


## 2026-10-15 麻绳与合作地形

麻绳三股捻纹、纤维法线和圆管轮廓由 `scripts/rope_view.gd` 确定性生成；腰带、绳扣、绞盘、配重和木平台由程序生成，不新增第三方素材或下载依赖。坡面、石阶和斜桥复用已记录的 `monastery_stone_floor`。桌面和 Label3D 复用已有 `NotoSansSC-web-subset.otf` 及其 OFL 许可，解决 Mac 默认字体缺字；字体文件本轮未修改。


## 2026-10-15 连续旅程素材与 Blender 动画

新增扫描贴图由 Poly Haven 提供，官方资源页面标注 CC0：

- Rob Tuytel / [Forest Leaves 02](https://polyhaven.com/a/forest_leaves_02)：林地落叶、苔藓与枝屑；1K diffuse、OpenGL normal、roughness，用于新入口森林与草地路面。
- Amal Kumar / [Wood Planks](https://polyhaven.com/a/wood_planks)：风化木板；1K diffuse、OpenGL normal、roughness，用于 Blender 房屋、推车、水车、桥、围栏及机关。

实际下载 URL、字节和 SHA-256 见 `build-tools/journey/material-sources.json`；可重跑 `build-tools/journey/download_materials.py`。仅下载六张 1K JPEG，没有下载整套高分辨率资源。

Blender 5.2.2 LTS 后台运行 `build-tools/journey/make_assets.py`，生成三种村舍、野猪、推车、可倒伏树、水车、木栅门、吊桥、围栏与路牌，共 11 个 GLB。几何由项目脚本制作，扫描贴图继续保持原 CC0 许可。按材质与父节点合并静态网格，保留动作铰点；未执行复杂渲染或动力学模拟。生成文件与 SHA-256 见 `build-tools/journey/generated-assets.json`。

`build-tools/journey/make_villager_actions.py` 导入既有 Quaternius `assets/humans/Adventurer_B.glb`（原来源与 CC0 许可见前文），新增 Throw 与 Push 骨骼动作，导出 `assets/journey/villager_actions.glb`。这是对原角色的动画改作，原资源保持不变；字节、哈希见 `build-tools/journey/villager-actions.json`。

上述资源均由 `scripts/journey_view.gd` 实际加载。野猪 Charge、车轮 WheelTurn、村民 Throw/Push、门 GateOpen 与桥 BridgeLower 按生产时间采样，暂停与存档恢复不依赖独立动画时钟。倒树使用 Blender 网格和游戏倒伏相位驱动旋转，Fall 动作同时保留在资产中。

风、河水与鸟鸣是本项目的轻量合成音源，非自然实录。更真实的动物、村民、植被与环境音需求见 `docs/JOURNEY_ASSET_BRIEF.md`。游戏内 F1 提供来源摘要。Blender 联系表仅是资产预览，不是 Godot 运行截图。

## 连续森林与村庄扩展（2026-10-15）

- `assets/landscape/`：项目 Blender 后台脚本 `build-tools/journey/make_landscape.py` 生成的乔木、远景 LOD、蕨类、草、灌木、水井、木桶、柴堆和晾衣绳。房屋与栅栏转换自项目既有 GLB，移除重复嵌入贴图后按共享材质导入。逐文件大小与 SHA-256 见 `build-tools/journey/landscape-assets.json`。
- 林地扫描纹理仍使用 Poly Haven 的 [Forest Leaves 02](https://polyhaven.com/a/forest_leaves_02)，Rob Tuytel，CC0；石板、岩面和天空沿用上文已记录资源。新地面 Shader 只改变这些纹理的连续混合与采样。
- `assets/audio/forest_birds.ogg`：isaiah658 的 [Ambient Bird Sounds](https://opengameart.org/content/ambient-bird-sounds)，原始相机环境录音，CC0。原始下载、字节数与 SHA-256 见 `build-tools/journey/environment-audio-source.json`；游戏内设置循环，并随进入森林渐入、离开森林渐出。未将其描述成村落人声。
- 本轮写实素材的程序生成替代与建议补充规格见 `docs/ENVIRONMENT_ASSET_WISHLIST.md`。


## 2026-10-15：连续树冠与断路表现

- 新增 `assets/landscape/grove_oak_7.glb`、`grove_oak_17.glb`、`grove_birch.glb` 及三份 `_lod.glb`。本项目原创程序生成，无新增第三方素材或许可限制；制作工具为本机 Blender 后台模式，生成器为 `build-tools/journey/make_canopy.py`。
- 六份网格合计约 262 KiB。每棵近景树为 1,376 个三角形，远景为 596 个；尺寸、三角形数量及 SHA-256 记录在 `build-tools/journey/canopy-assets.json`。替换连续森林实例的叶片树冠，旧模型继续保留用于历史与倒树事件。
- 新树干、断口岩壁、横木端面继续引用本清单已有的树皮、岩石和木板材质，未复制新的扫描贴图。断口网格由真实地面切片生成，沿深度增加顶点颜色，不使用独立的假碰撞地形。
- 六个新资源均已进入生产路径 `journey_landscape.gd`、区块预加载列表与对应 LOD，实际 Web 渲染证据位于 `build-tools/journey/evidence/polish/`。这些是游戏运行截图，不是 Blender 预览。

### 2026-10-15 区域怪物与反馈

树皮小怪、村庄掠袭者、矿道石卫由 `scripts/journey_enemy_view.gd` 使用 Godot 内置低面数球体、盒体和圆柱组合生成，属于本项目原创程序几何；没有新增第三方下载素材或外部服务。血条与命中火花使用 QuadMesh，命中提示音复用项目已有合成 `buckle.wav`。野猪、原投掷者及原有素材的署名保持不变。

### 2026-10-15 森林与村庄细节

- 新增 `assets/landscape/detail_*.glb` 共八件：枯木树桩、苔石、蕨类蘑菇、遮阳摊位、门廊、菜圃、灯笼及接触暗部平面。均为项目原创程序几何，由 `build-tools/journey/make_set_dressing.py` 使用 Blender 后台生成，无新下载素材、内嵌贴图或新增第三方许可。合计 342,932 字节；逐件大小、三角形与 SHA-256 见 `build-tools/journey/set-dressing-assets.json`。
- 六份 `grove_*` 树冠更新为较小的 24 组叶簇，近景 2,520 三角形、远景 1,080 三角形，合计 475,520 字节。当前值及哈希见 `canopy-assets.json`；前文 1,376 / 596 为上一版记录。密度上限从每侧每区块 115 棵调为 85 棵，继续使用距离 LOD、空间批次和缓存，不承诺单项改动降低 GPU 开销。
- 地面、树皮继续使用已记录的共享纹理；灰泥墙与接触暗部使用项目 Shader，灯笼使用自发光材质而非新增动态灯。房屋、瓦顶和门廊均在生产区块路径中加载。截图来自实际 Godot WebAssembly 渲染，见 `build-tools/journey/evidence/atmosphere/`。


## 2026-10-16 自制自然树木

- assets/landscape/natural_oak_7、natural_oak_17、natural_birch 及各自 _lod.glb：本项目使用 Blender 程序生成的树根、分叉树干、枝条、几何叶片。生成器为 build-tools/journey/make_natural_trees.py，尺寸、三角形数量、SHA-256 见同目录 natural-tree-assets.json。未下载或引入外部模型。
- 树干继续复用本文件已有来源记录的 Pine_Bark_NormalTree 贴图与法线；叶脉使用本项目 journey_natural_leaf.gdshader 程序材质，无新增外部贴图。
- 弓手、冲锋者、灰鬃狼由本项目基础网格组合生成；造型、关节动作、预警线与箭矢无新增外部素材。

## 2026-10-19 Tripo 文生 3D 怪物与村民

用户在自己的 Tripo Studio 账号（studio.tripo3d.ai）中以文生 3D 生成，Agent 在应用内置浏览器中填写提示词并提交，用户本人导出 GLB。生成参数：H3.1 高精度模型、关闭超清几何、开启纹理与去光处理、2K 贴图、三角面、面数上限 6000。导出后用 `build-tools/shrink_glb.py` 把内嵌贴图缩到 1024（JPEG q88），几何不变。

**许可待确认**：Tripo 生成内容的授权取决于账号套餐（免费套餐通常为公开且需署名，付费套餐归用户所有）。正式发布前须由用户在账号中确认，并按需补充署名。

| 文件 | 内容 | 三角面 | 字节 | SHA256 前缀 | 使用位置 |
| --- | --- | ---: | ---: | --- | --- |
| `assets/monsters/bark_sprite.glb` | 树皮苔藓林地小怪 | 5,689 | 361,532 | 7569ce716f3d23b3 | 树皮小怪（briar） |
| `assets/monsters/raider.glb` | 红头巾棍棒掠袭者 | 5,636 | 264,200 | 803bec2301efda67 | 村庄掠袭者（raider） |
| `assets/monsters/raider_slinger.glb` | 兜帽投石手 | 5,888 | 297,924 | 010ee68a28c0f001 | 林地弓手（archer） |
| `assets/monsters/stone_guard.glb` | 苔藓石魔守卫 | 5,930 | 310,716 | b41f35b1fc83c50c | 矿道石卫（sentinel） |
| `assets/monsters/brute_charger.glb` | 羊角盔重甲持盾冲锋者 | 5,719 | 295,220 | b1707349684d9611 | 破阵冲锋者（dasher） |
| `assets/monsters/grey_wolf.glb` | 灰鬃狼 | 5,858 | 258,496 | cd58c522691f2639 | 灰鬃狼（wolf），原生高约 0.73，按 2.8 倍缩放 |
| `assets/landscape/villager_farmer.glb` | 草帽农妇 | 5,936 | 313,060 | 1d31708654b28fa9 | 村庄院落布景 |
| `assets/landscape/villager_elder.glb` | 拄拐老人 | 5,673 | 278,276 | 111d2c293fa3d370 | 村庄院落布景 |
| `assets/landscape/villager_blacksmith.glb` | 铁匠 | 5,762 | 274,716 | a708760cfa91cf0f | 村庄院落布景 |
| `assets/landscape/villager_merchant.glb` | 背货商贩 | 5,654 | 327,176 | cf0a66767a6b1331 | 村庄院落布景 |

Godot 导入时把内嵌贴图提取为同目录的 `*_tripo_image_*.jpg`。模型无骨骼与动画：怪物以空关节兼容原同步逻辑，步态改为整体摇摆与蓄力后仰；六种怪物原型均已改用扫描模型（程序几何仅在资源缺失时兜底），推车/投石事件的带动画村民 `villager_actions.glb` 保持不变。

## 2026-10-19 Tripo 村庄环境与机关

用户授权在自己的 Tripo Studio 国际版账号中通过文字生成八件资产，使用 H3.1、三角面、2K 纹理、去光处理及 PBR，关闭超清几何和分部件生成。原始文件及提示词保存在工程外；本次接入的 GLB 与下载原件 SHA-256 相同。完整来源 URL、面数、哈希、大小和世界缩放见 `build-tools/journey/tripo-village-assets.json`。

| 资产 | 文件 | 三角面 | 实际使用位置 |
| --- | --- | ---: | --- |
| 民居 | `assets/landscape/tripo_cottage.glb` | 7730 | 林缘、村庄与农田住宅 |
| 工坊 | `assets/landscape/tripo_workshop.glb` | 8730 | 与民居交替的住宅外观 |
| 村口拱门 | `assets/landscape/tripo_arch.glb` | 5764 | 道路外的村庄院门 |
| 岩石路肩 | `assets/landscape/tripo_road_edge.glb` | 3351 | 森林道路外沿 |
| 树根树桩 | `assets/landscape/tripo_stump.glb` | 3395 | 林下布景 |
| 庭院杂物 | `assets/landscape/tripo_supplies.glb` | 3729 | 首排住宅旁 |
| 包铁滚石 | `assets/journey/tripo_boulder.glb` | 4363 | 连续旅程的 `stone_ball` |
| 木制撞锤 | `assets/journey/tripo_timber_ram.glb` | 4424 | 连续旅程的横向矮栏 `rail`，尺寸按原危险体适配 |

每件一个材质，保留颜色、法线、金属度/粗糙度贴图；导入采用内嵌 Basis Universal 压缩及自动网格 LOD，不再次提取重复图片。环境通过原有 MultiMesh 和区块驻留机制复用，旧资源与历史白盒入口保留。授权沿用上节“许可待确认”的边界，本次未发布或重新分发正式游戏包。


## 2026-10-19 Tripo 第二批村庄与地表资产

用户授权在已登录的 Tripo Studio 国际版用文字生成 20 件模型，并导入游戏。使用 H3.1、2K PBR、三角面、关闭超清几何；原始导出总计 100,678 三角面。它们是账户生成资源，不标注为 CC0；沿用该账户及服务适用的生成资产使用条款。

文件为 `assets/landscape/tripo_{roadside_inn,corner_townhouse,thatched_farmhouse,stone_cottage,forester_cabin,riverside_house,village_windmill,storage_barn,covered_well,produce_stall,bread_oven,stone_fountain,cobble_road_panel,flagstone_road_panel,muddy_wheel_ruts,grass_soil_border,leaf_litter_patch,stone_road_curb,crumbled_pit_rim,layered_cliff_face}.glb`。每件一个材质，保留颜色、法线、金属粗糙度贴图；导入生成 LOD 并采用内嵌 Basis Universal 压缩。

原始文件、原始与米制预处理后的 SHA-256、字节、生成页面、三角面及尺寸记录在 `build-tools/journey/tripo-village-expansion-assets.json`。入库版本仅修改根节点变换以统一米制与轴向，原网格二进制和贴图不变，20 件共 56,915,248 字节，单件均小于 5 MB。原始导出、预处理脚本及缩略图保存在工程外 `/Users/apple/ConjoinedTwins-art-assets/tripo-village-batch2-20261019/`。

实际使用：八种建筑按村庄、农田、林地、河畔分配；四种设施进入村庄院落；三种地面模型取内部区域顶视烘焙为 1024×2048 的颜色、世界法线与粗糙度纹理，用于完整连续的石板、卵石和泥路；另五种用于路肩、落叶和道路下方岩壁。原始模型保留，六张烘焙纹理、哈希和重跑命令见同一清单；纹理采用显存压缩、mipmap 和各向异性过滤。地表材质适度降低法线强度并提高粗糙度，保留路缘土壤过渡。风车为整件静态网格，叶片没有动画。

### 2026-10-19 Tripo 村庄资源减重

上述 28 件 Tripo 村庄、地表与机关 GLB 中，25 件运行时模型的内嵌贴图由 2048 缩至 1024（`build-tools/shrink_glb.py`，格式与网格不变）。卵石路、石板路、泥地车辙三件只用于烘焙地面纹理，保留 2K 原件并从导出包排除。来源版本与运行时版本的哈希均记录在 `build-tools/journey/tripo-village-assets.json` 与 `tripo-village-expansion-assets.json`。许可同前，仍待按 Tripo 账号套餐确认。

## 2026-10-19 Tripo 主角与动作重定向

两名主角由用户的 Tripo 账号文生 3D 生成（H3.1、T 姿势、2K 贴图、三角面上限 10000），再用 Tripo「人形 / Mixamo」自动绑定。Tripo 不带动画导出的 GLB，蒙皮几乎全部绑在 Hips 上，无法弯曲；因此改在动画页套用「跑步」预设后带骨骼导出，取得正确蒙皮。Tripo 的跑步动画在导入时关闭，不使用。贴图用 `build-tools/shrink_glb.py` 缩到 1024。

| 文件 | 内容 | 三角面 | 字节 | SHA256 前缀 | 使用位置 |
| --- | --- | ---: | ---: | --- | --- |
| `assets/humans/hero_01.glb` | 青色连帽外套、背包与青色提灯的男冒险者 | 9,509 | 1,964,480 | f5b4d52ff3db400f | 01 主角 |
| `assets/humans/hero_02.glb` | 橙色短斗篷、马尾与橙色提灯的女冒险者 | 9,936 | 1,975,460 | 51fc550b7465d468 | 02 主角 |

动作仍来自 Quaternius Adventurer（CC0），以及本项目用 Blender 制作的救援攀爬、拉绳动画。

- `build-tools/journey/make_humanoid_bonemaps.gd` 生成 Quaternius 与 Mixamo 两份 Godot 人形骨骼映射。Quaternius 的骨盆动画在 Body 骨上，人形 Hips 因此映射到 Body。
- 五个 GLB 导入时做重定向，并开启轮廓修正，统一为 T 姿势静止姿态。
- Adventurer_A 只作动画来源；Adventurer_B 不再加载，文件保留。

许可同前，Tripo 部分待按账号套餐确认。

### 2026-10-20 主角动画本地烘焙

01 的头/颈在 Godot `rest_fixer/fix_silhouette` 下被压进胸腔；关掉 fixer 后重定向动作又整体错位。根因是 01 的 Tripo“套跑步预设后导出”留下的静止颈部与重定向不兼容。

改为在 Blender 里做世界空间重定向：用 `build-tools/journey/bake_hero_animations.py` 把 `Adventurer_A.glb`（Quaternius，CC0）的 24 个动作逐帧烘焙到两名主角的 Mixamo 骨架，骨骼改为人形名（Hips/Spine/Chest/UpperChest/LeftUpperArm 等），导出带动画 GLB。新增：

- `CharacterArmature|Jump`：动作源没有跳跃，用 Idle 静止姿势加髋部起伏和屈膝合成 31 帧。
- `CharacterArmature|HitRecieve_1`：`HitRecieve` 的别名，游戏动作名使用。

Godot 导入改为 `animation/import=true`，清空 `retarget/bone_map`，关闭 `fix_silhouette`；游戏直接播放模型自带的 27 个 clip，不再使用 `Adventurer_A` 的运行时动画库。主角身高统一由模型包围盒给到 3.45 米，不再用 Run 姿势的骨骼跨度归一化。01/02 的三角面未变，动画让文件从约 600 KB 增至约 1.96 MB。

## 2026-10-19 双人机关模型

由用户的 Tripo 账号文生 3D 生成（H3.1、2K、去光、三角面上限 6000），用户导出 GLB，再用 `build-tools/shrink_glb.py` 把贴图缩到 1024。

| 文件 | 内容 | 字节 | SHA256 前缀 | 使用位置 |
| --- | --- | ---: | --- | --- |
| `assets/mechanisms/pivot_pillar.glb` | 带铁齿轮盖的石质转轴柱 | 242,716 | adf39c3102015d0c | 跳绳杆两侧转轴 |
| `assets/mechanisms/pressure_plate.glb` | 刻符文的圆形石踏板 | 255,244 | c811c6808c518b02 | 接力门踏板 |
| `assets/mechanisms/arch_amber.glb` | 橙色水晶石拱 | 262,360 | eea0e82fa021bd0a | 颜色门橙门（02） |
| `assets/mechanisms/arch_teal.glb` | 由橙门派生：`build-tools/recolor_glb.py` 把贴图中高饱和暖色旋转到青色 | 286,352 | 53a08eb745b46f8e | 颜色门青门（01） |
| `assets/mechanisms/crusher.glb` | 木吊架石块压锤 | 293,716 | 10d56167e47ddf0f | 已入库，本轮未接入 |

另生成的"铁箍木桶"未导出成功，滚桶外观改用既有的 `assets/landscape/barrel.glb`。许可同前，待按 Tripo 账号套餐确认。

## 2026-10-19 机关美术统一批次

由用户的 Tripo 账号文生 3D 生成（H3.1、2K、去光、三角面上限 6000），贴图用 `build-tools/shrink_glb.py` 缩到 1024。8 个文件被应用内浏览器存成隐藏临时名，按外观识别后入库。

| 文件 | 内容 | 字节 | SHA256 前缀 | 使用位置 |
| --- | --- | ---: | --- | --- |
| `assets/mechanisms/spiked_ball.glb` | 带刺铁锤球 | 248,160 | 69e14e13150d885a | 铁球 `iron_ball` |
| `assets/mechanisms/stone_post.glb` | 雕刻石界桩 | 254,468 | 27210c993738db5d | 立柱 `pillar` |
| `assets/mechanisms/spike_trap.glb` | 铁刺陷阱板 | 248,328 | 60b22dd460f19184 | 活动地刺 `active_spikes` |
| `assets/mechanisms/fire_bolt.glb` | 火焰弩箭 | 264,220 | e5f927a8d85d7506 | 火箭 `rocket` |
| `assets/mechanisms/flying_rock.glb` | 带余烬的碎岩 | 208,168 | 322edafb71d4619f | 飞石 `fly_low` / `fly_body` |
| `assets/mechanisms/steam_vent.glb` | 石圈铁栅喷口 | 252,580 | c5e197848f737499 | 地火喷口 `steam` |
| `assets/mechanisms/spiked_log.glb` | 带刺铁箍圆木 | 346,188 | 7c7f2cfd987ab692 | 旋转扫杆 `sweeper` |
| `assets/mechanisms/lift_platform.glb` | 带护栏木质升降台 | 287,032 | 35f171ba99347dbf | 升降平台 `lift` |
| `assets/mechanisms/barrel.glb` | 铁箍木桶（上一轮生成，此次找回） | 264,400 | 596563c295dac6bc | 横滚木桶 `barrel` |

摆锤吊架与石阶块也已生成但未入库（前者外形不合格，后者需与碰撞台阶严格吻合）。许可同前，待按 Tripo 账号套餐确认。

## 2026-10-19 Tripo 文生地标（第五刀）

用户在自己的 Tripo Studio 国际版账号中生产。Agent 在用户已登录的 Chrome for Testing 窗口内批量提交文生 3D 任务（H3.1 最高质量，30 积分/次），随后对每件模型做一次纹理生成（2K，30 积分/次）。导出 GLB 后用 `build-tools/journey/process_tripo_landmark.py` 在 Blender 5.2 后台减面，并把内嵌 8192 baseColor 缩到 1024。

| 运行时文件 | 三角面 | 大小 | 提示词摘要 | 实际使用位置 |
| --- | --- | --- | --- | --- |
| `assets/landscape/landmark_watchtower.glb` | 45,000 | 3.2 MB | tall medieval stone watchtower, wooden balcony, conical shingle roof, red banner | 第一章村庄段 x=38 米，缩放 22 |
| `assets/landscape/landmark_headframe.glb` | 45,000 | 3.4 MB | wooden mine headframe, timber A-frame, iron pulley wheel, weathered planks | 第三章矿道 x=-19.5 米，缩放 18 |
| `assets/landscape/landmark_shrine.glb` | 25,000 | 2.5 MB | small medieval roadside stone shrine, wooden roof, glowing lantern | 全章路侧 x=17.8 米，缩放 3 |

另生成但未接入：廊桥（缺少水面支撑）、橡树（纹理生成无贴图且下载截断）。原始导出与提示词保存工程外，不入库。许可同前：Tripo 生成内容的授权取决于账号套餐（免费套餐通常为公开且需署名，付费套餐归用户所有），正式发布前须由用户在账号中确认并按需补充署名。

## 2026-10-20 新增枪械模型与图标

- `assets/weapons/shotgun.glb`、`flamer.glb`、`launcher.glb`：本项目原创低模，由 `build-tools/journey/make_weapons.py` 在 Blender 5.2 后台用基本体拼装并导出，纯色 PBR 材质、无贴图、无外部下载，每个约 70 KB。
- `assets/ui/shotgun.svg`、`flamer.svg`、`launcher.svg`：本项目手写 SVG 剪影，与原 `smg.svg` 同一画风。
- 冲锋枪仍为 `scripts/journey_combat_view.gd` 内程序拼装的方块模型。

## 2026-10-20 录制音效：Kenney Impact Sounds 与 RPG Audio（CC0）

经用户同意，从 Kenney 官方页面公开下载链接下载两个音效包，各包内 `License.txt` 均声明 CC0 1.0（署名非必须），原文随素材保存为 `assets/audio/kenney/License_ImpactSounds.txt`、`License_RPGAudio.txt`。只挑选 57 个音效进入 `assets/audio/kenney/`；其余文件未入库。原始 OGG（共约 628 KB）用 macOS `afconvert -f WAVE -d LEI16 -c 1` 解码为单声道 16 位 WAV（共约 2.6 MB），文件名除扩展名外不变，未做剪辑、混音或效果处理。改用 WAV 是因为短音效频繁起停时，OGG 播放句柄在退出时会偶发残留，触发资源生命周期检查失败。

| 资源组 | 官方页面 / 下载文件 | 大小与 SHA-256 | 许可 | 入库文件与用途 |
| --- | --- | --- | --- | --- |
| Kenney / Impact Sounds 1.0 | https://kenney.nl/assets/impact-sounds ；https://kenney.nl/media/pages/assets/impact-sounds/87b4ddecda-1677589768/kenney_impact-sounds.zip | 800,850 字节；`029d734af1582474edf3a694d1b0cebc97c1c152f2f39fa34d4c2bafc5de77f8` | CC0 1.0 | （均为同名 `.wav`）`footstep_grass/concrete/wood_000–004`：草地、石路、木板脚步与起跳；`impactSoft_heavy_*`：落地；`impactMetal_heavy_*`：压机落下；`impactMetal_light_*`：地刺弹出；`impactMining_*`：塌陷落地；`impactPlate_heavy_*`：火焰弩命中；`impactPunch_medium_*` / `impactPunch_heavy_*`：命中、击败敌人与角色受击 |
| Kenney / RPG Audio | https://kenney.nl/assets/rpg-audio ；https://kenney.nl/media/pages/assets/rpg-audio/8e99002d76-1677590336/kenney_rpg-audio.zip | 964,837 字节；`6dbeaf8544da958d8f2adcb4a4a4b76c1ade34a05f8ab9edccd327da7375f38b` | CC0 1.0 | `creak1–3`：塌陷路面开裂；`metalLatch` / `metalClick`：换弹开始与上膛；`doorOpen_1–2`：合作门打开 |

运行时由 `scripts/sfx.gd` 的 `VARIANTS` 按组随机选取，并叠加音高 ±5%、音量 ±2 dB 变化；原合成音效保留用于界面与未替换的事件。

## 2026-10-20 章节音乐（OpenGameArt，CC0）

经用户选定并同意下载，从各曲 OpenGameArt 页面的公开下载链接获取原文件，未改动音频内容，只在 Godot 导入设置中开启循环（`loop=true`）。各页面许可均为 CC0 1.0；Cynic Battle Loop 页面附有致谢原作曲 Alex Smith（cynicmusic.com / pixelsphere.org）的说明，已在游戏 F1 素材署名中列出。

| 曲目 / 作者 | 页面 / 下载文件 | 大小与 SHA-256 | 入库文件与用途 |
| --- | --- | --- | --- |
| Forest Ambience / TinyWorlds | https://opengameart.org/content/forest-ambience ；`https://opengameart.org/sites/default/files/Forest_Ambience.mp3` | 716,670 字节；`9850aa1d0d5d66bd9c5daf8bb77c6d852e01f2f4de22f283bd5621e8bed13b75` | `assets/audio/music/forest_ambience.mp3`：第一章“穿林入村”探索层；作者说明可无缝循环 |
| Village, 2018 / Loyalty Freak Music（Komiku） | https://opengameart.org/content/village-2018 ；`https://opengameart.org/sites/default/files/Komiku%20-%20Tale%20on%20the%20Late%20-%2005%20Village%2C%202018.mp3` | 2,831,285 字节；`f0250f304d6ab11fcc3658a6606d38d1425c586d124524b814597abf8d1954c9` | `assets/audio/music/village_2018.mp3`：第二章“水车河道”探索层；页面未说明可循环，首尾衔接待试听 |
| Cathedral in the Forest / congusbongus | https://opengameart.org/content/cathedral-in-the-forest-ambient-loop ；`https://opengameart.org/sites/default/files/forest_2_0.ogg` | 2,947,211 字节；`b9e05a1fcd5869b63193515e2a9c1bd578906a78e628e307f19527d387262593` | `assets/audio/music/cathedral_forest.ogg`：第三章“矿道归航”探索层；作者说明无缝循环 |
| Cynic Battle Loop / Ferk（原曲 Alex Smith / cynicmusic） | https://opengameart.org/content/cynic-battle-loop ；`https://opengameart.org/sites/default/files/cynicbattleloop_0.ogg` | 1,861,815 字节；`39195451e23c929dce5bed687b0d78454c32eb574b06713ea3d079b6b37b6a86` | `assets/audio/music/cynic_battle_loop.ogg`：三章共用战斗层，附近敌人察觉时淡入 |

四首合计约 8.4 MB，单个文件均小于 5 MB。

## 2026-10-20 真实录音：枪声、火焰与机关（freesound.org，CC0）

为替换合成枪声与机关提示音，从 freesound.org 选取 31 段许可均为 CC0 1.0 的实录音效（署名非必须），逐条记录在 `build-tools/journey/recorded-audio-sources.json`：来源页面、下载地址、作者、许可、原始文件 SHA-256 与字节数、原标题与描述、处理步骤。下载对象为各页面公开的 HQ 预览 MP3（约 128 kbps），未登录、未下载原始高码率文件。处理：解码并缩混为单声道 44.1 kHz 16 位 WAV，截取所需片段、去直流、短淡入淡出，峰值归一化到 −1 dBFS；循环素材按节奏周期截取并做首尾等功率交叉淡化，导入时设为正向循环（`edit/loop_mode=2`）。部分原始电平很低的素材增益较大（锤击约 +14~16 dB、滚石约 +14 dB、机械低鸣约 +17 dB），底噪随之抬高，待实机试听确认。入库于 `assets/audio/recorded/`，共约 2.7 MB，单个文件均小于 1 MB。

| 组（`<组>_<序号>.wav` 或单个 `<组>.wav`） | 作者 / freesound 编号 | 游戏内用途 |
| --- | --- | --- |
| `smg_shot` ×4 | qubodup #854231、#854207、#854179、#854177 | 冲锋枪射击 |
| `shotgun_shot` ×3 | AnthonyChan0 #159709；qubodup #184418、#854652 | 霰弹枪射击 |
| `launcher_shot` ×2 | qubodup #162402；LeMudCrab #163458 | 榴弹发射 |
| `explosion` ×2 | qubodup #171971、#855898 | 榴弹落地爆炸 |
| `flame_start` ×2 | ldezem #386379；AslakHostaker #395038 | 喷火器点火 |
| `flame_loop` | AslakHostaker #395039 | 喷火器持续火焰（循环） |
| `fire_crackle_loop` | cyberthilop #558983 | 喷火时叠加的火焰噼啪（循环） |
| `steam_hiss` ×2 | Engineer_815 #493558；wubitog #234782 | 蒸汽机关蓄压与喷射、压机泄压 |
| `hammer_swing` ×2 | Joao_Janz #485243、#485246 | 摆锤挥落 |
| `spike_spring` ×2 | fractionalist #644245；baefild #276589 | 地刺弹出 |
| `wood_creak_heavy` ×2 | LampEight #402465；kyles #450381 | 塌陷路面开裂、倒树与摆木预警 |
| `tree_fall` ×2 | Kinoton #494071；ecfike #139952 | 大树倒下 |
| `rocket_whoosh` ×2 | qubodup #840511；craigsmith #675780 | 火焰弩发射飞行 |
| `stone_roll` | klakmart #108273 | 滚石、铁球与木桶滚动（循环） |
| `cart_roll` | pnwheeler #831723 | 推车冲出（循环） |
| `machine_loop` | lagezon #232882 | 工业机关运转低鸣（循环） |
| `stone_slide_door` | NahuelMartinez #844329 | 合作门开启时的门体拖地摩擦 |

运行时由 `scripts/sfx.gd` 的 `RECORDED_GROUPS` 加载，短音效与 Kenney 录音同样按组随机选取；循环声经 `loop_at` 按键复用定位播放器，暂停、失败与重开时全部停止。原合成 `gunshot` 等 PCM 保持不变（`tests/release_integration.gd` 校验），只是生产调用改用实录。
