# 服务端归档 / Server archive

本目录是《纪元急袭》服务端的统一归档入口。源码继续保存在现有目录，通过下表与 `archive.json` 锁定其组成，避免复制出两份不同步的战斗逻辑。归档覆盖接入服务、权威裁判、共享规则、数据库建表、双平台部署模板、许可和校验工具。

**2026-10-11 核对状态：线上服务端 0.8.1，兼容客户端 0.8.2。** 官方服务由 SIDcloud 运营：<https://jyqx-server.sidcloud.cn>。线上 35 个裁判/规则文件、10 个实际运维配置与仓库一致；61 个部署包文件均与原始包清单一致。只读核对结果见 [归档验收记录](../docs/qa/server-archive/README.md)。

## 归档内容

| 内容 | 仓库位置 | 用途 |
| --- | --- | --- |
| Go 网关 | [services/online-gateway](../services/online-gateway) | HTTPS/WSS 接入、匿名身份、匹配、六位房间码、重连与持久化 |
| 数据库结构 | [001_online.sql](../services/online-gateway/migrations/001_online.sql) | 专用库建表；不含玩家数据 |
| 权威裁判 | [godot/server](../godot/server) | 独立 Godot Headless 执行比赛 |
| 共享战斗逻辑 | [godot/scripts](../godot/scripts) | `game_model`、`game_data`、`epoch_combat`、`epoch_skills`、`epoch_environment`、`epoch_snapshot_migration`，以及对应 UID |
| 规则与版本契约 | [godot/assets/data](../godot/assets/data) | JSON 定义、`online-manifest.json` 与模拟哈希 |
| Windows 部署 | [deploy](../services/online-gateway/deploy) | 原生启停、排空与 Caddy 示例 |
| Linux 部署 | [deploy/linux](../services/online-gateway/deploy/linux) | systemd、Nginx、备份、健康检查、日志轮转、证书续期 |
| 非敏感环境模板 | [environment.example](../services/online-gateway/deploy/linux/environment.example) | 仅密码占位符；实际配置必须另外创建 |
| 协议与设计 | [联机协议](../docs/epoch-rush/online-protocol.md) / [实现说明](../docs/epoch-rush/online-implementation-and-acceptance.md) | 命令、权威状态、原局恢复与验收依据 |
| 版本与发布包锁定 | [archive.json](archive.json) | 原始发布提交、引擎版本、双平台包大小与 SHA-256 |
| 源码归档工具 | [archive_server.py](../tools/online/archive_server.py) | 只取 Git 对象中的允许文件，检查凭据、模拟清单与 ZIP |
| 线上只读核对 | [audit_server_archive.py](../tools/online/audit_server_archive.py) | 只读文件哈希、服务状态和私密配置权限；不读数据库内容 |

Go 模块由 `go.mod/go.sum` 固定。裁判以 30 Hz 执行，状态以 10 Hz 推送；双方使用同一模拟契约。联机核心源码复用客户端战斗模块，不能单独更改一端规则后继续使用旧哈希。规则 JSON 的清单使用原始字节哈希；`.gitattributes` 禁止 Git 转换这些 JSON 的换行，保证 Windows、Linux 和新克隆的文件均符合现网契约。共享 GDScript 的契约哈希按 LF 计算。

## 获取已验证的原生服务端

| 平台 | 下载 | 包含 |
| --- | --- | --- |
| Windows x64 | [0.8.1 Server ZIP](https://github.com/wikigsroom/Evolutionary-history-of-war/releases/download/v0.8.1/Epoch-Rush-Server-0.8.1-Windows-x64.zip) | 网关、Godot、独立 PostgreSQL、纯裁判与管理脚本 |
| Linux amd64 | [0.8.1 Server TAR](https://github.com/wikigsroom/Evolutionary-history-of-war/releases/download/v0.8.1/Epoch-Rush-Server-0.8.1-Linux-x64.tar.gz) | 网关、纯裁判、运维模板与许可；引擎和 PostgreSQL 另外安装 |

先按 `archive.json` 核对大小与 SHA-256，再校验包内 `BUNDLE-MANIFEST.json`。大型引擎、数据库运行库和发布二进制放在 GitHub Release；Git 保存源码和版本依据。原始发布源码提交为 `e009e707c953fe64b56f1a8d08141b1ee024f710`。

## 生成独立源码归档

在完整 Git 仓库根目录运行，要求原生 Python 3.10+ 和 Git：

```powershell
# 提交前检查暂存区中的服务端文件；没有打包或部署副作用。
python -X utf8 tools/online/archive_server.py --check-index

# 从明确的提交生成 ZIP，默认 HEAD；不扫描临时目录。
python -X utf8 tools/online/archive_server.py --ref HEAD
```

输出位于 `output/archives/server/<12位提交号>/`，含源码 ZIP 与 `source-archive.json` 回执。ZIP 中的 `SERVER-SOURCE-MANIFEST.json` 记录完整提交号和每个文件的 SHA-256。工具核验全部 ZIP 条目的 CRC、哈希和当前模拟契约；文件清单采用允许列表，排除运行产物、符号链接、私密路径、已知密钥格式及含真实密码的数据库连接串。该检查用于补充人工审查，不能识别所有可能的秘密格式。

归档从 Git 提交读取，因此未提交的修复不会悄悄混入旧版本；`--check-index` 检查即将提交的 Git blob。生成的 ZIP 不提交进 Git，源码与归档工具本身已经构成版本归档。

## 从源码构建

完整仓库推荐先按 [服务端开发说明](../services/online-gateway/README.md) 配置原生 Go 1.27.2、Godot 4.7.2 Standard 与 PostgreSQL。Go 原生构建命令：

```powershell
Push-Location services/online-gateway
go test ./...
go build -trimpath -o ../../output/archives/epoch-online.exe .
Pop-Location

# 在原生 Windows 上交叉编译 Linux 网关；不启动 Linux/虚拟化环境。
$env:GOOS='linux'
$env:GOARCH='amd64'
$env:CGO_ENABLED='0'
Push-Location services/online-gateway
go build -trimpath -o ../../output/deploy/online/epoch-online-linux-amd64 .
Pop-Location
Remove-Item Env:GOOS, Env:GOARCH, Env:CGO_ENABLED
```

上述交叉编译环境变量仅用于当前终端；实际部署仍在原生 Linux 主机进行。生成正式发行包使用 `tools/online/package_server.py` / `package_linux_server.py`。它们读取**当前客户端工程版本**，所以还原 0.8.1 包须使用其原始提交；不能把新版本包直接改名冒充 0.8.1。重新编译的二进制不承诺与历史发行包逐字节相同。

若使用本页工具生成的独立源码 ZIP，先解压到新目录。**仅在该解压目录内**将 `server/referee-project.godot` 复制为 `godot/project.godot`，得到没有客户端界面、图像、音频或导出插件的最小裁判工程。完整游戏仓库中的 `godot/project.godot` 不应被覆盖。运行原生 Godot 的 `--headless --editor --path <解压目录>/godot --import --quit` 进行导入，再由网关的 `--project` 指向该目录；启动入口由网关调用 `server/server_main.gd`。

独立源码 ZIP 可构建网关和裁判。完整双端发行流水线仍须使用完整仓库及原生工具链，不能假定这个服务端子集包含客户端美术和 Android 构建环境。

## 部署与恢复边界

Windows 运行已验证 ZIP 中的 `Start-Server.ps1`；Linux 按 [完整部署与恢复步骤](../services/online-gateway/deploy/linux/README.md) 操作。公网使用 HTTPS/WSS，网关和数据库仅监听本机；现有正式服务准入限制为两局 / 四人，数据库连接池为 4。

Linux 实际环境文件是 `/etc/epochrush/online.env`：root 所有、权限 0600。模板只是说明格式，不能直接用于认证。另行创建专用受限数据库角色并设置强密码；把 URL 编码后的密码保存在私密环境文件内，不写入 Git、终端历史或发行包。Nginx 模板引用证书路径，不含证书私钥。

升级流程为排空新对局 → 等待活动局归零 → 私下备份 → 停止本游戏服务 → 导入并校验新版本 → 替换版本链接 → 启动 → 校验本机健康、公网 TLS 和 WSS → 恢复准入。不能重启无关服务或共享数据库来执行本游戏的升级。跨模拟版本须排空，不能用新规则恢复旧比赛。

**Git 归档恢复的是代码和部署体系，不包含真实玩家数据。** 线上数据库备份保存在私密备份目录；数据迁移必须另行通过受控通道进行。没有数据库备份，重建服务不会保留旧匿名身份或对局。当前备份仍在同一主机，归档不代表已具备异地备份或多机容灾。

正式 0.8.2 客户端固定连接官方地址；私人部署测试可在原生编辑器内设置 `EPOCH_ONLINE_URL`。要分发私人客户端，需修改 `EpochNetClient.DEFAULT_ENDPOINT` 后重新编译，并更新运营与隐私说明；发行包不会接受环境变量修改地址。

## English

This directory is the server archive index. The existing gateway, shared Godot simulation, migrations and deployment templates remain in their original repository paths; `archive.json` records the deployed version, source baseline, toolchains and published artifact hashes. The live **0.8.1** authority is compatible with **0.8.2** clients. A read-only audit verified all 35 simulation/source files, all 10 operation templates and all 61 original bundle files against the running deployment.

Run `python tools/online/archive_server.py --check-index` before committing, then `python tools/online/archive_server.py --ref HEAD` to produce a server-only ZIP from committed Git objects. The ZIP includes an exact commit and per-file hashes; its CRC and entry hashes are verified. An allowlist and credential-signature checks reject private/runtime files. They complement review and do not detect every possible secret format.

The standalone ZIP supports native Go and headless Godot builds. Only inside its newly extracted directory, copy `server/referee-project.godot` to `godot/project.godot`, import it with Godot 4.7.2, and point the gateway to that project. Do not replace the full game's project file. Full client/server distribution packaging uses the complete repository and reads the current game version; use the original release commit to rebuild that historical version. Rebuilt binaries are not guaranteed byte-identical to published ones.

Deploy using the Windows or Linux guides linked above. Create fresh private credentials and a restricted database role, protect the Linux environment file as root/0600, and expose only HTTPS/WSS. Drain active matches before changing simulation versions. Shipped clients use the fixed SIDcloud endpoint; private testing requires an editor override or a rebuilt private client.

The public archive excludes live databases, player records, database dumps, passwords, identity tokens, DPAPI files, signing keys, SSH state, TLS keys and logs. Code reconstruction is covered; private player-data backup, off-site disaster recovery and multi-host failover are separate concerns. No Docker, WSL or local virtual machines are used.
