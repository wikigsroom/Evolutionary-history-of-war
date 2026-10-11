# 服务端归档验收 / Server archive verification

归档日期：2026-10-11。服务端 **0.8.1**，兼容客户端 **0.8.2**；原始发布提交 `e009e707c953fe64b56f1a8d08141b1ee024f710`。源码组成和发行包哈希见 [server/archive.json](../../../server/archive.json)。

本次通过已有授权的原生 SSH 进行只读核对，没有启动容器/WSL，没有部署新版本、停止服务、读取玩家表、读取日志或复制凭据。`audit_server_archive.py` 只访问发布清单、列入允许名单的源码/运维文件、systemd 活动状态和私密配置的权限信息。线上 SQL 查询、备份恢复和故障演练属于历史 0.8.1 验收，本次未重新执行。

| 验收项 | 结果 | 证据 |
| --- | --- | --- |
| 官方服务 | 正常运行；公网可信 HTTPS 返回同一模拟哈希 | [deployed-inventory.json](deployed-inventory.json) |
| 发布包完整性 | 61 个安装文件全部符合原始 BUNDLE-MANIFEST | 同上；`matches_original_package` 全部为 true |
| 裁判与规则源码 | 35 个文件与仓库一致，包括 JSON、裁判、共享脚本与已有 UID | 同上；源码按 LF 比较，避免系统换行差异 |
| 实际运维文件 | 10 / 10 与 Git 模板一致 | 同上；systemd、Nginx、健康、备份、logrotate 与续期 hook |
| 私密配置 | root 所有，权限 0600；未读取文件内容 | 同上；仅 stat 元数据 |
| 发行包版本依据 | GitHub v0.8.1 两个服务端资产的大小与 SHA-256 与本地清单一致 | [archive.json](../../../server/archive.json) |

本次还修正了 Git 归档中的换行问题：19 个规则 JSON 的工作区原始字节与现网清单一致，但先前 Git 的文本规范化会把它们转换为 LF，导致暂存对象的 SHA-256 不符合模拟契约。新增 `.gitattributes` 字节保留规则并重新暂存这些原始文件，JSON 数据内容和现网模拟哈希没有修改。共享 GDScript 仍按既有契约规范为 LF。归档校验从 Git 对象核对规则哈希，因此能发现这种只检查工作区时遗漏的问题。

源码归档工具在提交前验证 Git 暂存区，提交后从提交对象生成 ZIP，并逐个校验 ZIP 条目。安全排除检查与独立源码编译/导入结果另见 `source-verification.json`；该文件记录的是本次归档校验，不替代既有的对局与重连测试。

数据库实际内容和真实备份保留在受控的私密目录，不是公开 Git 归档的一部分。公开归档包含数据库结构；迁移现有玩家数据需要私下迁移备份与凭据。当前异地备份和多机故障切换没有实现。

English: This is a read-only archive audit of the deployed 0.8.1 authority. All 61 bundle files, 35 simulation/source files and 10 operation templates matched; the service was active and the public simulation hash matched. The root-only secret file was inspected through metadata only. No database rows, secret values, private keys or logs were read. Source archive validation is separate from the historical gameplay/recovery acceptance tests.
