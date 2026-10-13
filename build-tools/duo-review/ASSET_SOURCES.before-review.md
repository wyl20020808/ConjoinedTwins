# 归航 Demo 资产来源与许可

本轮通过普通 HTTPS 请求实际访问官方页面、检索其公开下载链接并下载资源，没有浏览器登录、购买或 API Key。官方网页原文证据为 `build-tools/art-demo/mech.html`、`industrial.html`；下载与 SHA256 清单为 `build-tools/art-demo/sources.json`。所用两组均由官方页面声明 CC0，可修改并随测试包再分发。

| 作者 / 资源组 | 官方页面 / 下载文件 | 许可 | 实际使用位置 |
| --- | --- | --- | --- |
| Quaternius / Animated Mech Pack | https://quaternius.com/packs/animatedmech.html；官方页面链接公共 Drive 目录 `1sueV_4CGMpZC8y30mWfgKK9UaT3mkHBX`，Flat Colors / glTF 中 George.gltf 与 Leela.gltf | CC0：https://creativecommons.org/publicdomain/zero/1.0/ | `assets/mechs/George.gltf`：01 青色识别、宽肩四肢轮廓；`Leela.gltf`：02 橙色识别、柱状头身轮廓；生产 `build_robots()` 实际加载 |
| Kenney / City Kit Industrial 2.0 | https://kenney.nl/assets/city-kit-industrial；https://kenney.nl/media/pages/assets/city-kit-industrial/0ec35b139d-1788171848/kenney_city-kit-industrial_2.0.zip | CC0；原文 `assets/industrial/License.txt` | building-a/f/k/p：道路两侧建筑与远景；detail-tank/chimney-large：侧边设施；shipping-container-a：可碰撞货箱；Textures/colormap.png：共享调色板，全部由生产场景加载 |

角色直接下载：George `https://drive.google.com/uc?export=download&id=1CEATvzzC1w198kD9DLTamgMD8LsRwV1I`；Leela `https://drive.google.com/uc?export=download&id=1BOAP-hwB8VlR6S9veirq5407h4dp0Vfq`。每个 glTF 自含模型数据；仅下载两个角色，没有下载全套角色工程。工业归档 SHA256：`5b381164e5760f3830a2dbee43b972deee38b2a695d091b56e238ab2910c96d2`。仅选七份 GLB 和其贴图进入运行资产目录；FBX、其他道具和来源网页留在制作目录。

加工与呈现：保持原模型网格和调色板，按包围盒统一尺度；工业模型额外限制宽度以避免遮挡道路，材质绑定原共享贴图并适度调暗。角色使用原 Idle 动画的静态采样姿态后暂停，搭配程序滑行底座，没有使用 T-pose，没有开发新的跑步动画。无需 Blender 加工。

本项目程序制作：道路模块、车道线、边界/栏杆、灯杆与灯带、透明能量屏障、区段/终点门架、角色识别灯和双人能量线、天空与定向灯、HUD 和菜单。它们补齐下载资产的环境和交互表达；两个机器人、建筑、货箱与设施均为实际下载资产。

决策者审查返修：相同 Kenney building-k/p/f 资源另用于三排城市尺度远景，新增程序连续港区承托面；没有新增下载或许可依赖。屏障显示改为与逻辑矩形一致的完整能量体积和地面危险投影。
