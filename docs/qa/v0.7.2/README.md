# v0.7.2 验收 / QA

日期：2026-10-10。主变更为 AI 经济难度和独立进化时首都生命增长与满血恢复。

| 证据 / Evidence | 验证范围 / Coverage |
| --- | --- |
| [difficulty-capital.json](difficulty-capital.json) | 187/187：三档经济、起始时代、实际收入、读档与重复金币、双方九次进化、满血与增长比例、对方独立、遗物与关卡加成、封顶和死亡限制 |
| [rules-regression.json](rules-regression.json) | 420/420：十时代、伤害、支援预算、独立进化、地图及主将生命比例 |
| [restore-regression.json](restore-regression.json) | 45/45：旧五时代和当前十时代存档 |
| [balance-comparison.json](balance-comparison.json) | 旧版与新版各九场、最多 600 秒，三个种子、同一自动玩家，未结束样本不记为胜利 |
| [extended-hard.json](extended-hard.json) | 一场挑战 AI 存活至 1500 秒、升至第六时代 |
| [windows-embedded-content.json](windows-embedded-content.json)、[windows-balance-checks.json](windows-balance-checks.json) | 同版本 Godot 从空目录加载正式 EXE 的内嵌包：应用版本 0.7.2、19 数据 JSON、252 图集及 187 项规则检查 |
| [windows-standalone-boot.json](windows-standalone-boot.json) | 正式 Windows EXE 无源工程启动，强制 90 帧退出；没有脚本或解析错误，保留既有退出资源诊断 |
| [cross-platform-scripts.json](cross-platform-scripts.json) | 正式及调试 APK 的核心规则、对战界面和菜单字节码与经过规则检查的 Windows 内嵌包一致，六项 SHA-256 比较通过 |
| [package-asset-checks.json](package-asset-checks.json) | 两个 APK 各 19 数据文件、图集、字体及音乐导入一致；6980 非空帧、字体覆盖、Windows ZIP CRC 与 EXE 字节一致 |
| [launcher-branding.json](launcher-branding.json)、[android-finalization.json](android-finalization.json) | 44 图标／版本条目；版本 0.7.2、Android code 11，签名与 16 KB 对齐通过 |
| [delivery.json](delivery.json)、[SHA256SUMS.txt](SHA256SUMS.txt) | 四个最终程序包的实际字节数与 SHA-256 |

配置和结论见 [中英发布说明](../../releases/v0.7.2.md)。完整原生测试及编译日志保留于本机 `output/qa/2026-10-10-balance/`。

Deterministic samples do not establish human win rates. Android physical-device testing remains outstanding. Windows forced-quit boot samples retain the previously observed ObjectDB/resource exit diagnostics; they do not establish leak-free shutdown.
