# LanFu 员工安装说明

LanFu 是公司提供的本地 AI 助手。员工通过 GitHub 私有仓库的 Release 下载 Windows 安装器，安装器自带固定 Node.js，不要求额外安装 Node.js、pnpm 或 Git。

## Windows

1. 登录公司授权的 GitHub 账号。
2. 在 GitHub Releases 下载 LanFu-Setup-x64.exe。
3. 双击安装器并按提示完成安装。
4. 首次启动时按管理员提供的模型地址完成配置。
5. 如果电脑以前使用过 OpenClaw，安装器会先备份并迁移旧数据到 .lanfu；旧 .openclaw 目录不会自动删除。

## 重要说明

- 不要删除 .lanfu，其中包含会话、配置和本地 Agent 数据。
- 不要把 API 密钥发送到聊天、提交到 Git 或写入截图。
- 升级前关闭正在运行的 LanFu；安装器会保留可回滚版本。
- 出现问题时保留安装日志和 Gateway 日志，提交给公司 IT。
