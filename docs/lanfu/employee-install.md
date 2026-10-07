# LanFu 员工安装说明

LanFu 是公司提供的本地 AI 助手。装好之后，用浏览器打开本机界面就能用，也可以通过公司配置的微信渠道找它。

## Windows

1. 用公司授权的 GitHub 账号登录，打开公司私有仓库的 Releases 页面。
2. 下载 LanFu-Setup-x64.exe 和 SHA256SUMS.txt。
3. （建议）校验下载文件：在下载目录打开 PowerShell，执行

       Get-FileHash .\LanFu-Setup-x64.exe -Algorithm SHA256

   结果应与 SHA256SUMS.txt 中的值一致。

4. 双击 LanFu-Setup-x64.exe，按提示完成安装。安装过程不需要管理员权限，也不会要求你另外安装 Node.js。
5. 安装完成后会自动注册登录自启并打开一次界面。之后可以随时双击桌面上的 LanFu 快捷方式。

### 访问公司模型需要什么

公司模型服务目前通过 Tailscale 访问（100.116.120.40:8000）。所以：

- 请确认电脑上的 Tailscale 已登录并且在线；
- 如果不确定，可以在浏览器里试一下能否打开界面并正常对话，失败时把界面上的报错截图发给 IT。

### 数据放在哪

- 配置与会话数据：%USERPROFILE%\.lanfu
- 程序本体：%LOCALAPPDATA%\Programs\LanFu
- 卸载不会删除 .lanfu；要彻底清除请手动删除该目录。

### 卸载

设置 → 应用 → 已安装的应用 → LanFu → 卸载；或运行安装目录下的 unins000.exe。

## Linux（Ubuntu）

    sudo dpkg -i lanfu_0.1.0_amd64.deb
    systemctl --user enable --now lanfu-gateway.service

安装后在浏览器打开 http://127.0.0.1:18789/。

## 遇到问题

把这两样发给 IT：

1. 界面上的报错截图；
2. 网关日志（Windows：%USERPROFILE%\.lanfu\logs）。
