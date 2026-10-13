# v0.8.3 验证记录

本目录对应 v0.8.3 的本地原生构建与模拟规则检查。所有检查在 Windows 原生工具链执行，没有 Docker、WSL、虚拟机或 Android 模拟器。

| 范围 | 结果 |
| --- | --- |
| TypeScript 非 soak | 9 个测试文件、88 项通过 |
| TypeScript soak | 30/30 自动对战通过；最大对战 1059 秒、峰值实体 35 |
| Godot 十时代 | 420 项、0 失败 |
| Godot 难度/首都 | 187 项、0 失败 |
| Godot 规则修复 | 258 项、0 失败 |
| Godot 联机契约 | 35 项、0 失败 |
| Go 网关 | `go test ./...` 通过 |
| Windows 资源包 | 品牌检查 44 项；在线资源契约 4 项 |
| Android APK | debug/release 各 24 项；仅 `INTERNET` 权限、清单一致、16 KB 对齐 |
| 资源与动画 | 126 角色、6980 非空帧、670 个中文字体字形 |

对应的可复核 JSON 和日志位于本机忽略目录 `output/qa/`；二进制包位于 `output/releases/v0.8.3/`。Android 实体设备安装、触控和硬件音频仍未认证。
