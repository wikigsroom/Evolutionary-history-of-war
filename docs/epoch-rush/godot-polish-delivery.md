# 纪元急袭 · Godot 0.6.0 交付记录

> 此文为 0.6.0 历史交付记录。当前可运行路径已更新为 0.6.1，修复、朝向检查纠正与最新验证见 [0.6.1 报告](godot-v0.6.1-repair-report.md)。0.6.0 原压缩包保留在 `output/qa/godot-fixes/baseline-Windows-0.6.0.zip`。

交付日期：2026-10-07（Asia/Taipei）。本轮将旧 Godot 骨架重做为可运行的独立 Windows/Android 游戏，采用已经选定的方案 1。这里记录实际完成内容与验证范围；视觉质量的最终判断仍应依据游戏和录像。

## 可运行文件与查看材料

- [Windows 程序](../../godot/build/windows/Epoch-Rush-Godot.exe)：资源内嵌，双击运行，不需要安装编辑器。
- [Windows 完整压缩包](../../godot/build/windows/Epoch-Rush-Godot-Windows.zip)：包含程序、使用说明、引擎和字体许可。
- [Windows 使用说明](../../godot/build/windows/README.md)。
- [Android 发布 APK](../../godot/build/android/Epoch-Rush-Godot-release.apk)：arm64，最低 Android 7.0/API 24，应用版本 0.6.0。
- [Android 调试 APK](../../godot/build/android/Epoch-Rush-Godot-debug.apk)。调试与发布包的签名不同。
- [原速演出视频](../../output/qa/godot-polish/showcase.mp4) 与 [二分之一速度片段](../../output/qa/godot-polish/showcase-slow.mp4)。
- [对战画面](../../output/qa/godot-polish/02-battle-scheme1.png)、[主菜单](../../output/qa/godot-polish/01-home.png)、[整军](../../output/qa/godot-polish/10-loadout.png)。
- [成品资源包横屏画面](../../output/qa/godot-polish/exported/13-battle-2400x1080.png) 与 [成品资源包结算](../../output/qa/godot-polish/exported/15-result.png)。
- [Godot 项目](../../godot/project.godot)。桌面和 Android 均使用原生工具链，没有调用 Docker、WSL 或模拟器。

## UI 与美术

方案 1 的核心结构已落实：顶部双方生命与我方资源、横向四枚辅助图标、夜间战场、显著高于常规人物的基地、五张纸色招募卡、三枚战术道具卡、战略按钮组、金色进化主卡、圆形指挥官头像。

按钮与面板使用像素切角、九宫格明暗压边、纸色和金色材质。图标、夜间背景与五时代基地通过指定的 Sub2/gpt-image-2.5 通道生成；基地同时具备敌方配色、破损和崩塌变体。素材原图及提示词保存在 `output/imagegen/epoch-rush/godot-polish/`。

中文界面采用 Resource Han Rounded 圆体，标题采用得意黑；字体本地打包并附 OFL 许可。字体检查覆盖当前脚本中的 368 个中文字。冷却、次数、锁定、选中、训练进度、进化进度均有实际状态表达；触屏选点提供明确的取消图标。

首页、15 关战役路线与简报、六英雄/专精/技能/遗物/天赋配置、五时代兵种图鉴、音量与动态设置都使用同一套主题。UI 目前仍主要由脚本组装 Control/Container；独立可在编辑器中逐页排版的场景库尚未完全建立。

## 战斗规则与内容

30Hz 固定步长控制战斗，表现层按模型事件消费动作、粒子和音频。双方时代、经验、训练、研究和军令独立保存。升级只改变本方的基地、英雄与后续招募目录，旧兵、原炮塔和已付费订单保留原时代。

地面采用真实体积间距与出口阻挡。短兵队首接敌、长兵越肩支援、远程后排开火；后排支援兵可让位，英雄提供护阵、突击、撤退和驻防恢复。训练遵循 FIFO，完工遇堵等待，取消按是否已开始退款。

完整内容包括五时代 25 兵种、六英雄、12 个通用技能、六专属技能、三类主动道具、同代研究、重型解锁、三炮位及时代奇袭。英雄、兵种光环、护盾、导电、燃烧、压制、破甲、标记和弹道抵达均参与实际结算。敌军按自己的资源、时代、战役配置和战况决定招募、研究、技能与晋升。

15 关战役接入不同的起始时代、时代上限、敌方配置和首领条件。首通解锁、遗物与碎片、掌握点、英雄熟练度、配置保存、设置保存、战斗恢复和奖励去重已接入。

本轮复核修正了同步进化、订单时代、受击提前扣血、状态同次触发、重复返还、光环累加、角色排序、结算弹窗反复重建、旧存档备份复活等问题。返回操作按目标选择、托盘、面板、暂停和结算处理；Android 系统返回由游戏接管并对重复通知去重。已排程技能与待结算命中都纳入存档恢复检查。

## 动作与演出

31 个角色分别使用经过验收的五动作图集、脚底锚点和尺寸数据。行走随位移推进，攻击分蓄力/释放/恢复，伤害按真实近战接触或弹道到达结算；受击图集、方向反馈、闪白和死亡淡出由同一 tick 驱动。

表现包含近战轨迹、箭与枪弹、火炮爆炸、电弧、护盾/治疗、烟幕、伤害与奖励提示、镜头反馈、时代奇袭、基地进化、破损与崩塌。炮塔从实际屋顶挂点发射，弹道朝目标受击高度下降，抵达后结算伤害。效果有数量预算和复用池，音效与模型事件联动；暂停和降低动态设置实际生效。AnimationPlayer 用于闪白与基地演出，普通帧动画按模拟时点播放。

录像从最终 Windows EXE 内的资源包加载录制。录像使用 QA 预设站位与充足资源来展示五时代演出，属于展示场景；真实预算的完整对局另列在下方，不以演示录像证明平衡。

## 验证结果

| 验证对象 | 实际结果 | 证据 |
| --- | --- | --- |
| 战斗规则回归 | 120 项通过 | `output/qa/godot-polish/rules-checks.log` |
| 技能与存档专项 | 20 项通过，包含技能恢复、炮塔枪口与抵达时序 | `skill-checks.json` |
| 角色动作覆盖 | 31 角色，279 项通过 | `animation-checks.json` |
| 原始素材与字体 | 62 图集、1860 个非空帧，SHA 与元数据一致，字体无缺字 | `asset-checks.json` |
| 实际 UI 输入 | 74 项通过；桌面、缩小窗口及横屏尺寸请求；含触屏事件 | `interaction-checks.json` |
| 成品 EXE 资源包 | 同一套 74 项交互通过，无资源缺失；分别记录请求、引擎报告的窗口尺寸与截图像素 | `exported/interaction-checks.json`、`exported-pack-ui.log` |
| Windows 导出程序 | 独立原生窗口实际启动并正常退出，无启动错误 | `exported-ui.log`、`export-windows.log` |
| Android 发布/调试 | 导出成功，17 个 JSON 数据文件均与来源一致，未包含 QA/工具链/密钥 | `package-checks.json` |
| Android 签名与对齐 | v2/v3 签名通过；发布包 16KiB 对齐检查通过 | `apk-signature-release.txt`、`apk-signature-debug.txt`、`apk-alignment.txt` |

### 完整对局

以下六场为当时的自动策略样本，通过真实动作和预算运行，不注入额外金币/经验。更正：0.6.0 检查脚本只在每秒取样点检查地面占位，取样中未发现交叠，原“每 tick”说明不准确。0.6.1 已改为逐 tick 检查，并独立保留最新对局及重放；下表保留历史结果。

| 模式/打法 | 种子 | 时长 | 我方最终时代 | 结果 | 同屏兵力峰值 |
| --- | --- | --- | --- | --- | --- |
| 标准/均衡 | 42571 | 329.4 秒 | IV | 胜利 | 19 |
| 标准/防守 | 27183 | 936.4 秒 | V | 胜利 | 27 |
| 标准/进化竞速 | 3107 | 253.3 秒 | III | 胜利 | 21 |
| M01/均衡 | 48711 | 351.2 秒 | II | 胜利 | 23 |
| M06/均衡 | 98173 | 539.6 秒 | III | 胜利 | 18 |
| M15/竞速 | 31597 | 591.0 秒 | V | 胜利 | 13 |

这些结果证明不同路径可走到完整结算，不代表已经穷尽 15 关与全部配置的难度平衡。竞速可在最终时代前获胜；防守策略用时明显更长。

### 性能测量

Windows 本机、RTX 3060、原生 OpenGL Compatibility、1280×720、关闭垂直同步测量。数据是完整帧间隔，静态内存来自 Godot 监视器，不是完整进程驻留或 GPU 内存。

| 场景 | 样本帧 | 帧耗时中位数 | 95 分位 | 最大值 | Godot 静态内存 |
| --- | --- | --- | --- | --- | --- |
| 24 单位代表场景及持续粒子 | 600 | 2.36 ms | 3.96 ms | 8.79 ms | 60.6 MiB |
| 60 单位额外压力场景及持续粒子 | 540 | 3.59 ms | 11.88 ms | 27.68 ms | 61.7 MiB |

60 单位场景人为密集摆放，专门测量模拟与渲染压力，不是正常单战线的合法站位样本。高压力下仍存在超出 16.67ms 的帧；不能宣称所有设备/场景稳定 60fps，更不能据此保证 Android 性能。详见 `performance.json` 和 `godot/qa/performance.gd`。

## 明确的验证边界

1. 当前没有连接 Android 真机，因此安装、系统返回手势、触屏手感、发热与续航尚未做真机实测。APK 导出、包内容、横屏配置、签名和对齐已校验。
2. Windows EXE 已实际启动。外部原生鼠标注入工具 computer-use 在初始化时连续报 `failed to write kernel assets: 系统找不到指定的路径。 (os error 3)`，因此该验证路径未完成。成品资源包的交互复验由 Godot 编辑器运行时加载 EXE 内嵌资源，通过引擎输入事件执行；它验证了成品代码与资源，但不替代 Windows 物理输入或桌面注入工具的测量。
3. 15 关内容均接入；本轮完整模拟选择 M01/M06/M15 三个代表任务，并未穷举所有难度、英雄、天赋和遗物组合。
4. 新包不声明兼容旧 Phaser 存档，原浏览器工程仍单独保留。此轮未交付 Godot Web 版。
5. 当前未建立迁移前 Phaser 与最终 Godot 的同机、同场景完整性能 A/B。因此不能将本轮性能数据表述为引擎天然优于 Phaser。
6. 游戏保留 16:9 内容比例。请求 2400×1080 窗口所得截图为 1920×1080；本轮验证了横屏尺寸请求下的界面交互和布局，不能表述为已实测 2400 像素宽的移动设备。真实超宽屏上的留边与操作体验仍需设备验证。

## 对“全面使用 Godot 是否所有效果更好”的回答

Godot 更适合本项目继续建立原生动作与演出制作体系，明显收益在动作时点、技能多轨反馈、基地进化/摧毁和统一像素主题的组织与调试。相同图集的普通像素动画并不会因引擎更换自动变好；动作设计、素材连续性、命中时序、音效、镜头和预算仍决定最终质量。

本轮实际采用了这些能力并提供了可运行成品与证据。推荐将 Godot 作为 Windows/Android 主线，但以实际游戏和录像评价质量，继续用明确的规则测试约束玩法，而不以“换了引擎”作为质量验收。

相关官方能力说明：[AnimationPlayer](https://docs.godotengine.org/en/stable/classes/class_animationplayer.html)、[2D 粒子](https://docs.godotengine.org/en/stable/tutorials/2d/particle_systems_2d.html)、[GUI Theme](https://docs.godotengine.org/en/stable/tutorials/ui/gui_skinning.html)、[系统返回设置](https://docs.godotengine.org/en/stable/classes/class_projectsettings.html#class-projectsettings-property-application-config-quit-on-go-back)。完整前期比较见 [重构评估](godot-replatform-evaluation.md)。
