# 纪元急袭（Godot 独立重构）

这是《纪元急袭》 / Epoch Rush: Pixel Command 的原生 **0.8.1** 线路。完整的中英玩法、菜单示意图、实机截图、GIF、构建步骤与当前限制见 [仓库总览](../README.md)。旧的 Phaser 0.3.1 客户端保留在仓库根目录，两套运行时版本分别维护。

预构建 Windows 与 Android 包见 [v0.8.1 Release](https://github.com/wikigsroom/Evolutionary-history-of-war/releases/tag/v0.8.1)，已包含 [十时代营寨朝向修复](../docs/epoch-rush/godot-base-facing-fix.md)。Windows 推荐下载完整 ZIP，解压运行即可；Android 当前完成包与签名验证。

品牌、BGM 更新与实际验证见 [v0.7.1 报告](../docs/epoch-rush/godot-v0.7.1-branding-bgm-report.md)。

## 当前实现

- `GameModel` 把我方 `ally_era` 与敌方 `enemy_era` 作为两个独立状态；双方使用各自交战经验支付升级，不以计时器自动追平。
- 主菜单按照营地、战役地图、军团配置、时代百科、设置、战斗 HUD、暂停/结算分层。
- UI 采用方案 1「像素指挥卡组」：深海军蓝底、4px 网格、圆角像素卡片、青蓝我方/红色敌方/琥珀进化提示、图标优先。
- 战斗包含体积占位与接敌排队、基地耐久、独立时代升级、主动道具、研究与炮塔。招募目录随本方时代更新，旧兵与已付费订单保留原时代。
- 0.6.1 修正双方朝向与让位速度；提供常驻图标进度队列、左右拖拽地图、小地图定位和道具反馈。下载与验证见 [本版报告](../docs/epoch-rush/godot-v0.6.1-repair-report.md)。
- 最新不透明男性骑士图标与透明“纪元急袭”文字 LOGO 已应用于 Windows 和 Android；菜单、十时代对战共用四首 Yourset 随机 BGM，每轮不重复，跨轮避免连续同曲，曲间 2 秒淡化。保留 43 类 / 129 个音效变体、材质与武器反馈、声音分组、镜头声像、重大事件混音和结算短曲。[声音设计](SOUND_DESIGN.md) 记录来源、处理规则和事件映射。
- `BattleWorld` 使用现有生成资产的基地、战场背景、单位卡图，同时用 Godot 自绘粒子与状态条保证在 Windows/Android 都能运行。

0.7.0 扩展为十时代、50 兵种、六位主将的 60 套时代形态、20 关战役、30 张候选地图。时代奇袭、动态天空与弱随机事件已接入；图鉴可从指定时代开始标准对战，当前会正常保存与结算，不是无奖励沙盒。医疗和持续护盾共用恢复预算，相邻时代同定位伤害至少五倍。见 [十时代交付报告](../docs/epoch-rush/godot-v0.7-ten-eras-report.md) 和 [公开验收证据](../docs/qa/v0.7.0/README.md)。

## 联机

主菜单新增联机入口：真实玩家自由匹配、六位数字创建/加入、构筑与双方准备、自动原局重连和重启恢复。双端资源由服务器裁判计算，双方同等经济与构筑预算。完整操作见 [服务端 README](../services/online-gateway/README.md) 与 [v0.8.1 实现报告](../docs/epoch-rush/godot-v0.8.1-public-online-report.md)。离线游戏仍可直接运行；线上结算不写入单机养成。

正式客户端默认连接 **https://jyqx-server.sidcloud.cn**。主菜单 → 联机 → 同意并连接 → 自由匹配或相同六位码 → 双方准备/接受。SIDcloud 在新加坡运营，当前最多两局/四人同时对战。首次进入联机页不创建线上身份，明确连接后启用；已加入的原局可自动恢复。Windows 私有服包可解压用原生 PowerShell 启动，Linux 部署见 [运维说明](../services/online-gateway/deploy/linux/README.md)。所有组件原生运行，不使用 Docker/WSL/虚拟机。

## 运行

安装 Godot **4.7.2 Standard**，将引擎加入 PATH，或使用自己的绝对引擎路径。以下命令在仓库根目录执行；运行原生游戏不需要 Node.js 或图片生成接口。

```powershell
godot --headless --path godot --editor --import
godot --path godot --editor
godot --path godot
```

缓存、工具链和导出包均被 Git 忽略；资源 `.import` 配置、脚本 `.uid` 与运行素材随源码保留。全部步骤在本机原生执行，不使用 Docker、WSL 或虚拟化。

## 导出

从仓库根目录执行，先安装同版本 Export Templates 并复制无凭据的导出模板。私有配置和密钥不入库。

```powershell
Copy-Item godot/export_presets.example.cfg godot/export_presets.cfg
New-Item -ItemType Directory -Force godot/build/windows, godot/build/android | Out-Null
godot --headless --path godot --export-release "Windows Desktop" build/windows/Epoch-Rush-Godot.exe
python -X utf8 tools/package_godot_windows.py
```

Windows 打包脚本附带引擎、字体、音频声明（CC0 音效与用户提供 BGM 分开标记），并输出 ZIP 与校验和。安装包不上传源码仓库，`build/` 路径表示本机输出。

Android 需要配置自己的签名、SDK、Java 和 debug keystore：

```powershell
python -X utf8 tools/online/prepare_android_build.py
python -X utf8 tools/online/build_android_secure_store.py
godot --headless --path godot --export-release "Android" build/android/Epoch-Rush-Godot-release.apk
godot --headless --path godot --export-debug "Android" build/android/Epoch-Rush-Godot-debug.apk
python -X utf8 tools/finalize_android_packages.py
```

Android 需要本机 JDK 21 与 Android SDK 36。应用 ID 为 `studio.epochrush.pixelcommand`，版本 0.8.1 / code 14，arm64、最低 API 24。Android 使用自定义 Gradle 模板与自有 Keystore 插件，仅声明 INTERNET 权限；构建准备脚本删除引擎继承的电话/共享存储权限。后处理检查 adaptive-icon 资源别名，按 16 KB 原生页对齐并以本机密钥重新签名。脚本支持 `JAVA_HOME`、`ANDROID_SDK_ROOT` / `ANDROID_HOME` 及根 README 所列覆盖变量。两个 APK 导出完成后运行一次；已记录包验证，尚无真机试玩结果。

## 基础回归

```powershell
New-Item -ItemType Directory -Force output/qa/ten-eras | Out-Null
godot --headless --path godot --script res://qa/ten_era_rules.gd
godot --headless --path godot --script res://qa/ten_era_skills.gd
godot --headless --path godot --script res://qa/ten_era_restore.gd
```

旧存档样本已包含在 `qa/fixtures/`。音频和交互检查使用真实驱动，不能以 headless 的 Dummy 音频替代实际声音。详细英文说明、操作与当前规划均见 [bilingual README](../README.md)。

