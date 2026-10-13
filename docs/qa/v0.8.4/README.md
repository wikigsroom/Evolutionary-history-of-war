# v0.8.4 验证记录

本目录对应 v0.8.4 的本地原生构建与模拟规则检查。所有检查在 Windows 原生工具链执行，没有 Docker、WSL、虚拟机或 Android 模拟器。

| 范围 | 结果 |
| --- | --- |
| TypeScript 非 soak | 9 个测试文件、88 项通过 |
| TypeScript soak | 30/30 自动对战通过；最大对战 1059 秒、峰值实体 35 |
| Godot 十时代 | 420 项、0 失败 |
| Godot 难度/首都 | 187 项、0 失败 |
| Godot 规则修复 | 258 项、0 失败 |
| Godot 联机契约 | 35 项、0 失败 |
| Go 网关 | `go test ./...` 通过 |
| 双客户端联机回归 | 24/24 通过；无脚本错误 |
| Windows 资源包 | 品牌检查 44 项；在线资源契约 4 项 |
| Android APK | debug/release 各 24 项；仅 `INTERNET` 权限、清单一致、16 KB 对齐 |
| 资源与动画 | 126 角色、6980 非空帧、670 个中文字体字形 |
| 服务端切换 | Linux 清单校验、真实裁判 IPC 预检、排空/原子切换/健康回滚已在 124.221.198.220 验证；公网 bootstrap 为 0.8.4 |

对应的可复核 JSON 和日志位于本机忽略目录 `output/qa/`；二进制包位于 `output/releases/v0.8.4/`。Android 实体设备安装、触控和硬件音频仍未认证。

服务端发布不执行 Godot 编辑器导入：部署器以有界的裁判 IPC 握手替代可能无限等待的导入流程；切换失败会保持旧 `current` 链接并自动恢复服务。Windows 原生包的首次空数据目录也已验证可在无 `ConvertTo-SecureString` 自动模块的 PowerShell 主机上初始化。
