# v0.7.1 公开验收证据 / Public QA evidence

2026-10-09 原生 Windows 更新：最新男性骑士图标、透明文字 LOGO 与四首 Yourset 随机配乐。精简证据随源码保存；完整 PCM、高清截图及导出日志保留本机 `output/qa/v0.7.1`。

Native Windows delivery on October 9, 2026: updated knight icon, transparent wordmark and four shuffled Yourset songs. Compact proof is committed; full PCM, high-resolution captures and export logs remain in local output.

| Evidence | Result |
| --- | --- |
| [delivery.json](delivery.json), [SHA256SUMS](SHA256SUMS.txt) | 0.7.1, Android code 10, final package sizes and checksums |
| [Yourset import](audio/yourset-import.json) | Four full-length songs, original hashes preserved, stereo 48 kHz, approximately -19 LUFS |
| [Native audio](audio/native/audio-regression.json) | 313/313 checks, four real PCM songs, transitions, eight shuffle cycles, independent RNG and lifecycle |
| [Signal checks](audio/audio-signal-checks.json) | 40.181-second native mix, zero clipped samples and zero dropped frames; legacy SFX preserved |
| [Source branding](branding/source/branding-playlist.json), [Windows embedded branding](branding/windows-embedded/branding-playlist.json) | 63/63 checks each; approved image/music imports and five menus at two viewport sizes |
| [Launcher resources](packages/launcher-branding.json) | 44 icon/identity entries from actual PE/APK packages; regular icons opaque |
| [Rules](rules/rules-regression.json), [Restore](restore/restore-regression.json) | 420/420 and 45/45 |
| [Embedded Windows content](windows-embedded-content/embedded-content.json), [standalone boot](windows-standalone-boot.txt) | 19 source JSONs, 252 atlas references, boot exit 0 |
| [Package assets](packages/package-asset-checks.json), [Android finalization](packages/android-finalization.json) | ZIP CRC and bundled EXE match; APK brand/music imports match; signatures and 16 KB alignment pass |

Android device installation, touch behavior and hardware audio have **not** been verified. No virtualized environment was used. Gameplay/save content version stays 0.7.0; application version is 0.7.1. Historical gameplay/performance proofs remain in [v0.7.0](../v0.7.0/README.md).

The four owner-provided songs are credited separately from CC0 SFX. See [Audio-CREDITS](../../../godot/assets/audio/Audio-CREDITS.txt), [sound design](../../../godot/SOUND_DESIGN.md) and the [bilingual release notes](../../releases/v0.7.1.md).
