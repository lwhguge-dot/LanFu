# LanFu 管理员手册（内部）

> 适用版本：0.4.28 及以上。员工侧安装/使用见 `docs/lanfu/employee-install.md`（如有更新以本文为准）。

## 1. 安装

**交互安装**：双击 `LanFu-Setup-x64.exe`，按向导完成（安装器自带 Node、网关、桌面端，无需另装 Node/pnpm/Git）。

**静默安装（批量/远程）**：

```powershell
LanFu-Setup-x64.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /NOCANCEL /LOG=%TEMP%\lanfu-setup.log
```

- 安装位置：
  - 桌面端：`%LOCALAPPDATA%\LanFu\`（LanFu.exe）
  - 网关运行时：`%LOCALAPPDATA%\Programs\LanFu\`（app/、runtime/、lanfu.cmd、ensure-gateway.ps1、approve-pairing.ps1）
  - 用户数据：`%USERPROFILE%\.lanfu\`（lanfu.json、agents/main、state/openclaw.sqlite、workspace；0.4.33 起配置文件由 openclaw.json 更名为 lanfu.json，老文件在网关首次启动时自动改名迁移）
- 首次启动：网关通常 **2 分钟内**就绪（安装后首次 2–4 分钟，由 240 秒窗口兜底），随后应用自动连接、身份与配对自动完成。
- 未签名安装包可能触发 SmartScreen：选「更多信息 → 仍要运行」。

## 2. 升级

- 应用内更新：设置 → 检查更新 → 下载并安装；更新器会**校验安装包大小与 SHA256**，不匹配会删除下载并提示手动安装，不会半装。
- 升级自动清理旧 `dist` 缓存与旧 Node 工具链，安装目录不会随更新膨胀。
- 手动升级：从 GitHub Release 下载最新 `LanFu-Setup-x64.exe`，静默参数同上覆盖安装即可（会保留用户数据）。
- 更新失败排查：
  - 日志：`%LOCALAPPDATA%\LanFu\lanfu-tray.log`（搜索 `Verifying downloaded installer integrity` / `Integrity check failed`；0.4.30 及之前版本文件名为 `openclaw-tray.log`）；
  - 网络受限时可用代理/手动下载；
  - 完整性失败时按提示从 Release 页手动下载安装。

## 3. 版本与文件校验

- 桌面端版本：右键 `%LOCALAPPDATA%\LanFu\LanFu.exe` → 属性 → 详细信息，或设置页「版本」；
- 网关 CLI：`%LOCALAPPDATA%\Programs\LanFu\lanfu.cmd --help` 顶部显示版本；
- 安装包校验：GitHub Release 页的 `SHA256SUMS.txt`：
  ```powershell
  Get-FileHash .\LanFu-Setup-x64.exe -Algorithm SHA256
  ```

## 4. 数据备份 / 恢复

- 备份：退出 LanFu（托盘 → 退出），停止网关（如 `lanfu.cmd gateway stop` 或结束对应 node.exe），复制整个 `%USERPROFILE%\.lanfu` 目录；
- 恢复：退出应用后，用备份替换 `.lanfu` 目录，再启动应用（身份/配对/记忆/会话都在其中）；
- 升级/重装不会删除 `.lanfu`；卸载时按卸载器提示选择是否保留本地网关数据。

## 5. 日志与诊断

| 文件                                                 | 用途                         |
| ---------------------------------------------------- | ---------------------------- |
| `%LOCALAPPDATA%\LanFu\lanfu-tray.log`                | 桌面端（更新/连接/UI）主日志 |
| `%TEMP%\lanfu-gateway-watchdog.log`                  | 网关启动/重试/就绪记录       |
| `%TEMP%\lanfu-gateway-stdout.log` / `stderr.log`     | 网关进程输出                 |
| `%TEMP%\lanfu-pairing.log`                           | 配对与身份自愈               |
| `%TEMP%\lanfu-post-install.log` / `lanfu-setup*.log` | 安装收尾/安装器日志          |

- 一键诊断：设置 → 诊断 → 复制诊断包（只读、会脱敏）；也可打开诊断文件夹。

## 6. 常见问题

| 现象                   | 处理                                                            |
| ---------------------- | --------------------------------------------------------------- |
| 打开后一直「未连接」   | 等 2–4 分钟；查 watchdog 日志；必要时运行 `ensure-gateway.ps1`  |
| 更新时报 rate limit    | 不应再出现（更新检查已用内嵌只读 token）；若出现，检查网络/代理 |
| 更新下载极慢/失败      | 网络问题；可手动下载安装包覆盖安装                              |
| 安装后身份不是「小蓝」 | 运行 `approve-pairing.ps1 -TimeoutSeconds 300`（安装目录下）    |
| 卸载后想彻底清数据     | 手动删除 `%USERPROFILE%\.lanfu`（谨慎，记忆/会话会丢）          |

## 7. 安全与凭据

- 安装包未做代码签名（当前决定）；只从公司 GitHub Release 分发。
- 更新检查使用构建时注入的**只读** GitHub token；如需轮换：在 GitHub 生成只读 fine-grained PAT（仅本仓库 contents: read），更新仓库 Actions secret `LANFU_UPDATE_TOKEN`，再发一版即可（旧版本内嵌旧 token，需升级后生效）。
- 不要把 `.lanfu\lanfu.json`、日志或诊断包随意外发（可能含会话/令牌信息，诊断导出会脱敏但请复核）。

## 8. 发布（管理员/维护者）

- 每次发版必须写 `docs/lanfu/releases/<version>.md`（简短、只写本版变更）；缺失时流水线在 build 阶段直接失败。
- 打 tag `vX.Y.Z` 触发发布；GitHub Actions 产出 Windows 安装器/Linux deb/SHA256SUMS；
- 发布 smoke 会做干净安装 + 重复安装校验（dist 不增长、网关就绪）；
- 发版后只保留最新安装包归档，历史版本可从 Release 重新下载。
