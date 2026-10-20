# 画面质感第五刀：Tripo 地标与村庄剪影

日期：2026-10-19。分支：`art/lookdev-landmarks`（从第四刀 `art/lookdev-ui@46a1d03` 继续；第一轮收尾时随 P1–P6 一起合入 `test`）。

## 问题

前四刀把镜头、光照、路面和界面处理完之后，场景仍缺少"远看能记住的东西"：每一段路都靠同一批房屋、树木和机关重复，走路时没有方向感。第四刀之前生成的 Tripo 资产偏小件，没有能跨越 80–120 米仍保持清晰剪影的地标。

## 生产流程

在用户已登录的 Tripo Studio 国际版中，用文生 3D 批量提交 4 个任务（H3.1 最高质量，30 积分/次），完成后再对每件模型做一次纹理生成（2K，30 积分/次）：

| 资产 | 提示词摘要 | 原始面数 | 导出 |
| --- | --- | --- | --- |
| 矿道井架 | wooden mine headframe, timber A-frame, iron pulley wheel, weathered planks | 1,878,575 | 1.88M 三角面，8192 baseColor |
| 石质瞭望塔 | tall medieval stone watchtower, wooden balcony, conical shingle roof, red banner | 1,937,725 | 1.94M，8192 |
| 路边神龛 | small medieval roadside stone shrine, wooden roof, glowing lantern | 1,885,306 | 1.89M，8192 |
| 廊桥 | wooden covered bridge, shingled roof, timber trusses, stone abutments | 1,794,817 | 1.79M，8192 |

导出后用 [process_tripo_landmark.py](build-tools/journey/process_tripo_landmark.py) 在 Blender 5.2 后台模式减面并把 8192 贴图缩到 1024：

- 井架、瞭望塔：45,000 三角面，约 3.4 MB / 3.2 MB。
- 神龛：25,000 三角面，约 2.5 MB。
- 廊桥：45,000 面，但未接入（见下）。

## 接入

- 第一章村庄段：石质瞭望塔，x=38 米、缩放 22、每 3 个区块一座；在 [journey_landscape.gd](scripts/journey_landscape.gd) 的 `decorate` 中生成。
- 第三章矿道：木制井架，x=-19.5 米、缩放 18、每 3 个区块一座；在 [journey_chunk_plan.gd](scripts/journey_chunk_plan.gd) 的 `make` 中生成（第二、三章不走 `decorate`）。
- 全章路侧：石质神龛，x=17.8 米、缩放 3、每 4 个区块一座。
- 全部为展示层，不参与碰撞、支撑和危险判定；玩家活动范围仍在道路内。

## 未接入

- **廊桥**：河道两侧只有低处水带，桥放在草坡上近看像木棚，没有真实水面和桥台支撑；本轮不接入，原始 GLB 只保留在工程外。
- **橡树**：纹理生成没有产出贴图，且导出下载被截断（文件头长度与实际大小不符），本轮不接入。

## 验证

| 项目 | 结果 |
| --- | --- |
| 固定种子截图 | `builds/look-review-20261019-landmarks-final/`（9 张）；地标近景 `builds/look-review-20261019-landmarks3/` |
| `tripo_village_assets` / `tripo_village_expansion` | 807 / 4,831 项，全部通过 |
| `check_journey_performance.py` | 26 项全部 PASS，退出码 0；报告见 `~/ConjoinedTwins-perf-reports/lookdev-landmarks-final/` |
| 生产入口 headless 启动 | 退出码 0 |
| 实际帧时间（M4 / 720p / 关垂直同步 / 180 帧） | 森林 14.5 ms、村庄 7.9 ms、设施 6.0 ms（长时间空闲后）；连续跑基准或 Blender 后同一场景会升到 19–21 ms，属于热降频；隐藏地标前后差异在噪声内 |

## 未验收

- 没有真人试玩。瞭望塔和井架在不同镜头距离下会被路边房屋或机关短时遮挡，是否需要调整 x 位置需要实际跑图确认。
- 神龛尺寸较小，远看更像路边石堆，尚未达到"地标"强度。
- 地标没有碰撞和遮挡剔除优化，只有单实例 MultiMesh；后续增加数量时需要复测绘制调用与三角面。
- 只在 M4 / Metal / 720p 测过；网页、iOS 与 Windows 未运行。
- Tripo 生成内容的授权取决于账号套餐，正式发布前仍需用户确认。
