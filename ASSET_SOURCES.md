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
