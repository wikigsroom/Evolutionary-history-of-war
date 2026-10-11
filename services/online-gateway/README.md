# 纪元急袭原生联机服务端 / Epoch Rush online authority

v0.8.1，协议 1.0，规则 `pvp-classic-v1`。Go 接入与 PostgreSQL 持久化配合独立 Godot Headless 裁判，支持原生 Windows x64 自部署和 Linux amd64 正式服务，不需要 Docker、WSL、虚拟机、Node.js 或浏览器。游戏客户端另行下载。

## 官方公网服务

SIDcloud 正式地址 **https://jyqx-server.sidcloud.cn**，双端 0.8.1 默认选择。主菜单 → 联机 → 同意并连接 → 自由匹配或双方相同六位码 → 双方准备/接受。无需解压服务端即可使用官方服。数据在新加坡处理；首次连接前有明确提示，离线进度不上传。当前共享 1 GB 主机限制 **两局 / 四玩家**，不是 Windows 私有服的十局默认容量。

已部署可信 HTTPS/WSS、systemd 自启与重启、专用 PostgreSQL 16 库、健康与磁盘检查、每日备份及实际隔离恢复验证。Linux TAR 包和 [运维说明](deploy/linux/README.md) 提供纯模拟与配置模板，Godot 引擎与数据库需另外安装；Windows ZIP 保留完整原生运行环境。

## 解压即用

下载 `Epoch-Rush-Server-0.8.1-Windows-x64.zip`，完整解压，使用 Windows PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-Server.ps1
```

启动脚本初始化独立 PostgreSQL、导入纯战斗工程、后台启动接入服务，并等待健康检查成功。默认端口 **28187**，数据库只监听本机 **54329**；默认最多 **10 局 / 20 人**同时作战。首次启动需要可用端口和写入权限，允许 Windows 防火墙访问时只开放游戏接入端口，不开放数据库。程序不会更改系统防火墙规则。

原生 PostgreSQL 依赖系统的 Microsoft Visual C++ 2015–2022 x64 运行库，启动脚本会检查；缺少时安装 [微软官方运行库](https://aka.ms/vs/17/release/vc_redist.x64.exe) 后再启动。随包数据库只用于本游戏，未提供全部可选扩展。

两台客户端连接同一服务端：主菜单 → **联机** → 填入 `http://服务器局域网IPv4:28187` → **连接**。选择自由匹配，或双方填写相同的六位数字并点击创建/加入；`042731` 的前导零会保留。双方准备后开始，六位房间码只是找房方式，不是账号密码；第三人不能加入已满房间。

只在同一台电脑测试时可使用 `-LocalOnly` 与 `http://127.0.0.1:28187`。同一 Windows 用户的普通客户端共用匿名身份；测试两人应使用两台设备或不同 Windows 用户，不能把同一身份的两个窗口当成双方。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-Server.ps1 -LocalOnly -Port 28188 -DatabasePort 54330 -DataDirectory C:\EpochRushServerData
```

`DataDirectory` 必须为 ASCII 路径。默认 `%LOCALAPPDATA%\SIDcloud\EpochRushServer`，包含数据库、日志、网关 PID 和本机 DPAPI 保护的数据库凭据。不要公开、删除或提交该目录；更换电脑或 Windows 用户时需先规划数据库与凭据迁移，直接复制受保护的凭据文件不能保证可读取。

## 排空、停止和更新

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Stop-Server.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Resume-Admissions.ps1
```

`Stop-Server` 先关闭新对局准入，已有比赛继续运行；仍有活动局时会提示数量并保留服务进程，再次执行且已空时停止网关与独立数据库。`-Force` 允许立即停机并保留已提交数据，适合相同版本的故障恢复；不适合将运行中的比赛直接切换到不同模拟版本。维护结束后执行 `Resume-Admissions` 删除排空标记，再启动服务；脚本不会删除数据库。

所有命令应使用同一个 `-DataDirectory`。更新流程：排空 → 等待活动局归零 → 停止 → 解压新包 → 使用原数据目录启动 → 恢复准入。不要把新 ZIP 覆盖到仍运行的旧服务；旧对局使用旧模拟哈希，跨版本恢复不受支持。容量上限可通过 `-MaxMatches` 设置，应在目标机器完成负载测试后再提高。

## 公网部署

HTTP 明文只供本机和私有局域网。公网客户端要求 **HTTPS/WSS**。在拥有的原生服务器上配置域名、证书与反向代理：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Start-Server.ps1 -LocalOnly -TrustLocalProxy
```

将 `Caddyfile.example` 中的域名环境变量配置为自己的域名，用原生 Caddy 反向代理至 `127.0.0.1:28187`。只开放 80/443，数据库与内部裁判 TCP 端口不对公网开放。Caddy 未随包提供；模板明确隐藏 `/healthz`、`/metrics`、`/admin`。`-TrustLocalProxy` 仅允许可信的本机反向代理提供真实来源 IP。

正式公共匹配服务器已部署于 `jyqx-server.sidcloud.cn`；`jyqx.sidcloud.cn` 仍是独立的 Vercel 隐私政策网页。官方进程与数据库连接中断恢复已经实测，备份仍在同一主机，未配置数据库同步副本、跨机故障切换或异地备份，不能承诺整机或磁盘损坏后零丢失。

## 对战与恢复契约

| 项目 | 当前实现 |
| --- | --- |
| 公平规则 | 双真人、各 240 金币、相同资源增速；无 AI 补偿；时代独立升级、首都进化回满 |
| 构筑 | 六位主将、两项通用技能、两件遗物、六点天赋；不继承离线刷取优势 |
| 找房 | 全服唯一六位数字；两席位；房间准备、构筑变更取消双方准备 |
| 自由匹配 | 真实玩家匹配、15 秒双方确认；没有 AI 冒充或排位积分结算 |
| 模拟 | 30Hz 原生裁判；约 100ms 持久批次与状态投影；客户端只负责输入与表现 |
| 已执行指令 | 数据库事务提交后才发送结果；按玩家序号去重，双方都可使用序号 1 |
| 自动重连 | 心跳检测、有限退避、原身份/原席位、完整状态恢复；重启客户端可恢复 |
| 未确认旧点击 | 查询已执行结果，封存尚未执行的序号；不补发过时招募或技能 |
| 单方掉线 | 技术暂停每次 8 秒、每人整局 15 秒；离线连续 120 秒或累计 180 秒判负 |
| 双方掉线 | 冻结战局，60 秒无人回来则关闭，无获胜方 |
| 服务故障 | 检查点、租约世代和提交账本恢复；识别平台故障并停计玩家掉线预算 |
| 长局 | 72,000 tick 上限，即实际模拟 40 分钟；上限平局 |

控制层有数据库租约和世代隔离，不允许过期裁判继续提交；结束结果唯一提交，可重新查询。恢复过程中客户端锁定输入，敌方金钱、科技值、训练队列、私有冷却不会传给对手。双端都把自己的阵营显示在左边，服务端仍按实际席位处理坐标与命令。

## 数据与排查

本机 `/healthz` 返回数据库健康、当前活动局数、容量和排空状态，不包含玩家令牌。匿名身份密钥在客户端由 Windows DPAPI 或 Android Keystore 保护，服务器存哈希；HTTP 令牌 15 分钟，WebSocket 单次票据 30 秒。应用日志不记录这些明文凭据。在线会话与单机进度分别保存，线上结算不发单机奖励。

定时清理：过期令牌与票据、24 小时幂等请求记录、30 天已结束对局/命令/结果、90 天无关联活动的匿名身份。活动局不因清理任务删除。部署者应核对实际备份、代理访问日志和额外监控的保存规则，不能将应用清理时限直接当成备份删除时限。[隐私政策](https://jyqx.sidcloud.cn)。

常见问题：地址填错或端口被系统保留时换端口；版本不一致时更新双方客户端与服务端；开房无响应时看网关日志与本机健康检查；Android 不可连接时检查同一局域网、Wi-Fi 隔离、防火墙以及服务器地址是否误用手机自己的 `127.0.0.1`。Android APK 内容、签名和 Keystore 插件经过包检查，实体 Android 设备的游玩及后台生命周期仍需验收。

## 从源码构建

在仓库根目录运行，需原生 Python 3.13、Go 1.27.2、Godot 4.7.2 Standard：

```powershell
python -X utf8 tools/online/bootstrap_toolchains.py
python -X utf8 tools/online/prepare_manifest.py
python -X utf8 tools/online/start_local.py
python -X utf8 tools/online/integration_smoke.py
python -X utf8 tools/online/fault_smoke.py
python -X utf8 tools/online/load_smoke.py --matches 10 --seconds 30
python -X utf8 tools/online/package_server.py
```

Go 模块由 `go.mod/go.sum` 固定；工具链与数据库缓存被 Git 忽略。Manifest 校验六个战斗脚本、规则 JSON、裁判脚本，修改它们后要重新生成，再统一导出客户端与服务端。程序化故障测试只停止属于本工作目录、路径已经核验的原生进程，不操作其他数据库或系统服务。

## English quick start

Extract the complete Windows x64 server ZIP, then run `Start-Server.ps1` with native PowerShell. It bundles the gateway, headless Godot authority and isolated native PostgreSQL; no containers, WSL, virtual machines, Python or Go installation are required by the packaged server. Default game port is 28187, private database port is 54329, and admission is capped at ten simultaneous matches.

Connect both clients to `http://<server LAN IPv4>:28187` from the new Online menu. Use real-player matchmaking or enter the same six-digit room code; the first player creates the room, the second joins, and both must ready. Leading zeros are preserved. One anonymous identity cannot occupy both seats. Online builds have equal access to all commanders and six talent points; offline progression does not grant online advantages.

Windows DPAPI and Android Keystore protect persistent anonymous credentials. The authority executes 30 ticks per second and commits command outcomes and exact snapshots before acknowledging them. Disconnects resume the original match and seat; already executed actions remain executed, while unexecuted stale clicks are sealed rather than replayed. Client restart recovers the protected identity and match. Local settings panels do not pause online battles. Each player's private resources and queue are filtered from the opponent's subscription.

`Stop-Server.ps1` drains new admissions first and keeps active matches alive. Run it again once empty, then replace the bundle, retain the same data directory, restart and run `Resume-Admissions.ps1`. Use the same data directory argument for every administrative command. Exact simulation hashes must match; drain old-version matches before upgrading.

Public hosting requires an operator-owned native server and HTTPS/WSS reverse proxy; use the included Caddy example and bind the gateway locally with `-LocalOnly -TrustLocalProxy`. The public SIDcloud endpoint is now available at https://jyqx-server.sidcloud.cn and selected by default. It runs natively on a shared Singapore host, capped at two matches. The Linux archive provides the gateway, pure simulation and operation templates; install Godot and PostgreSQL separately. Local ten-match tests do not establish capacity for that public host. Public process-crash recovery does not certify host or disk disaster recovery. Physical Android-device validation is pending. Full source, implementation notes and compact QA evidence are in the repository.
