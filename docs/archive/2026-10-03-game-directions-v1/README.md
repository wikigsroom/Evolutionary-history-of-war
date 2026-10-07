# 五套游戏预案归档 · v1

归档日期：2026-10-03（Asia/Taipei）。归档编号：GD-20261003-v1。

本归档记录 Age of War 类游戏的五套候选方向，用于后续方向选择和实现参考。当前状态为「候选方案，待选择」；命名均为工作名，视觉图为风格提案。

## 查阅入口

- [完整总案](游戏方向提案.md)：保留五套预案及全部共用实施说明。
- [方案对比](方案对比.md)：比较核心爽感、特色决策、美术与复杂度。
- [共用实施范围](共用实施范围.md)：技术、素材、动画、声音、测试与范围控制。
- [五方向风格对比图](assets/direction-comparison.png)。
- [文件与校验清单](manifest.json)。

## 五套独立预案

| 编号 | 中文名称与独立文档 | 英文名称 | 视觉参考 | 生成来源 |
| --- | --- | --- | --- | --- |
| 01 | [一线万年：文明冲锋](plans/01-文明冲锋.md) | Epoch Rush | [风格图](assets/directions/01_epoch_rush.png) | [提示词](prompts/01_epoch_rush.txt) |
| 02 | [齿轮边境：移动要塞](plans/02-移动要塞.md) | Gearfront | [风格图](assets/directions/02_gearfront.png) | [提示词](prompts/02_gearfront.txt) |
| 03 | [菌潮：进化吞噬](plans/03-进化吞噬.md) | Bloomwar | [风格图](assets/directions/03_bloomwar.png) | [提示词](prompts/03_bloomwar.txt) |
| 04 | [香火纪元：山海护城](plans/04-山海护城.md) | Spiritbound | [风格图](assets/directions/04_spiritbound.png) | [提示词](prompts/04_spiritbound.txt) |
| 05 | [玩具起义：课桌战争](plans/05-课桌战争.md) | Desk Rebellion | [风格图](assets/directions/05_desk_rebellion.png) | [提示词](prompts/05_desk_rebellion.txt) |

![五方向风格对比](assets/direction-comparison.png)

## 归档说明

来源为项目内 `docs/游戏方向提案.md` 及 `output/imagegen/` 下的原始图像与提示词。完整总案保留原文正文，仅将图像相对链接改为归档内路径；独立文档按原总案中的五个方向提取，附上版本、索引和提示词入口。

归档内包含五张 1536×1024 PNG 战场风格图、一张 2100×1540 PNG 对比图和五份原始生成提示词。生成路线记录为 Sub2API / `sub2-image-gen`，请求模型 `gpt-image-2.5`，high 质量、PNG 格式。

`manifest.json` 记录归档文件路径、字节数及 SHA-256，以便检查复制或解压后的完整性。ZIP 包在上级归档目录中，包含本文件夹的全部内容；解压后由本文件开始查阅。

本目录作为 v1 快照保存。后续方向修订使用新的版本归档，并在项目文档索引登记。
