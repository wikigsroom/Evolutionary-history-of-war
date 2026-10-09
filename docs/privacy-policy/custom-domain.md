# 《纪元急袭》隐私政策自定义域名

日期：2026-10-09，Asia/Taipei。目标域名：`jyqx.sidcloud.cn`。网页来源：`web/privacy-policy/`，正式政策文件位于本目录。

## 当前状态

已登录用户账号 `carzyg-7121`，在 `sidcloud` 团队下创建并关联 `jyqx-privacy-policy`。正式入口为 [https://jyqx.sidcloud.cn/](https://jyqx.sidcloud.cn/)，备用生产地址为 [https://jyqx-privacy-policy.vercel.app](https://jyqx-privacy-policy.vercel.app)。当前部署 ID 为 `dpl_5JayjyrZLvxb1PdMZa8rkT6JZZya`，生产状态为 `READY`，无临时部署到期时间。

`jyqx.sidcloud.cn` 已绑定项目 `prj_prtduAtJcAeCCXWoB7Jnu6b1fcmR`。2026 年 10 月 9 日 00:55（UTC+8）初次复核：官方项目域名 API 返回 `verified: true`；DNS 配置返回 `configuredBy: CNAME`、`misconfigured: false`，无冲突。15:24（UTC+8）完成主体修订后的再次生产发布及公开访问校验，域名已提供最新 SIDcloud 政策。

无登录、无代理直连 `https://jyqx.sidcloud.cn/` 验证通过，HTTP 200；默认 TLS 证书和主机名校验正常。当前域名可公开访问，无待完成配置。

此前临时地址 `temporary-flying-cello-u61kcq3.vercel.app` 已过期，由以上生产部署替代。

## DNS 配置

现有 `sidcloud.cn` 的权威名称服务器为 `dns19.hichina.com`、`dns20.hichina.com`。用户已在外部 DNS 服务商配置解析，公共 DNS 与 Vercel 均检测到预期 CNAME，所有权 TXT 验证已通过。原配置记录如下：

| 类型 | 主机记录 / 名称 | 完整记录名称 | 记录值 | 线路 | TTL |
| --- | --- | --- | --- | --- | --- |
| CNAME | `jyqx` | `jyqx.sidcloud.cn` | `43a3bd38074bf29b.vercel-dns-017.com.` | 默认 | 600 秒或服务商默认值 |
| TXT | `_vercel` | `_vercel.sidcloud.cn` | `vc-domain-verify=jyqx.sidcloud.cn,a401f8c4c77161a49fbc` | 默认 | 600 秒或服务商默认值 |

CNAME 记录值为主机名，不填写 `https://`、网页路径或端口；末尾的点表示完整域名。TXT 名称是根域名下的 `_vercel`，不是 `_vercel.jyqx`。TXT 值按表格原样填写，不额外加引号。无需更换根域名的名称服务器。

上述 CNAME 使用官方域名配置 API 返回的第一优先级记录，TXT 来自此前项目域名的真实所有权验证挑战。目前该项目已完成验证，HTTPS 证书已生效。公共 DNS 的 CNAME 与表格一致，记录 TTL 为 600 秒；Vercel 未检测到解析冲突。

## 发布与验收

已完成正式账号认证、项目创建、静态生产发布、项目域名添加、DNS 及所有权验证、HTTPS 和公开访问检查。页面使用显式的 Build Output API v3 静态输出，包含根路径、`/privacy`、`/privacy-policy`、响应头及下载文件。现有生产部署已正确承接自定义域名。

2026 年 10 月 9 日 15:24（UTC+8）自定义域名未登录直连检查结果：三个页面入口、CSS、骑士图片、Word 和 Markdown 下载均为 200，所有公开响应与对应正式源文件逐字节一致。页面含完整游戏名及政策版本 `ER-PRIVACY-2026-10-09`，开发及运营主体统一为 `SIDcloud`；网页和下载正文均不再包含原发布账号的主体名称。初次验收确认 HTTP 自动跳转 HTTPS。本次复核保持默认 TLS 校验，未使用绕过证书验证的选项，通过 Windows 原生命令验证，未打开浏览器标签页。

当前没有待办配置。DNS 解析由用户完成，本轮未修改 DNS 服务商记录。

部署源文件白名单保持为 `index.html`、`styles.css`、`vercel.json`、`privacy-policy.docx`、`privacy-policy.md`、`assets/knight.png`，共六个文件。生产静态输出仅含五个页面 / 下载 / 图片文件及单独的路由配置。发布包和静态输出均通过白名单检查；不包含游戏程序、签名配置、环境文件或 CLI 认证状态。公开访问 `/.env.local`、`/.vercel/anonymous.json` 均为 404。

初始域名配置证据保存在 `output/privacy-policy/2026-10-09/domain-binding/`：`project-domain.json`、`domain-configuration.json`、`dns-records.json`、`custom-domain-verification.json`、`custom-domain-http-verification.json`。本次主体修订的公开访问与文件哈希校验记录位于 `output/privacy-policy/2026-10-09/operator-correction/public-verification.json`。此前备用生产地址的验收保存在 `production-http-verification.json`。认证令牌、登录设备码及临时部署认领凭据不写入本文。

参考：[Vercel 自定义域名设置](https://vercel.com/docs/domains/set-up-custom-domain)、[Vercel 项目域名配置](https://vercel.com/docs/domains/working-with-domains/add-a-domain)。
