# v0.8.0 联机验收证据 / Online acceptance evidence

2026-10-11，原生 Windows 测试；没有使用 Docker、WSL、虚拟机或 Android 模拟器。游戏版本 0.8.0，Android versionCode 13。以下记录分别验证不同层次，不以总数替代实际游玩验收。

| 检查 | 结果 | 原始证据 |
| --- | --- | --- |
| 公平双真人、独立进化、投影与本地弹窗 | 35/35 | [核心契约](core-contract.json)、[日志](core_contract-source.txt) |
| HTTP / WSS / 数据库实际集成 | 23/23 | [独立包网络检查](server-bundle-integration.json) |
| 导出 Windows 内嵌资源的两个原生客户端 | 19/19，无脚本错误 | [客户端检查](native-client-playable.json)、[日志](client_playable-embedded.txt) |
| 原生裁判、网关、独立数据库强制终止与恢复 | 10/10 | [故障检查](native-faults.json) |
| 独立服务端 ZIP、完整启停、维护排空、保留数据再启动 | 10/10 | [交付包检查](server-bundle.json) |
| Go 掉线预算、平台免罚、独立序号等控制层 | 7/7 | [Go 测试事件](go-control.jsonl) |
| 本机十局、二十订阅者、30 秒负载 | 4/4；最低 29.96Hz、平均 30.14Hz、ACK P95 260ms | [负载测量](native-load.json) |
| 原有单机交互回归 | 159/159 | [日志](interaction_regression-source.txt) |
| AI 难度和首都进化回归 | 187/187 | [日志](difficulty_capital-source.txt) |
| Android 应用标识、版本、仅 INTERNET 权限、身份插件、16KB 载入段 | 两个 APK 共 18 项通过 | [APK 检查](online-android.json) |
| Android 签名、对齐与图标资源 | 通过 | [签名/对齐](android-finalization.json)、[图标](launcher-branding.json) |
| SIDcloud 隐私页及路由/下载 | HTTPS 可达，六项路由和下载检查通过 | [线上页面](privacy-live.json)、[下载](privacy-downloads.json) |

四张截图位于 [联机实机图目录](../../media/v0.8.0/)，来源是实际导出 Windows 游戏资源的原生渲染。包括大厅、六位码房间、战斗与结算；同一测试期间使用独立受保护身份，并执行真实准备、招募、自动重连和客户端重启恢复。

[发布文件校验回执](release-artifacts.json) 记录五个二进制文件的大小和 SHA-256。GitHub Release 的 `SHA256SUMS.txt` 应与该回执一致。运行时匿名凭据、数据库内容、签名私钥和本机配置不属于验收材料，也不进入仓库或发布包。

**验证边界：**没有实体 Android 设备，因此真机游玩、后台挂起/恢复、系统杀进程及 Wi-Fi/蜂窝切换未验证；十局负载是开发机本地测量，不是公网容量承诺。数据库为单主，进程崩溃恢复不证明整机或磁盘损坏后零数据丢失。未进行原生 race detector、跨地域弱网和商业峰值测试；没有提供已部署的公共对战服务。

## English

These are native Windows checks, including two real Godot clients loading the exported Windows resource pack, a persistent HTTP/WSS authority, process-crash recovery, and the extracted standalone server's start/drain/stop/restart workflow. All listed checks passed. Release receipts bind the five binary artifacts to their inspected source files by SHA-256.

Android APKs were exported, signed and inspected; physical Android play and mobile lifecycle remain untested. Load measurements cover only ten local matches for thirty seconds. This release uses single-primary PostgreSQL and does not claim host-loss resilience, public-region capacity, race-detector coverage or a hosted matchmaking endpoint.
