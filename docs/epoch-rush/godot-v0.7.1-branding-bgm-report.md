# v0.7.1 品牌与随机配乐交付

日期：2026-10-09。应用版本 0.7.1；Android `versionCode=10`、包名 `studio.epochrush.pixelcommand`。在 Windows 原生环境完成资源处理、Godot 4.7.2 编译与验证。

## 品牌应用

使用已选男性骑士胸像，不重新生成角色。Windows EXE 图标与 Android 常规启动图标为不透明深蓝背景；Android 自适应图标使用人物前景、深蓝背景、单色剪影三层。

`public/brand/game-logo.png` 为已批准的 2048×512 透明主文件，文字仅“纪元急袭”。Godot 菜单资源 `godot/assets/ui/brand/game-logo.png` 保留原字形，裁除空白并增加 16 px 透明边距，最终 1340×431。营地首页与五个菜单页顶栏共用该资源。阵营标识继续承担战斗阵营信息。

品牌准备可由 `python -X utf8 tools/prepare_native_brand.py` 复建。透明主文件 SHA-256 为 `c32d538087261ed2bdfb7d88f600e7aac5ef5004278591af973a94fccc190921`；Godot 裁剪资源为 `f41c88571cc0456e5d2fbe771aac8b7bf43bca9ca9f329050912b301b4979a46`。来源记录位于 `godot/assets/ui/brand/branding.json`。

![新版营地菜单](../media/v0.7.1/menu-home.png)

## 曲目与播放逻辑

来源为用户指定目录 `C:/Users/carzy/Downloads/yourset-old` 中的四个 MP3。源文件保持不变；导入工具 `tools/import_yourset_bgm.py` 只处理输出副本，提取音轨、移除封面，并使用 FFmpeg 双遍响度处理。

| 曲目 | 时长（秒） | 实测 LUFS | 真峰值 dBTP |
| --- | ---: | ---: | ---: |
| Yourset — 黑历史 Infetar A1 | 140.070 | -19.01 | -7.42 |
| Yourset — Sirirankok 修复版 | 136.177 | -18.99 | -4.12 |
| Yourset — Loth | 106.043 | -18.99 | -4.74 |
| Yourset — Be A Single Dog Again | 173.559 | -19.00 | -7.96 |

四首为 48 kHz 双声道 Ogg Vorbis，保留全部歌曲，合计约 9 分 16 秒；转码副本同时存放于 Godot 和公共素材目录。曲目由用户提供并独立署名，不加入旧素材 CC0 声明。原始与成品校验值见 [导入记录](../qa/v0.7.1/audio/yourset-import.json) 和 [音频声明](../../godot/assets/audio/Audio-CREDITS.txt)。

`BattleAudio` 使用单独的 `RandomNumberGenerator` 和 Fisher–Yates 排序，不消耗模拟器随机序列。四首每轮各播一次，新一轮首曲若等于上一轮末曲则交换，避免连播同曲。曲目队列在同一次应用运行中跨菜单和对战保留。

两个音乐声部在曲尾提前 2 秒做等功率交叉淡化。自然结束信号只允许当前声部推进，退场声部结束不会多抽一首；未正常完成淡入的歌曲仍有结束兜底。菜单切换、进入对战及双方进化只更新播放场景，不重播当前曲目。胜负平局短曲独立且只播放一次，返回营地继续下一首。

关闭音乐与应用后台暂停播放、淡化和自动选曲；恢复后继续当前位置。战斗暂停将配乐压低，重大演出保留混音避让。总音量、配乐、战斗、界面四组控制继续工作。

旧菜单/五类时代循环资源保留历史兼容，但原生场景接口已全部路由到新列表。当前正常 BGM 仅选取这四首 Yourset 曲目；三段结算与 43 类 / 129 个音效变体沿用原有系统。

## 版本与存档

应用版本、Windows 文件版本及 Android versionName 更新至 0.7.1，Android code 从 9 增至 10，包名与发行签名保留。`contentVersion=0.7.0` 继续作为玩法/存档基线；未修改兵种、技能或双方时代规则，不触发存档迁移。

## 验证

| 范围 | 结果 | 证据 |
| --- | --- | --- |
| 原生 WASAPI 音频 | 313/313；四首实际 PCM、自然接续、淡化、八轮覆盖、无连续重复、独立 RNG、菜单/十时代不断曲、静音与生命周期 | [音频回归](../qa/v0.7.1/audio/native/audio-regression.json) |
| 音频信号 | 129 音效、13 个保留/新增音乐文件解码与散列通过；40.181 秒混音零削波、零采样丢帧 | [信号报告](../qa/v0.7.1/audio/audio-signal-checks.json) |
| 品牌与曲目运行资源 | 源码和 Windows 内嵌包各 63/63；1280×720、1920×1080 五菜单无 LOGO/导航重叠 | [源码](../qa/v0.7.1/branding/source/branding-playlist.json)、[内嵌包](../qa/v0.7.1/branding/windows-embedded/branding-playlist.json) |
| 安装包图标 | PE 内嵌 ICO 与两个 APK 启动图逐项核对；44 项通过，常规图标不透明 | [图标核对](../qa/v0.7.1/packages/launcher-branding.json) |
| 核心规则与存档 | 420/420 规则；45/45 恢复 | [规则](../qa/v0.7.1/rules/rules-regression.json)、[恢复](../qa/v0.7.1/restore/restore-regression.json) |
| Windows | 独立 EXE 正常启动；内嵌 19 个数据 JSON 和 252 个图集映射可加载；ZIP CRC、EXE 哈希一致 | [内嵌资源](../qa/v0.7.1/windows-embedded-content/embedded-content.json)、[包检查](../qa/v0.7.1/packages/package-asset-checks.json) |
| Android release/debug | versionName 0.7.1 / code 10；19 数据 JSON、品牌/音乐导入字节一致，arm64，签名及 16 KB 对齐通过 | [后处理](../qa/v0.7.1/packages/android-finalization.json)、[包检查](../qa/v0.7.1/packages/package-asset-checks.json) |

未连接 Android 实体设备，APK 内容、签名与版号检查不代替真机安装、触控、性能和扬声器试听。Windows 菜单图采自最终 EXE 内嵌资源，原有 0.7.0 战斗截图与 GIF 保留历史采集标记。本次未使用 Docker、WSL 或虚拟机，也未打开浏览器标签。

## 安装包与发布

[v0.7.1 GitHub Release](https://github.com/wikigsroom/Evolutionary-history-of-war/releases/tag/v0.7.1) 提供 Windows ZIP、独立 EXE、正式/调试 APK 与 SHA256SUMS。Windows ZIP 包含 8 个文件，附带引擎、字体与音频来源声明。

本机输出为 `godot/build/windows/Epoch-Rush-Godot.exe`、`godot/build/windows/Epoch-Rush-Godot-Windows.zip`、`godot/build/android/Epoch-Rush-Godot-release.apk` 和 `godot/build/android/Epoch-Rush-Godot-debug.apk`。可审查的发行清单与最终校验值见 [delivery.json](../qa/v0.7.1/delivery.json)、[SHA256SUMS.txt](../qa/v0.7.1/SHA256SUMS.txt)。
