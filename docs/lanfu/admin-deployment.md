# LanFu 管理员部署与配置说明

## 产品形态

LanFu 是员工各自安装、各自使用的公司版 AI 助手。它不是集中式平台：没有 SSO、没有多租户、没有统一管理后台，每台电脑上是一个独立的 Gateway 与独立的数据目录。

## 默认配置（安装时自动写入）

首次运行时安装脚本会写入 %USERPROFILE%\.lanfu\lanfu.json（Linux 为 ~/.lanfu/lanfu.json；旧版安装留下的 openclaw.json 会在网关首次启动时自动改名为 lanfu.json），要点：

| 键                            | 值                            | 说明                           |
| ----------------------------- | ----------------------------- | ------------------------------ |
| gateway.mode                  | local                         | 只监听本机回环地址             |
| gateway.bind                  | loopback                      | 不对局域网开放                 |
| gateway.auth.mode             | token                         | 每次安装随机生成 token         |
| models.providers.vllm.baseUrl | http://100.116.120.40:8000/v1 | 公司模型服务（Tailscale 地址） |
| models.providers.vllm.api     | openai-completions            | OpenAI 兼容接口                |
| agents.defaults.model         | vllm/qwen38                   | 默认模型                       |
| update.auto.enabled           | false                         | 关闭自动更新                   |

要改默认地址，编辑 packaging/windows/post-install.ps1 里的 -ModelBaseUrl / -DefaultModel 参数后重新发版；员工端也可以直接改上面这个 JSON。

## 网络前提

当前公司模型服务通过 Tailscale 暴露（100.116.120.40:8000），因此员工电脑必须登录 Tailscale。后续改成内网直连时，只需把 baseUrl 换成内网地址。

## 安全注意事项

- Gateway 只绑定回环地址，默认不对同事或局域网开放；不要把 gateway.bind 改成 lan，除非确实需要。
- 每次安装的 gateway.auth.token 是随机值，不要跨机器复用。
- 员工数据（会话、记忆、凭据）保存在员工自己的电脑上，公司不做集中收集。
- 安装包未做代码签名，Windows 可能提示未知发布者；正式大规模分发前建议购买代码签名证书。

## 发布与更新

见 release.md。当前没有自动更新：新版发布后由员工重新下载安装包覆盖安装，用户数据保留。
