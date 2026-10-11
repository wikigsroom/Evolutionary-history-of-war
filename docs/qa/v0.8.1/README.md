# v0.8.1 正式服务验收 / Public-service evidence

2026-10-11，原生 Windows 导出资源连接新加坡正式 HTTPS/WSS 服务。报告记录真实客户端、真实 PostgreSQL 与原生 Godot 裁判，不使用容器、WSL 或虚拟机。完整说明见 [交付报告](../../epoch-rush/godot-v0.8.1-public-online-report.md)。

| 证据 | 检查范围 |
| --- | --- |
| [public-client-playable.json](public-client-playable.json) | 22 项，默认官方地址、明确连接、六位房间、构筑、宽屏、招募、重连、客户端重启、共同结果 |
| [public-network.json](public-network.json) | 23 项，HTTPS/WSS、指令去重、隐私、恢复、20 人争抢两席、真人匹配 |
| [public-recovery.json](public-recovery.json) | 11 项，只杀游戏主进程与中断游戏 SQL 连接；原局、游标、已确认状态和后续动作/结算恢复 |
| [queue-liveness.json](queue-liveness.json) | 7 项，65 秒旧身份与 65 秒在线等待后仍可接受真人对局 |
| [public-load.json](public-load.json) | 4 项，新加坡目标主机两局四人、约 30 秒连续模拟和共同结果；路线延迟仅适用于本次工作站 |
| [server-operations.json](server-operations.json) | 12 项，DNS/TLS、loopback、systemd、自启定时器、专用账号、manifest、备份实际恢复、日志/资源保护 |
| [server-bundle.json](server-bundle.json) | 10 项，最终 Windows 私有服 ZIP 的启动、排空、持久结果与重启 |
| [server-bundle-integration.json](server-bundle-integration.json) | 23 项，最终 Windows 私有服的实际协议检查 |
| [android-packages.json](android-packages.json) | 两包版本/权限/Keystore/模拟数据/网络菜单与字体一致性/16 KB 对齐/私密文件排除；未进行真机游玩 |
| [android-finalization.json](android-finalization.json) | 最终双 APK 的签名、ZIP 对齐与文件哈希 |
| [launcher-branding.json](launcher-branding.json) | 实际 Windows PE 和 APK 图标资源 |
| [font-coverage.json](font-coverage.json) | 两款游戏字体覆盖当前原生脚本中的全部中文 |
| [windows-online-content.json](windows-online-content.json) | 实际 Windows PCK 编译网络/菜单和导入字体哈希，APK 逐项比对基准 |
| [privacy-live.json](privacy-live.json) | 6 项，正式隐私域名及路由/文件一致性；DOCX 最新 15 页逐页复核 |
| [go-control.jsonl](go-control.jsonl) | 7 项 Go 控制层单元检查；另运行 go vet |
| [release-artifacts.json](release-artifacts.json) | 六个二进制发布物的版本、字节数与 SHA-256 |
| [media-provenance.json](media-provenance.json) | 五张实机图的哈希和本次最终 Windows EXE 哈希 |

[客户端原始记录](public-client.txt) 与 [故障恢复记录](public-recovery.txt) 保留简短可读日志；匿名身份密钥、访问令牌、服务器环境文件和签名材料不进入此目录。历史版本证据保留在各自目录，不重复声明为本版新测试。

实机图见 [官方连接入口](../../media/v0.8.1/online-consent.png)、[大厅](../../media/v0.8.1/online-hall.png)、[双人房间](../../media/v0.8.1/online-room.png)、[对战](../../media/v0.8.1/online-battle.png) 与 [结算](../../media/v0.8.1/online-result.png)。画面来自本版 Windows 内嵌 PCK 和真实公共比赛。

These reports apply to the exact recorded release artifacts and deployment. Public capacity was measured at two matches/four subscribers for roughly 30 seconds. Physical Android, long-duration uptime, off-site disaster recovery, disk/host loss and multi-host failover are not certified. Credentials and private runtime data are excluded from public evidence.
