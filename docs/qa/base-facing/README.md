# 营寨朝向修复证据 / Camp orientation repair evidence

本目录对应 **0.7.0 营寨朝向修复构建**。[问题、实现与实机对比](../../epoch-rush/godot-base-facing-fix.md) 说明完整范围。

This directory records the **0.7.0 camp orientation corrective build**. The [repair report](../../epoch-rush/godot-base-facing-fix.md) describes the scope and native screenshots.

| 文件 / File | 含义 / Meaning |
| --- | --- |
| [before.json](before.json) | 原成品负向基线，19 项预期失败 / Original-build negative baseline with 19 expected failures |
| [source.json](source.json) | 修复后源码 527 / 527 / Corrected source regression |
| [windows-embedded.json](windows-embedded.json) | 新 Windows 内嵌资源 527 / 527 / Corrected Windows embedded-resource regression |
| [embedded-content.json](embedded-content.json) | 新 Windows 19 JSON 与 252 图集 / Windows data and atlases |
| [base-script.json](base-script.json) | 已测 Windows 内嵌营寨字节码哈希 / Tested Windows base bytecode hash |
| [android-packages.json](android-packages.json) | Android 数据、CRC、时代朝向与同一营寨字节码 / Android content, orientation and matching base bytecode |
| [android-finalization.json](android-finalization.json) | Android 签名、16 KB 对齐与最终哈希 / Android signatures, alignment and final hashes |
| [delivery.json](delivery.json) | 四个新包、旧包、源码与媒体哈希 / Package, baseline, source and media hashes |

Windows 检查由 Godot 4.7.2 加载成品 EXE 的内嵌资源运行外部检查脚本；JSON 中 `executable` 指验证用引擎路径。Android 尚未进行实体设备实测。`canonicalLfSha256` 对文本统一 LF 后计算；Android 数据匹配对照的是导出时本机源码字节。

Windows checks load the shipped EXE's embedded resources through Godot 4.7.2 and run an external regression script. The `executable` field identifies that verification engine. Android has not been playtested on physical hardware. `canonicalLfSha256` normalizes text line endings to LF; Android data comparisons use the local source bytes from export time.

原始截图、日志、旧成品备份和新安装包保留在本机；历史验收数据见 [首次 0.7.0 证据](../v0.7.0/README.md)。

Raw screenshots, logs, archived original builds and rebuilt packages remain local. See the [initial 0.7.0 evidence](../v0.7.0/README.md) for the historical delivery.
