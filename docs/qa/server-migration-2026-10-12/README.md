# 线上服务迁移验收 / Production migration acceptance

日期：2026-10-12

项目：纪元急袭（Epoch Rush）在线服务

公开入口：<https://jyqx-server.sidcloud.cn>
隐私政策：<https://jyqx.sidcloud.cn>

## 迁移结果

| 项目 | 结果 |
| --- | --- |
| 旧节点 | `43.160.222.104`；已排空、停止并禁用 `epochrush-online.service` |
| 新节点 | `124.221.198.220`；腾讯云中国（上海）`ap-shanghai` / `ap-shanghai-2` |
| 操作系统 | Ubuntu 22.04.5 amd64；2 vCPU；约 1 GB RAM |
| 服务版本 | 0.8.1；客户端兼容版本 0.8.2 |
| 模拟规则 | `pvp-classic-v1`；simulation hash `085a54fd2558352356ef9b46a001bb751db74c5638e50f4a31d96e633071395c` |
| 运行方式 | 原生 Go 网关 + Godot 4.7.2 Headless + PostgreSQL 14 + Nginx；未使用 Docker、WSL 或虚拟机 |
| 对战容量 | 最多 2 局 / 4 名玩家；数据库连接池 4 |
| 交换空间 | 合计 6 GiB，已写入 `/etc/fstab` 并在重启后复核 |
| 数据库 | `epochrush_online` 与专用受限角色 `epochrush_server`；迁移前后 13 张表的聚合行数一致 |
| 证书 | Let’s Encrypt；当前证书有效至 2027-01-09  |

迁移使用一次性的受保护 PostgreSQL dump；导入后完成表结构、权限、聚合行数和服务启动复核。备份任务、健康检查、日志轮转均已启用，运行时私密配置、数据库 dump、访问令牌和 TLS 私钥没有进入仓库。

## 验收证据

- 真实公网 `https://jyqx-server.sidcloud.cn/v1/bootstrap` 返回在线协议、容量、规则集和模拟 hash。
- `tools/online/integration_smoke.py --url https://jyqx-server.sidcloud.cn` 完成 **23 项**检查，全部通过，覆盖六位房间码、房间幂等、满员拒绝、匹配、两端 WSS、私有状态投影、指令幂等、技术暂停、断线恢复、非法时代演化、投降结算、重启后结果读取，以及并发入房/匹配拒绝。
- 新节点本机 `/healthz` 为 `ok: true`、`active_matches: 0`、`draining: false`；服务、健康定时器和备份定时器均为 active。
- 备份任务已生成 PostgreSQL custom-format 备份，并保存校验和；备份目录仅 root 可读。
- `audit_server_archive.py --host 124.221.198.220` 对发布包文件哈希、systemd/Nginx/运维模板、服务状态、配置权限及公网模拟 hash 做只读核验。

## 网络续期说明

Nginx 虚拟主机保留 80 端口的 ACME challenge 与 308 跳转配置，443 提供 HTTPS/WSS。当前域名的 HTTP 80 请求会被腾讯 DNSPod web 防护接管并返回平台拦截页，因此公网 HTTP-01 不能作为自动续期保证；HTTPS/WSS 已通过真实公网验收。证书到期前应解除 80 端口的 web 防护拦截，或配置 Certbot DNS-01 凭据并按最小权限保存。

## 回滚边界

旧节点没有重新启用。若需要回滚，必须先在新节点设置排空标记、等待活动比赛归零、确认数据库备份，再按版本包和 systemd 配置恢复；不能在有活动比赛时直接切换模拟版本。

---

## English

This record documents the 2026-10-12 production migration of Epoch Rush online services.

| Item | Result |
| --- | --- |
| Old node | `43.160.222.104`; drained, stopped and disabled |
| New node | `124.221.198.220`; Tencent Cloud Shanghai, `ap-shanghai` / `ap-shanghai-2` |
| Runtime | Ubuntu 22.04.5 amd64, 2 vCPU, about 1 GB RAM, native Go + Godot 4.7.2 + PostgreSQL 14 + Nginx |
| Release | Server 0.8.1; client compatibility 0.8.2 |
| Capacity | Two simultaneous matches / four players; four database connections |
| Swap | Exactly 6 GiB combined and persisted in `/etc/fstab` |
| Data | 13 database tables migrated; aggregate row counts matched before and after restore |
| TLS | Let’s Encrypt certificate currently valid through 2027-01-09 |

The public WSS smoke test completed 23 checks successfully, including room-code admission, matchmaking, two-client private-state projection, idempotent commands, technical pause, reconnect epoch/cursor recovery, invalid evolution rejection, surrender settlement, restart result retrieval and concurrent admission limits. Health and backup timers are active, and the archive audit reads hashes and state only; it never stores credentials, database rows, access tokens or private keys.

Nginx keeps an ACME challenge location and an HTTP-to-HTTPS redirect. Tencent DNSPod currently intercepts public port 80 with a web-protection page, so HTTP-01 renewal is not a reliable production path until that interception is removed; HTTPS/WSS is healthy. Use DNS-01 before the certificate renewal window if the interception remains.
