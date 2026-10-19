# Tripo 村庄资源减重

日期：2026-10-19。分支：`chore/tripo-asset-diet`，起点为 `art/tripo-village-expansion@76a2a72`（该分支基于本地 `test@4485080`，尚未合并进 `test`）。

## 改动

- 25 件运行时 Tripo GLB（首批 8 件、二批中除三种路面外的 17 件）的颜色、法线和金属粗糙度贴图从 2048 缩到 1024。
  - 用 `build-tools/shrink_glb.py` 原地重写，JPEG 仍为 JPEG（q88），PNG 仍为 PNG。
  - 网格、材质、扩展字段与根节点变换不变。
  - 导入设置不变：Basis Universal、自动 LOD、阴影网格。
- 卵石路、石板路、泥地车辙三件路面 GLB 只供 `bake_tripo_ground.gd` 烘焙地面纹理，运行时不实例化。
  - 保留 2K 原件，便于以后重新烘焙。
  - 在 `export_presets.cfg` 的 macOS、iOS、Web 三个预设中排除。
- 两份资产清单增加 `runtime_texture_size`、`runtime_sha256`、`runtime_bytes`，以及路面的 `excluded_from_export` 字段。原 `sha256`/`bytes` 仍对应 2K 来源版本。

## 结果

| 项目 | 减重前 | 减重后 | 合并前 test |
| --- | ---: | ---: | ---: |
| 28 件 Tripo GLB 磁盘体积 | 82.7 MB | 32.2 MB（含 8.3 MB 仅烘焙用路面） | — |
| 纹理显存峰值（M4，六观察点依次巡检后） | 638 MB | 341 MB | 229 MB |
| 村庄平均帧时间 | 8.57 ms | 8.73 ms | 8.61 ms |
| 森林平均帧时间 | 15.07 ms | 15.12 ms | 14.94 ms |

相对合并前的 `test`，新增显存由约 410 MB 降到约 112 MB。帧时间在误差范围内不变。

近景截图对比见工程外 `builds/asset-diet/*-crop.png`（不入库）：在固定游戏镜头距离下，房屋、水井、摊位的贴图细节与 2K 基本无差别。

## 未验证

- 没有重新导出 Mac / Web / iOS 包，排除规则对实际包体积的影响未实测。
- 显存数字来自 Godot `RENDER_TEXTURE_MEM_USED`，只在 M4 上测过。8 GB 内存机型、Intel 核显、网页与移动端未测。
- 用户试玩未进行。
