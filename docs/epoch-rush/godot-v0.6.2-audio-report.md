# 纪元急袭 · 0.6.2 声音更新与交付

日期：2026-10-07。已在当前 Godot 游戏中应用新的配乐、战斗音效与混音体系，并更新 Windows 与 Android 成品。旧 Phaser 客户端也同步使用新素材、武器/材质音效映射和变体；Godot 的声部分配、独立音量和后台恢复由独立原生模块实现。

直接体验：[Windows 更新包](../../godot/build/windows/Epoch-Rush-Godot-Windows.zip)、[Android 安装包](../../godot/build/android/Epoch-Rush-Godot-release.apk)。试听：[约 24 秒实战声音](../../output/qa/godot-audio/audio-showcase.mp3)、[对应五代战斗演出](../../output/qa/godot-audio/audio-showcase.mp4)。演出从最终 Windows 资源包录制，包含攻击、护盾、技能、道具、进化、基地倒塌和结算。

## 本次修正

| 原问题 | 更新后的行为 |
| --- | --- |
| 配乐多为相似的短合成旋律 | 菜单与五个时代使用不同的公开音乐，统一做响度和频段处理 |
| 人物受击大量使用石块声 | 肉体、木盾、金属装备、石质基地分别处理；能量和箭矢命中也有区别 |
| 近战挥击缺声音 | 短兵、长兵、投掷、弓弦、火枪、火炮、能量、辅助八种攻击模组全部接入 |
| 技能与道具声音过于相似 | 按技能表核验 12 个通用技能、6 个英雄技能；战鼓、烟幕和补给有各自音色 |
| 电击、能量场都用轨道爆炸 | 共振网用脉冲、脉冲链用电弧、裂隙场用能量场；轨道爆炸用于时代奇袭 |
| 冲锋重击缺重量感 | 贯阵冲锋命中叠加低频重击；爆炸伤害按类别处理 |
| 切歌突兀、胜负音乐无限重复 | 原生 Ogg 循环、时代切歌淡入淡出、胜利/失败/平局短曲各播一次 |
| 密集战斗容易吞关键声音 | 18 个声部、重大事件/界面预留声部、优先级抢占、同帧合并和同类数量限制 |
| 音量调节粗糙 | 总音量、配乐、战斗、界面分别调节；总音量 0 的实际混音为全零 |

## 配乐与生成内容

6 段循环配乐、3 段结算短曲；43 类音效、每类 3 个变体，共 129 个 48 kHz 单声道 WAV。音效采用公开录音分层，并生成瞬态、低频、警示与旋律层；保留攻击起音和尾音，不将全部事件变成同一种蜂鸣。

| 场景 | 音乐 / 作者 | 方向 | 实测 LUFS |
| --- | --- | --- | --- |
| 菜单 | [relax_background1 / joaquinton](https://opengameart.org/content/relaxbackground1-0) | 温暖拨弦、整军氛围 | -20.00 |
| 原始时代 | [Krakatoa / Kistol](https://opengameart.org/content/krakatoa) | 木质打击乐、部落节奏 | -19.00 |
| 军阵时代 | [Epic March Loop / Eldritch Grim](https://opengameart.org/content/epic-war-loop) | 行进鼓、军阵推进 | -19.04 |
| 王国时代 | [Hope / MintoDog](https://opengameart.org/content/hopeorchestral-battle-music) | 明亮管弦、冲锋军鼓 | -19.05 |
| 工业时代 | [8-Bit Battle Loop / Theodore Kerr](https://opengameart.org/content/8-bit-battle-loop) | 机械感芯片节奏 | -19.06 |
| 星际时代 | [Awake! / cynicmusic](https://opengameart.org/content/awake-megawall-10) | 电子碎拍、科技战斗 | -19.05 |

录音层来自 Kenney 的 [Impact Sounds](https://kenney.nl/assets/impact-sounds)、[RPG Audio](https://kenney.nl/assets/rpg-audio)、[Sci-Fi Sounds](https://kenney.nl/assets/sci-fi-sounds)、[Interface Sounds](https://kenney.nl/assets/interface-sounds) 和 [Music Jingles](https://kenney.nl/assets/music-jingles)。逐个来源页面已确认 CC0-1.0，并留存原始下载、许可页面与 SHA-256。完整声明见 [音频素材与作者](../../godot/assets/audio/Audio-CREDITS.txt)，许可随 Windows ZIP 与 Android 资源包保存。

已安装并参考社区 [creating-godot-procedural-audio 技能](https://github.com/abagames/agentic-gamedev-skills/blob/main/.agents/skills/creating-godot-procedural-audio/SKILL.md)，本机位置为 `C:/Users/carzy/.codex/skills/creating-godot-procedural-audio/`，后续会话可发现。完整设计、事件映射、制作方法和复建步骤见 [SOUND_DESIGN.md](../../godot/SOUND_DESIGN.md)。音乐来源、实际使用的录音与每个声音的参数见 [音频目录](../../godot/assets/audio/catalog.json)。

## 混音与使用

设置页和暂停菜单都提供四个音量滑块。将“战斗”设为 0，可保留界面声音；关闭“攻击与界面音效”会一起关闭这两组。旧设置文件会自动补充新字段。

战场声音随镜头做左右定位和画外衰减，界面提示居中。重要演出短暂让配乐降低音量；暂停清理攻击尾音，后台暂停音乐，返回后继续播放。基地生命低于 28% 后才发危急提醒，间隔至少 6.2 秒；技能冷却完成有短提示。敌方招募不触发玩家的招募提示，敌方进化也不会切换玩家配乐。

Godot Mix 总线设置 -1 dB 限幅，同时限制发声量；避免依赖把所有素材直接调大来制造打击感。菜单和五代音乐采用原生循环，结算短曲不会在调整音量后重新触发。官方能力参考：[Ogg Vorbis 循环](https://docs.godotengine.org/en/stable/classes/class_audiostreamoggvorbis.html)、[硬限幅](https://docs.godotengine.org/en/stable/classes/class_audioeffecthardlimiter.html)、[实际音频采样](https://docs.godotengine.org/en/stable/classes/class_audioeffectcapture.html)。

## 验证

| 验证 | 结果 |
| --- | --- |
| 最终 Windows 成品资源包的音频回归 | 245 项通过；覆盖全部 18 个技能的真实施放流程、八种攻击模组、材质、护盾、道具、循环、结算、声像、静音、满载、合并、暂停与后台 |
| 最终成品交互回归 | 74 + 104 项通过；包括菜单设置、暂停、触屏事件与既有游戏交互 |
| Windows 实际音频驱动 | WASAPI，48 kHz 立体声；捕获最终混音，不使用 Dummy 驱动代替 |
| 实际混音削波 | 0 个削波样本；压力混音最大幅值约 0.89126，符合 -1 dB 限幅 |
| 文件与信号 | 129 个音效变体、9 段音乐全部可解码；哈希、起音、直流、循环边界与响度检查通过 |
| 基础规则与技能 | 120 项规则、162 项修复规则、20 项技能回归通过 |
| 旧网页客户端 | 116 项测试通过；生产构建通过 |
| 成品资产 | 31 个角色、62 张图集、1860 个非空帧；两套字体均覆盖当前 673 个所需汉字 |
| Android | 两包 versionName 0.6.2 / versionCode 8；arm64；签名 v2/v3、16 KB 对齐、CRC、内容核验通过 |
| Windows 独立启动 | 最终 EXE 启动退出码 0，运行日志无错误 |

本次改动期间的本机性能采样：24 人场景帧间隔 P95 4.045 ms；60 人合成压力场景 P95 11.915 ms，最高 33.515 ms 包括场景重建。后续技能声音分类调整未增加声部或素材，这份采样记录保留于 `output/qa/godot-audio/exported/performance/`，不作为 Android 帧率或所有设备的性能保证。

技术采样验证不等同于耳机、扬声器上的主观试听；提供的片段与成品可直接用于试听和调节。未连接 Android 真机，因此本次 Android 结果限于构建与包验证。全程使用 Windows 原生工具，没有调用 Docker、WSL，也没有开启交互浏览器标签页。

汇总证据：[音频交付记录](../../output/qa/godot-audio/audio-delivery-summary.json)、[信号检查](../../output/qa/godot-audio/audio-signal-checks.json)、[最终音频回归](../../output/qa/godot-audio/exported/audio_regression/audio-regression.json)、[包校验](../../output/qa/godot-audio/package-asset-checks.json)。变更前的代码、声音和 Windows 包保存在 `output/qa/godot-audio/baseline-0.6.1.zip`。

Windows EXE SHA-256：`70a4e0d126fc3978b25dae8b7178880950e3e4f48b6d67bf47b6b05a61927d56`。
