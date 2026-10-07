# Godot 0.7.0 公开验收证据 / Public verification evidence

本目录收录 **2026-10-07** 的十时代成品验收 JSON，共 18 份。它们描述当时经过测试的 Windows 内嵌 PCK 和 Android 包；历史源码哈希不代表之后每次文档或工具修改都重新导出了游戏。游戏总览、菜单示意、实机截图和 GIF 见 [中英双语 README](../../../README.md)。

This collection contains 18 JSON reports from the **October 7, 2026** ten-era delivery. They describe the tested Windows embedded PCK and Android packages. Historical source hashes do not certify every later documentation or tooling commit. See the [bilingual project README](../../../README.md) for gameplay, menu guides, screenshots and GIFs.

| 证据 / Report | 范围 / Scope |
| --- | --- |
| [rules-regression.json](rules-regression.json) | 420 项时代、伤害、占位、恢复、环境检查 / 420 rule checks |
| [skills-regression.json](skills-regression.json) | 203 项技能、主将与实际作用检查 / 203 skill checks |
| [restore-regression.json](restore-regression.json) | 45 项旧档迁移与快照恢复 / 45 migration and restore checks |
| [asset-audit.json](assets/asset-audit.json) | 120 个实际角色、30 地图与运行素材 / Active actors, maps and runtime assets |
| [visual-review.json](assets/visual-review.json) | 审查板记录和最终图集哈希 / Review records and final atlas hashes |
| [body-geometry.json](assets/body-geometry.json) | 身体锚点与占位范围 / Body anchors and footprints |
| [native-transition-report.json](transitions/native-transition-report.json) | 120 个敌我主将时代形态、升级与生命比例 / Commander forms and evolution continuity |
| [embedded-content.json](windows-embedded/embedded-content.json) | 最终 EXE 的 19 个数据表与 252 图集 / Embedded executable data and atlases |
| [native-visual-report.json](windows-embedded/native/native-visual-report.json) | 十时代、30 背景、载具位置与 90 张截图记录 / Era rendering, maps and strike carriers |
| [interaction-checks.json](windows-embedded/interactions/interaction-checks.json) | 159 项交互与三种视口 / Input checks and three viewport sizes |
| [audio-regression.json](audio/native/audio-regression.json) | 265 项真实 WASAPI 音频检查 / Native audio checks |
| [audio-signal-checks.json](audio/audio-signal-checks.json) | 43 音效族、129 变体、9 曲、38.613 秒实际混音 / Audio signals and native mix |
| [full-battles.json](full-matches/full-battles.json) | 八场合法完整对局，逐 tick 占位检查 / Eight complete legal-action matches |
| [performance.json](performance/performance.json) | RTX 3060、代表与合成压力场景 / Desktop frame-interval samples |
| [android-finalization.json](android-finalization.json) | 两个 APK 的签名、图标修复与 16 KB 对齐 / APK signing and alignment |
| [package-asset-checks.json](packages/package-asset-checks.json) | 图集、字体、Android 内容与 Windows 便携包 / Asset and package checks |
| [showcase-report.json](video/showcase-report.json) | 十时代原生模拟录像记录 / Native scripted showcase recording |
| [delivery-summary.json](delivery-summary.json) | 交付状态、包哈希与证据摘要 / Delivery summary and hashes |

[proof-manifest.json](proof-manifest.json) 记录每份原始报告及公开副本的 SHA-256。只有 `embedded-content.json` 的一个本机绝对 EXE 路径被替换为占位符；其余报告逐字节保留。原始高分辨率审查板、日志、长 AVI/MP4 和 EXE/APK 留在被忽略的本机输出目录，报告中引用的这些附加文件不一定存在于 GitHub。

The manifest records both original and published SHA-256 hashes. One absolute workstation EXE path in `embedded-content.json` is replaced by a placeholder; all other reports retain their original bytes. Full review boards, logs, long AVI/MP4 captures and compiled binaries remain in ignored local outputs. References to those additional files inside reports may not resolve on GitHub.

完整对局是自动合法操作验证，不是全部二十关的人工平衡结论。性能数据来自 Windows 桌面，不是 Android 真机性能。录像以固定帧录制，不证明实时帧率；合成压力样本故意重叠与重复奇袭，不能解释为正常出兵。Android 当前仅完成包验证，未完成真机操作和听感验收。

Full-match checks are automated legal-action samples rather than manual balance approval for all 20 missions. Desktop performance is not an Android benchmark. Fixed-frame recording does not measure real-time FPS, and synthetic stress deliberately overlaps actors and repeats strikes. Android evidence covers packages rather than device play or listening tests.
