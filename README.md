# LanFu（蓝凫）

公司自有的 AI 助手产品：员工在自己电脑上安装后，通过本地网页界面和微信等渠道使用。

- 产品名：**LanFu**；默认助手名：**小蓝**
- 当前版本：**0.1.0**（内部上游基线：OpenClaw 2026.9.6，对外只显示 0.1.0）
- 模型：公司自建 vLLM（默认 http://100.116.120.40:8000/v1，qwen38 / qwen38-think）
- 部署形态：员工各自安装、各自使用；**不是**集中式多人 Agent 平台

## 员工：怎么装

见 docs/lanfu/employee-install.md。

Windows 员工从公司私有仓库的 Releases 下载 LanFu-Setup-x64.exe，双击安装即可——安装包自带固定版本的 Node.js，不需要自己装 Node / pnpm / Git。

## 管理员：怎么发版、怎么改配置

- 发版：docs/lanfu/release.md
- 部署与配置：docs/lanfu/admin-deployment.md
- Windows 打包细节与已知问题：docs/lanfu/windows-packaging.md

## 开发：本地构建与检查

    pnpm install
    pnpm tsgo:core && pnpm tsgo:ui && pnpm tsgo:extensions && pnpm tsgo:scripts   # 类型检查
    pnpm exec vitest run <测试文件>                                              # 定向测试
    pnpm build                                                                  # 构建 dist + Control UI

要求 Node 24.19.0 与 pnpm 12.4.0。

## 数据与隐私

- 所有会话、记忆与凭据都保存在本机用户目录（Linux 为 ~/.lanfu，Windows 为 %USERPROFILE%\.lanfu）。
- 卸载不会删除该目录；需要清除数据请手动删除。
- 除公司模型服务与员工自己配置的渠道外，产品不主动外连；自动更新默认关闭。

## 上游与许可

本产品基于 OpenClaw（MIT 许可）二次开发。上游代码的版权与许可声明保留在 LICENSE 与 THIRD_PARTY_NOTICES.md 中；LanFu 自身的品牌、界面文案、安装与发行体系由公司维护，且不向上游提交改动。
