# 《纪元急袭》隐私政策

本目录保存根据用户提供的 `privacy-policy-template.docx` 更新的正式隐私政策。版本为 **ER-PRIVACY-2026-10-09**，更新日期、生效日期均为 **2026 年 10 月 9 日**。

## 文档与页面

| 文件 | 用途 |
| --- | --- |
| `纪元急袭隐私政策.docx` | 保留原模板版式的 Word 正文，共 12 页 |
| `privacy-policy.zh-CN.md` | 便于阅读和审阅的同版 Markdown 正文 |
| `policy.json` | 已填入运营者信息的结构化正文 |
| `../../web/privacy-policy/` | 独立静态网页、Word/Markdown 下载及 Vercel 配置 |

正式公开 HTTPS 地址：[《纪元急袭》隐私政策](https://jyqx.sidcloud.cn/)。已部署到 `sidcloud` 团队的 `jyqx-privacy-policy` 项目。备用生产地址为 [jyqx-privacy-policy.vercel.app](https://jyqx-privacy-policy.vercel.app)。

自定义域名 `jyqx.sidcloud.cn` 的 DNS 与所有权验证已通过，HTTPS 证书有效。2026 年 10 月 9 日 15:24（UTC+8）完成主体修订后的无登录直连访问复核，三个页面入口、样式、图片和下载文件均返回 HTTP 200，并与正式源文件逐字节一致。准确 DNS 记录及验收证据见 [自定义域名部署记录](custom-domain.md)。

此前 Vercel 官方 CLI 创建的临时部署为 `temporary-flying-cello-u61kcq3.vercel.app`，到期时间为 **2026 年 10 月 8 日 12:00:39（UTC+8）**。它已跳转至 Vercel 的“部署已过期”页面，由以上正式部署替代。

## 适用范围

当前 Godot 原生 **0.7.1** 版本，支持 Windows 和 Android。Android 包名为 `studio.epochrush.pixelcommand`。历史 Web/Electron/Capacitor 版本及未来另行加入的联网功能不应直接套用当前版本说明。

开发及运营主体为 **SIDcloud**，与用户在 2026 年 10 月 9 日明确指定的资料页公司主体一致。隐私联系邮箱为 **carzyg@outlook.com**。网页正文、Word 正文与作者信息、Markdown 和结构化来源均使用同一主体名称。

## 更新依据

在原模板的十个主题下，按实际游戏代码、原生 Android APK 权限清单和网站行为重新编写：

1. 本机游戏数据、设置、对局状态、诊断日志与主动联系信息的处理。
2. 本机保存位置、联系材料的保存原则及网页托管涉及的跨境处理。
3. Cookie 和同类技术；本网页不启用访问统计、广告脚本或在线表单。
4. 共享、转让、公开披露及依法处理的边界。
5. Vercel 网页托管和 Microsoft Outlook 邮件服务的具体用途及隐私说明。
6. 实际安全措施、普通 JSON 存档的保护边界及安全事件处理。
7. 查阅、更正、删除、撤回同意，以及 Windows/Android 清理本机数据的方法。
8. 未成年人、未满十四周岁儿童和监护人请求的保护措施。
9. 更新告知、未来联网功能变更及必要的重新同意。
10. 真实联系邮箱、请求方式、合理核验和答复期限。

本版本代码未接入在线账号、云存档、广告、支付、统计或自动日志上传。APK 未声明 `uses-permission`，且自动备份关闭。游戏的离线行为与用户主动访问隐私网页、主动发邮件的网络行为分别说明。

## 校验与部署

- 原始模板保持不变。Word 经本机 Microsoft Word 导出和逐页视觉检查，最终 12 页。
- Word 的 20 个未编辑 OOXML 包部件与原模板字节一致；正文、补充标题样式及文档元数据按更新需要修改。
- 本次主体修订只修改 Word 正文及核心元数据两个 OOXML 部件，其余 22 个部件与修订前文档字节一致；原有版式保持，重新导出后逐页检查 12 页。
- 网页在 1280、390 和 320 像素宽度下验证无页面水平溢出，十个正文主题及目录锚点完整。
- 实际点击下载的 Word 和 Markdown 与正式文件 SHA-256 一致。
- 2026 年 10 月 9 日自定义域名 `https://jyqx.sidcloud.cn` 的公开访问复核：`/`、`/privacy`、`/privacy-policy`、样式、骑士图片、Word 和 Markdown 均返回 HTTP 200；所有响应与正式源文件逐字节一致。采用无登录、无代理直连，保持默认 TLS 证书及主机名校验，HTTP 自动跳转 HTTPS。
- 公开 HTTPS 页面已用无登录、无用户浏览器资料的独立浏览器验证。当前本机访问 `vercel.app` 存在 DNS 解析异常，公开访问检查通过本机已配置的现有网络代理完成；未修改系统或用户浏览器设置。
- 页面不加载外部资源，不包含 JavaScript、表单或访问统计；Vercel 仍会处理网页交付所需的技术请求信息。
- 部署内容限定为 `index.html`、`styles.css`、`vercel.json`、两个正文下载文件和骑士图标，不上传游戏代码、APK、签名配置或审计材料。
- Vercel 生成的 `.vercel/` 状态目录、环境文件、`.gitignore` 和 `.vercelignore` 不属于公开页面。生产发布采用经过白名单校验的 Build Output API 静态输出；`/.env.local` 与 `/.vercel/anonymous.json` 公开访问均返回 404。
- 全部操作使用本机 Windows 工具；浏览器检查结束后关闭专用页面、上下文和浏览器进程。

初始排版、来源核对和检查记录位于 `output/privacy-policy/2026-10-08/`，本次主体修订及公开访问校验记录位于 `output/privacy-policy/2026-10-09/operator-correction/`。编写工具位于 `tools/privacy/`。`build_privacy.py` 优先读取本目录的 `policy.json` 正文及其 `operator` 主体信息；历史模板和编写缓存保留于初始工作记录的 `source/` 子目录。修改正文时应同步 Word、Markdown 和网页，避免多个版本不一致或旧缓存覆盖已修订的主体名称。

### 本机预览

使用本机 Python 运行：

```powershell
python tools/privacy/serve_site.py web/privacy-policy
```

该命令仅监听本机回环地址并输出实际端口。检查结束后关闭该服务。

### Vercel 发布

官方 CLI 62.7.0 已完成账号认证；`web/privacy-policy/` 已关联 `sidcloud/jyqx-privacy-policy`。后续更新正文并同步页面文件后，在仓库根目录执行：

```powershell
python tools/privacy/deploy_vercel.py --authenticated --production --scope sidcloud
```

该脚本准备 Vercel Build Output API v3 静态输出，以 `--prod --prebuilt` 发布，保留页面路由、安全响应头和下载文件，随后仍应以未登录访客验证公开访问。当前正式部署 ID 为 `dpl_5JayjyrZLvxb1PdMZa8rkT6JZZya`，状态为 `READY`。本次公开访问校验记录位于 `output/privacy-policy/2026-10-09/operator-correction/public-verification.json`，原 DNS 配置记录位于 `output/privacy-policy/2026-10-09/domain-binding/`。

认证信息只交给 Vercel 官方登录流程，不写入本文、网页或仓库。临时部署仅供认领前访问，不应把未认领的到期地址作为长期发行配置。

## 核对的公开资料

- [《中华人民共和国个人信息保护法》](https://www.cac.gov.cn/2021-08/20/c_1631050028355286.htm)
- [Vercel Privacy Notice](https://vercel.com/legal/privacy-notice)
- [Microsoft 隐私声明](https://www.microsoft.com/zh-cn/privacy/privacystatement)
- [Vercel 官方 CLI 登录说明](https://vercel.com/docs/cli/login)

后续若新增 SDK、联网、广告、支付、敏感权限或不同运营主体，应按真实变化修订政策，并实现相应的产品告知与同意流程。
