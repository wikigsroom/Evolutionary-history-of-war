# 构建交付清单

构建版本：0.6.2；Android versionCode 8；构建时间：2026-10-07。声音资源及许可包含在成品中。

| 平台 | 文件 | 用途 | 校验 |
| --- | --- | --- | --- |
| Windows x86_64 | `build/windows/Epoch-Rush-Godot.exe` | 桌面可执行版本 | Godot 无头启动退出码 0 |
| Android arm64 | `build/android/Epoch-Rush-Godot-debug.apk` | 调试安装包 | ZIP/Manifest、aapt、apksigner v2/v3 |
| Android arm64 | `build/android/Epoch-Rush-Godot-release.apk` | 发布测试包 | ZIP/Manifest、aapt、apksigner v2/v3 |

## 本地复验

```powershell
$godot = "godot/toolchain/editor/Godot_v4.7.2-stable_win64_console.exe"
& $godot --headless --path godot --editor --quit
& $godot --headless --path godot --script res://qa/smoke.gd
& $godot --headless --path godot --script res://qa/battle_smoke.gd
```

发布 APK 使用本机临时测试 keystore `build/android/epoch-release.keystore` 签名。正式商店发布前应换成产品方自己的签名密钥，并更新 `export_presets.cfg` 中的 release keystore 配置。

