# 《纪元急袭》品牌图片修订

日期：2026-10-08。使用已选 H03 男性骑士与现有像素原画，完成第 2–5 条要求。正式游戏名为“纪元急袭”。

| 要求 | 已完成调整 | 当前文件 |
| --- | --- | --- |
| 2. 游戏图标不得使用透明背景 | 骑士图标铺满深蓝背景，1024、512 PNG 及 ICO 各尺寸完全不透明 | [1024 PNG](../../output/marketing/2026-10-08/brand/game-icon-opaque-1024.png)；[512 PNG](../../output/marketing/2026-10-08/brand/game-icon-opaque-512.png)；[ICO](../../output/marketing/2026-10-08/brand/game-icon-opaque.ico) |
| 3. 游戏 LOGO 使用透明背景 | 输出真实 RGBA PNG，画布四角及字形外部透明 | [2048×512](../../output/marketing/2026-10-08/brand/game-logo-transparent-2048x512.png)；[1024×256](../../output/marketing/2026-10-08/brand/game-logo-transparent-1024x256.png) |
| 4. LOGO 仅含游戏名文本 | 使用得意黑制作“纪元急袭”四字，采用金色像素层次；不附其他文字 | 同上两份透明 LOGO |
| 5. 封面、宣传图仅保留游戏名 | 删除宣传语、英文副标题、主题说明和功能数量，从无字原画重新排版；带标题图片只含“纪元急袭” | 下表中的九张成图，另附各自 JPG |

## 封面与宣传图

| 素材 | 尺寸 | 文件 |
| --- | --- | --- |
| 横版封面 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/covers/horizontal-cover-1920x1080.png) |
| 竖版封面 | 1080×1620 | [PNG](../../output/marketing/2026-10-08/covers/vertical-cover-1080x1620.png) |
| 宣传图：时代进化 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/promotional/01-evolution-1920x1080.png) |
| 宣传图：中世纪重骑 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/promotional/02-medieval-1920x1080.png) |
| 宣传图：工业火炮 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/promotional/03-industrial-1920x1080.png) |
| 宣传图：现代装甲 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/promotional/04-modern-1920x1080.png) |
| 宣传图：轨道机甲 | 1920×1080 | [PNG](../../output/marketing/2026-10-08/promotional/05-orbital-1920x1080.png) |
| Banner | 2304×768 | [PNG](../../output/marketing/2026-10-08/banners/game-banner-2304x768.png) |
| 海报 | 1536×2304 | [PNG](../../output/marketing/2026-10-08/posters/game-poster-1536x2304.png) |

宣传片缩略图同步采用新横版封面。图像总览未附加说明字样，可在 [宣传图与封面总览](../../output/marketing/2026-10-08/previews/promotional-covers-overview.jpg) 检查构图。两版游戏库超分壁纸及无 LOGO 原画继续保持无文字、无品牌徽章。

## 文件包与检查

[商店上传图片包](../../output/marketing/2026-10-08/Epoch-Rush-Store-Images-2026-10-08.zip) 包含 29 个图片文件及说明，约 94.4 MiB。目录按 `brand`、`covers`、`promotional`、`banners`、`posters`、`wallpapers` 分组，可直接选择上传。包内不包含历史角色参考图、制作脚本或视频。

[完整素材包](../../output/marketing/2026-10-08/Epoch-Rush-Marketing-Kit-2026-10-08.zip) 同步更新以上图片，保留之前已验收的截图、实机视频、文案、生成原画和制作证据。完整包中的 `source/selected-logo.png` 是历史命名的骑士来源参考；正式 LOGO 位于 `brand/game-logo-transparent-2048x512.png`。

PNG 的尺寸、模式、Alpha 范围、ICO 所有尺寸的透明度、唯一排版文本及文件 SHA-256 已通过程序检查，并目视复查图标、透明 LOGO、五张宣传图、横竖封面、Banner 与海报。图标 PNG 为 RGB，Alpha 等价于全 255；正式 LOGO 为 RGBA，透明范围为 0–255。图片 ZIP 通过 CRC 与解压内容 SHA-256 检查。

检查记录：[品牌合规报告](../../output/marketing/2026-10-08/source/branding-compliance.json)、[上传包校验报告](../../output/marketing/2026-10-08/store-package-report.json)、[画面复查](../../output/marketing/2026-10-08/source/visual-review.json)。

项目内 `public/app-icon.png`、`public/app-icon.ico`、Godot 图标及 Android / iOS 图标资源已同步；正式文字 LOGO 位于 `public/brand/game-logo.png`。Android 自适应图标使用透明人物前景与不透明背景层，最终合成图标不透明。2026-10-09 的 v0.7.1 已将最新图标及透明文字 LOGO 应用于 Windows EXE 与两个 Android APK 并更新 GitHub Release，详见 [本次交付报告](godot-v0.7.1-branding-bgm-report.md)。

品牌制作与图片打包脚本位于 `tools/marketing/build_brand_assets.py`、`build_images.py`、`package_store_assets.py`。全部处理使用 Windows 原生进程。
