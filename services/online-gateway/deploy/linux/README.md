# Linux 公网部署与运维 / Linux public operations

v0.8.1 正式服务为 **https://jyqx-server.sidcloud.cn**，由 SIDcloud 在新加坡运营。运行路径是现有 Nginx → 本机 Go 接入 → 原生 Godot Headless 裁判 → 独立 PostgreSQL 库。没有容器、WSL 或虚拟机。

## 已部署实例

| 项目 | 配置 |
| --- | --- |
| 系统与容量 | Ubuntu 24.04 / amd64，2 vCPU、1 GB 内存；与原有服务共存 |
| 对战限制 | 同时 2 局 / 4 玩家；数据库连接池 4；容量不足明确返回 SERVER_FULL |
| HTTPS/WSS | jyqx-server.sidcloud.cn，Let’s Encrypt，80 自动跳转 443 |
| 接入 | 127.0.0.1:28187；数据库 127.0.0.1:5432；裁判 IPC 仅本机 |
| 当前版本 | /opt/epochrush/current → /opt/epochrush/releases/0.8.1 |
| 引擎 | /opt/epochrush/runtime/Godot_v4.7.2-stable_linux.x86_64 |
| 系统用户 | epochrush，非 root；应用数据 /var/lib/epochrush |
| 私密配置 | /etc/epochrush/online.env，root:root / 0600，不在发布包中 |
| 数据库 | PostgreSQL 16；epochrush_online 库 / epochrush_server 专用受限账号 |
| 进程管理 | epochrush-online.service，崩溃后 3 秒重启；开机自启 |
| 内存约束 | Go 96 MiB 目标，服务 MemoryHigh 192 MiB / MemoryMax 320 MiB |

当前 Nginx 来自服务器已有的宝塔安装，虚拟主机在 `/www/server/panel/vhost/nginx/jyqx-server.sidcloud.cn.conf`。只改本游戏虚拟主机并校验后 reload，不能覆盖全局配置或停止其他站点。新机器可以使用系统 Nginx，但需要相应调整配置目录与 reload 命令。

## 在新的原生 Ubuntu 主机安装

Linux TAR 包包含 Go ELF、纯模拟工程、运维模板和许可；**不包含 Godot 引擎、PostgreSQL 或服务器凭据**。需要原生 PostgreSQL 16、Python 3、curl、Nginx、Certbot，以及固定版本 Godot 4.7.2 Standard。引擎下载 URL 与压缩包 SHA-256 写在 `BUNDLE-MANIFEST.json`；下载后校验，再解压到上述 runtime 目录。

1. 解压 `Epoch-Rush-Server-0.8.1-Linux-x64.tar.gz`，逐个校验 manifest 中的文件哈希；将 `Epoch-Rush-Server` 内容安装到 `/opt/epochrush/releases/0.8.1`。赋予 `bin/epoch-online` 和 `ops/*.sh` 执行权限，代码保持 root 所有。
2. 创建无登录系统用户 epochrush，以及该用户可写的 `/var/lib/epochrush`。引擎初次导入使用 `runuser -u epochrush -- <引擎> --headless --editor --path <referee> --import`；新版本目录导入阶段允许该用户写入 `.godot` 缓存，完成后收回对源码的写权限。纯裁判 project 限制 worker 线程为 2，避免小主机导入时产生过多线程。
3. PostgreSQL 只监听 loopback。使用管理员 psql 创建专用 `epochrush_server` LOGIN 角色，NOSUPERUSER / NOCREATEDB / NOCREATEROLE / NOREPLICATION、CONNECTION LIMIT 4；用交互式 `\password epochrush_server` 设置强密码，不把密码写在 shell 命令、历史、文档或 URL 中。创建该角色拥有的 epochrush_online 库并撤销 PUBLIC 数据库权限。共享 PostgreSQL 不应因本游戏部署而重启或改变全局调优参数。
4. 用 root 编辑 `/etc/epochrush/online.env`，设置 `EPOCH_DATABASE_URL`、`EPOCH_MAX_MATCHES=2`、`EPOCH_DB_CONNECTIONS=4`。DSN 的密码需 URL 编码。文件仅 root 可读，由 systemd 注入给服务；不要 cat 它或发布其副本。
5. 将 current 链接指向新版本。建立 root 管理的 `/var/log/epochrush` 与仅 root 可读的 `/var/backups/epochrush`。复制 `epochrush-*.service` / `epochrush-*.timer` 到 `/etc/systemd/system/`，logrotate 模板到 `/etc/logrotate.d/epochrush`。
6. 先配置域名的 A 记录，再以 webroot `/var/www/epochrush` 申请证书，证书名 epochrush-public。导入 `nginx-public.conf`，校验并 reload；公网只开放 80/443。把 renew-proxy.sh 放入 Certbot deploy-hooks，并启用 certbot.timer。
7. 执行下面的启用与本机检查。初始化表结构由网关完成；不要使用客户端离线存档初始化服务端。

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now epochrush-online.service epochrush-health.timer epochrush-backup.timer
curl --fail http://127.0.0.1:28187/healthz
curl --fail https://jyqx-server.sidcloud.cn/v1/bootstrap
```

复用这组模板时请替换域名、版本与系统路径，并在自己的机器重新验收。首次部署不能只启动 HTTP 网关后就宣布公网可用；应检查可信 TLS、真实 WSS 对局、断线恢复和存储恢复。

## 日常检查

```bash
sudo systemctl status epochrush-online.service --no-pager
sudo systemctl list-timers epochrush-health.timer epochrush-backup.timer certbot.timer --all
curl --fail http://127.0.0.1:28187/healthz
sudo tail -n 40 /var/log/epochrush/gateway.log
```

`/healthz`、`/metrics`、`/admin` 在公网均返回 404。应用日志不记录身份密钥、访问令牌或完整指令；Nginx 本游戏虚拟主机关闭访问日志及错误日志，防止一次性票据 URL 进入文件。网关诊断日志每天或达到 2 MB 后滚动，保留 7 份归档。

健康定时器每分钟检查一次，连续 3 次失败才重启本游戏服务；单次检查不会重启共享数据库。磁盘剩余不足 512 MB 时写入排空标记，拒绝新比赛，保留已有比赛。应在外部配置独立的 HTTPS 可用性告警：本机自检不能发现整台主机断网或停电，当前未接入邮件/短信通知。

## 排空与升级

```bash
sudo install -o epochrush -g epochrush -m 0600 /dev/null /var/lib/epochrush/draining.flag
curl --fail http://127.0.0.1:28187/healthz
```

等待 `active_matches` 归零，手动执行一次备份，然后停止服务。将新版本导入独立目录并核验 manifest，替换 current 链接，启动服务并验证本机健康和公网 bootstrap，最后删除排空标记。**不要把有活动比赛的旧模拟版本直接切换为新模拟版本。** 同版本进程崩溃由 systemd 自动恢复；跨版本更新必须先排空。

```bash
sudo systemctl start epochrush-backup.service
sudo systemctl stop epochrush-online.service
# 在已核验的新版本目录和 current 链接就绪后：
sudo systemctl start epochrush-online.service
curl --fail http://127.0.0.1:28187/healthz
sudo rm -- /var/lib/epochrush/draining.flag
```

删除排空标记前必须确认磁盘问题已解决；不要关闭健康保护来掩盖故障。仅删除上面明确的标记文件，不删除任何数据库或用户数据目录。

## 备份与恢复

每日 04:20 主机时间生成 PostgreSQL custom-format dump 与 SHA-256，只备份 epochrush_online。超过七天的文件由每日任务清理，因此可能保留至八天。已完成一次恢复到临时隔离数据库的实测，并核验玩家与结算记录；恢复检查库随后删除。

```bash
sudo systemctl start epochrush-backup.service
sudo ls -lh /var/backups/epochrush
# 先核对选择的备份 SHA-256，再恢复到全新的隔离库；不要覆盖生产库。
sudo -u postgres createdb epochrush_restorecheck
sudo -u postgres pg_restore --no-owner --no-privileges -d epochrush_restorecheck /path/to/readable-test-copy.dump
sudo -u postgres psql -d epochrush_restorecheck -c 'SELECT count(*) FROM online_results;'
```

备份根目录仅 root 可读；做隔离恢复时应创建仅 postgres 可读的临时副本，验证后删除副本和测试库。真正灾难恢复须先停应用、保留现场、核验备份、恢复到新库并处理专用角色权限，再测试后切换配置。

当前备份在同一台主机，**不能抵抗磁盘损坏或整机丢失**。未配置数据库同步副本、跨机自动故障切换或异地备份，不能承诺此类故障零丢失。后续应将加密备份同步到独立存储，并定期演练。

## English

The public SIDcloud endpoint is `https://jyqx-server.sidcloud.cn`, hosted in Singapore. Native Nginx proxies to a loopback Go gateway; headless Godot runs the authority and PostgreSQL 16 stores committed commands, checkpoints and unique results. The shared 1 GB / two-vCPU host admits **two simultaneous matches / four players**, with a four-connection database pool. This is an admission cap, not a large-scale availability guarantee.

The Linux archive contains the gateway, pure simulation project, operation templates and license notices. Install the pinned Godot runtime and PostgreSQL natively, create an isolated database and restricted role, protect the root-only environment file, import the referee, configure TLS, and enable the supplied systemd units. Preserve unrelated applications and database services.

Systemd restarts a crashed game process after three seconds. Health checks run every minute; three failures restart only this game, while low disk space drains new admissions. Daily database dumps retain seven days of backups, up to eight days with daily cleanup. The actual dump was restored to an isolated test database. Backups remain on-host; disk loss, host loss, off-site disaster recovery and multi-host failover are not covered.

Drain all old-version matches before updating simulation files. Validate the new release manifest, take a backup, replace the current symlink, verify loopback health and public TLS/bootstrap, then reopen admission. Never print or commit the environment file or credential state.
