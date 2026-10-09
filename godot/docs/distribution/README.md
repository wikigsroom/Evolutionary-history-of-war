# 纪元急袭 / Epoch Rush: Pixel Command

Godot 0.7.3 · Windows x64

解压后运行 `Epoch-Rush-Godot.exe`。游戏资源已嵌入程序，无需安装 Godot、Node.js 或启动网页服务。

Extract the archive and run `Epoch-Rush-Godot.exe`. Resources are embedded; no Godot or Node.js installation or web server is required.

v0.7.1 更新不透明男性骑士应用图标和透明“纪元急袭”文字 LOGO。菜单及十时代对战共用四首 Yourset 完整曲目，每轮随机排序并各播放一次；跨轮避免连续重复同一首，曲间 2 秒淡入淡出。进化与菜单切换不会重启音乐，应用后台暂停并保留位置；胜负平局仍有独立结算短曲。

v0.7.1 ships the opaque male-knight app icon and transparent Chinese wordmark. Four full-length Yourset songs share a shuffled playlist across menus and all ten eras: each plays once per cycle, consecutive repeats are avoided across cycles, and songs crossfade for two seconds. Menu/era changes keep the current song; backgrounding pauses at the current position. Result stings remain separate.

v0.7.2 拉开三档 AI 的开局金币与持续收入：轻松 0.80× / 0.85×，标准 1.25× / 1.35×，挑战 1.50× / 1.65×。玩家资源不变。双方成功进化时，首都最大生命与兵种生命倍率一致增长，并恢复满血；双方仍独立赚取战斗经验并升级。

v0.7.2 separates AI starting gold / passive income by difficulty: Easy 0.80× / 0.85×, Standard 1.25× / 1.35×, Challenge 1.50× / 1.65×. Player resources stay unchanged. Each successful evolution scales that side's capital health with troop HP and fully heals it; sides still earn combat XP and evolve independently.

## 游玩 / Playing

摧毁敌方基地获胜。双方独立获取经验并进化；已存在的普通兵、炮塔和付费训练订单保留原时代。当前游戏界面为中文，仓库提供完整中英双语说明。

Destroy the enemy base. Each side earns XP and evolves independently; existing regular troops, turrets and paid orders keep their original era. The current game UI is Chinese; the repository includes a bilingual guide.

| 操作 / Action | 输入 / Input |
| --- | --- |
| 招募 / Recruit | `1`–`5` |
| 战鼓 / War drum | `Z` |
| 烟幕 / Smoke | `X` |
| 补给 / Supplies | `C` |
| 指挥官 / Commander tray | `Q` |
| 进化 / Evolution | `E` |
| 暂停、返回或取消瞄准 / Pause, back or cancel targeting | `Esc` |
| 移动视野 / Pan | `A` / `D`, `←` / `→`, mouse wheel or battlefield drag |
| 定位基地 / Focus bases | `Home` / `End` |

技能选择后点击合法战场落点；右键取消。屏幕按钮支持鼠标与触屏。设置页提供总音量、配乐、战斗、界面、降低镜头动态和全屏选项。

After selecting a targeted skill, click a valid battlefield location; right-click cancels. On-screen controls support mouse and touch. Settings include four audio groups, reduced camera motion and fullscreen.

存档位于 Godot 的本机 `user://` 数据目录；各平台档案独立。保留对局后可从营地继续。

Saves are local to Godot's `user://` data directory. Platforms keep separate profiles. Use the pause menu to retain a match and continue it from camp.

## 源码与说明 / Source and documentation

[GitHub 仓库 / Repository](https://github.com/wikigsroom/Evolutionary-history-of-war) 包含十时代、50 兵种、六位主将、20 关战役、30 张地图的源码、运行素材、实机截图和 GIF。

The repository contains source, runtime assets, native screenshots and GIFs for ten eras, 50 troops, six commanders, 20 campaign missions and 30 maps.

随包包含 Godot 引擎、字体和音频来源声明。原有公开音效采用 CC0；四首 Yourset 曲目由项目所有者指定提供，分别标记，不适用 CC0。项目源码及自制美术尚未指定统一开源许可，第三方资源分别适用其自身许可。

The package includes Godot, font and audio notices. Legacy public SFX are CC0; the four owner-supplied Yourset tracks are credited separately and are not covered by CC0. No repository-wide open-source license has been selected for the project code and original artwork; third-party resources retain their own licenses.

0.7.3：Android 等比扩展铺满、边到边沉浸模式、交互 UI 安全区与前台恢复。
0.7.3: proportional full-screen expansion, Android edge-to-edge, safe interactive UI and immersive resume.
