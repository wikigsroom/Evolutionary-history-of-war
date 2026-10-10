# 项目文档

当前方向：方向 1。最新原生版本为 Godot 0.8.0《纪元急袭》，提供 Windows 便携包和已签名 Android APK。十时代源码、素材及验收结果见 [0.7.0 交付报告](epoch-rush/godot-v0.7-ten-eras-report.md)；下一轮选择与反制设计见 [玩法深化与对等博弈](epoch-rush/godot-v0.7-gameplay-depth-and-fair-duels.md)。Android 真机与原生 iOS 发行验证尚未完成。以下 v0.1–v0.3 文档及归档保留对应历史状态。

- [v0.8.0 真人联机交付](epoch-rush/godot-v0.8-online-report.md)：原生服务端、双端联机菜单、自由匹配、六位码、断线与重启恢复；[操作](../services/online-gateway/README.md)、[发布](releases/v0.8.0.md)、[证据](qa/v0.8.0/README.md)。
- [联机体系详细设计](epoch-rush/online-system-design.md)：自由真人匹配、六位码创建/加入、权威对局、断线与裁判恢复；配套 [协议](epoch-rush/online-protocol.md)、[实施与验收](epoch-rush/online-implementation-and-acceptance.md)、[参数草案](epoch-rush/online-defaults.example.json)。原始设计保留；当前实现见 [v0.8.0 联机交付](epoch-rush/godot-v0.8-online-report.md)。
- [v0.7.3 长屏铺满与安全区](releases/v0.7.3.md)：等比扩展、边到边全屏、UI 挖孔避让；[验收截图](qa/v0.7.3/README.md)。
- [v0.7.2 难度与首都进化](releases/v0.7.2.md)：三档 AI 经济系数、首都进化按兵种生命比例增长并回满；[验收记录](qa/v0.7.2/README.md)。
- [v0.7.1 品牌与随机 BGM](epoch-rush/godot-v0.7.1-branding-bgm-report.md)：双端最新骑士图标、透明文字 LOGO、Yourset 四首随机轮播与重新打包；[发布说明](releases/v0.7.1.md)。
- [Logo 上传版](epoch-rush/logo-upload-spec.md)：透明游戏名 PNG，2880×960 主版和 1440×480 备用版；满足 4 MB 以内、宽 ≥1280 或高 ≥720 的最新规格。
- [Age of War前两部复核与重做方案](epoch-rush/20-Age-of-War前两部复核与重做方案.md)：2026-10-05重新检查UI、动作、时代与占位；记录实际缺陷、原作规则、复现证据和后续验收条件。v0.2.0的技术交付不代表这些质量问题已经解决。
- [方向1完整设计体系](epoch-rush/README.md)：18份主文档，角色、成长、掉落、技能、打击、美术、故事、交互、跨端架构与验收。
- [v0.2.0界面、战场与动作改版](epoch-rush/19-界面战场与动作改版.md)：整体UI、完整战线平移、流程修复、26套动作、建筑反馈与实际验证。
- [v0.1.0首版实现记录](epoch-rush/18-首版实现与验证.md)：首版交付与对应验证边界。
- [方向1结构化数据](epoch-rush/data/README.md)：17个JSON配置与完整内容ID。
- [方向1素材制作任务表](epoch-rush/素材制作任务表.md)：197项逻辑素材的规格、阶段与状态。
- [方向1设计校验报告](epoch-rush/设计校验报告.md)：引用、构筑、数量、演算和链接检查。
- [方向1设计 v0.1 归档](archive/2026-10-04-epoch-rush-design-v0.1/README.md)：包含完整文档、数据、提示词和SHA-256文件清单的独立快照。
- [下载方向1设计 v0.1 完整归档包](archive/2026-10-04-epoch-rush-design-v0.1.zip)。

- [五个游戏方向的完整提案](游戏方向提案.md)：命名、构思、核心爽感、特色机制、进化路线、美术与实现范围。
- [五方向风格对比图](../output/imagegen/direction-comparison.png)：五张通过指定 Sub2API 路线生成的战场风格示意。
- [本地归档索引](archive/README.md)：按日期和版本查阅文档归档。
- [五套预案 v1 归档](archive/2026-10-03-game-directions-v1/README.md)：五份独立预案、总案、共用实施范围、风格图、原始提示词与校验清单。
- [下载 v1 完整归档包](archive/2026-10-03-game-directions-v1.zip)。

后续在本目录保存实现进度、素材制作结果、多端构建说明与试玩记录；版本归档保留对应阶段的实际状态。

- [十时代玩法深化与对等博弈](epoch-rush/godot-v0.7-gameplay-depth-and-fair-duels.md)：下一轮设计提案，包含集结、行为克制、进化投资、战术预算、公平 AI 和实施切片；新增机制尚未进入运行规则。
