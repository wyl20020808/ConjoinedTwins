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
