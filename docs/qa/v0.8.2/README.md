# v0.8.2 验证记录

本目录记录最终 Windows 导出资源包及双 APK 的验证结果。运行命令使用原生 Windows 工具，没有 Docker、WSL、虚拟机或 Android 模拟器。

| 验证 | 结果文件 | 范围 |
| --- | --- | --- |
| 联机版面 | [lobby-layout.json](lobby-layout.json) | 65 项；九种活动状态、五种窗口、安全区及六位主将 |
| 网络故障恢复 | [lobby-reconnect.json](lobby-reconnect.json) | 12 项；首次失败、空大厅中断、后台/前台与过期身份 |
| 公共双客户端 | [native-client-playable.json](native-client-playable.json) | 24 项；原生连接、入房、准备、指令及原局恢复 |
| 旧配置迁移 | [endpoint-lock.json](endpoint-lock.json) | 5 项；旧地址忽略、构筑保留与无编辑 API |
| Android 安装包 | [online-android.json](online-android.json) | 双包合计 24 项；版本、权限、安全存储及最终脚本/字体一致 |
| 签名与对齐 | [android-finalization.json](android-finalization.json) | 双包签名及 16 KB 原生页对齐 |
| 品牌资源 | [launcher-branding.json](launcher-branding.json) | 44 项 PE/APK 品牌资源 |
| 字体 | [font-coverage.json](font-coverage.json) | 游戏中文字形完整 |
| 服务兼容性 | [authority-compatibility.json](authority-compatibility.json) | 0.8.1 公共服务与本版战斗协议一致 |
| 隐私发布 | [privacy-live.json](privacy-live.json) | 六条公网路径与本次审核文档一致；15 页原生 Word 渲染复核 |
| 包与截图来源 | [release-artifacts.json](release-artifacts.json) / [media-provenance.json](media-provenance.json) | 四个发布包的大小、SHA-256 及图片来源 |

界面截图分别注明真实公共对局与状态样例。最终资源包检查通过不等于 Android 真机试玩；本次没有实体 Android 设备验收。公共服务器继续运行 0.8.1，本次未重复执行服务端崩溃、数据库断开或容量压力测试，其既有证据见 [v0.8.1](../v0.8.1/README.md)。

复核命令：

```powershell
python tools/online/run_native_checks.py --script qa/online/lobby_layout.gd --pack
python tools/online/lobby_reconnect_smoke.py --pack
python tools/online/run_native_checks.py --script qa/online/client_playable.gd --pack
python tools/online/run_native_checks.py --script qa/online/endpoint_lock.gd --pack --headless
python tools/online/run_native_checks.py --script qa/online/package_contract.gd --pack --headless
python tools/online/inspect_online_packages.py
python tools/online/prepare_client_patch.py
```
