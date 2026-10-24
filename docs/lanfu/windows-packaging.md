# LanFu Windows 打包与安装（0.1.0 实操记录）

更新时间：2026-10-07。本文记录的是**已实际跑通**的打包流程与仍然存在的问题，供后续在 CI（Windows runner）上固化。

## 已验证的流程

1. **构建产物**：在 WSL 里执行 `pnpm build`（约 6 分钟），产出 `dist/`（约 310MB，含 Control UI 与全部内置插件）。
2. **物化 Windows 生产依赖**：在**工作区配置临时改成 Windows 目标**后执行 `pnpm --filter . deploy --prod --legacy <目标目录>`：
   ```yaml
   # pnpm-workspace.yaml（仅打包期间，随后必须还原）
   allowUnusedPatches: true
   supportedArchitectures:
     os:
       - win32
     cpu:
       - x64
   ```
   这样会拉取 win32 原生包（`@lancedb/lancedb-win32-x64-msvc`、`@openclaw/fs-safe-win32-x64-msvc`、`@lydell/node-pty-win32-x64`、`@trycua/cua-driver-win32-x64-msvc`、`@koromix/koffi-win32-x64` 等），产物体积约 590MB。
3. **随身 Node**：使用固定版本 `node-v24.19.0-win-x64`，解压后约 101MB。
4. **安装器**：Inno Setup 6 `ISCC.exe` 编译 `packaging/windows/LanFu.iss`，产出 `LanFu-Setup-x64.exe`（本次 149MB）。
5. **实装验证（本机 Windows）**：静默安装 `/VERYSILENT` 成功；安装到 `%LOCALAPPDATA%\Programs\LanFu`；首次运行写入 `%USERPROFILE%\.lanfu\lanfu.json`（gateway.mode=local、公司 vLLM provider、随机 token）；`runtime\node.exe app\openclaw.mjs gateway --port 18789` **可以启动并返回 HTTP 200**。

## 必须解决的问题（按优先级）

### 1. pnpm 布局与 Inno Setup 不兼容（阻断级）

- pnpm 的 `node_modules` 是「顶层链接 + `.pnpm` 实体」结构，本次共 **691 个目录链接**。
- Inno Setup 打包时会把这些链接**展开成真实目录**，安装后 `node_modules/execa` 变成实体目录，Node 便无法再从 `.pnpm` 里解析它的兄弟依赖，启动报 `Cannot find package 'is-plain-obj'`。
- 本次的临时修法：安装后用原始链接清单把安装目录里的实体目录重新替换成 **junction**（652/691 成功，之后网关正常）。
- **正式做法**：发布时直接产出**扁平 node_modules**（`nodeLinker: hoisted`，Windows 上原生安装）或改用 npm 安装，从根上消除链接。

### 2. Windows 路径长度（MAX_PATH）

- pnpm 的 `.pnpm` 目录名会把 peer 依赖编码进去，个别名字长达 116 字符，叠加后超过 260，`ISCC` 报「系统找不到指定的路径」。
- 本次的做法：把 22 个超长 `.pnpm` 目录改名成 `p1..p22` 并同步改写引用它们的 junction；再把暂存根目录缩短为 `D:\lb`（最长路径降到 196）。
- 正式做法：改用扁平布局后此问题自然消失；否则必须在 Windows CI 上启用长路径并确认工具链支持。

### 3. 服务注册需要管理员权限

- `post-install.ps1` 里的 `Register-ScheduledTask` 在非管理员会话下报 `Access is denied`（HRESULT 0x80070005），因此「登录自启」没有生效。
- 替代方案（无需管理员）：把快捷方式放进 `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup`，或写 `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`。

### 4. 内置插件包未完整物化

- `dist` 里引用了 108 个 `@openclaw/<plugin>` 名称，但 `extensions/*` 并不是带 `package.json` 的工作区包（`extensions/acpx` 等没有 package.json），因此 deploy 产物里没有它们。
- 本次实装验证中网关仍能启动（加载 14 个插件，WSL 参考实例为 20 个）。
- 正式做法：让打包流程显式产出这些插件包，或在构建期把插件解析改成就地路径。

## 复现命令（当前手工流程）

```bash
# 1) WSL：构建
pnpm build

# 2) WSL：临时切到 Windows 目标并 deploy（完成后立刻还原 pnpm-workspace.yaml）
pnpm --filter . deploy --prod --legacy /mnt/d/lb/app

# 3) Windows：解压 Node，编译安装器
ISCC.exe D:\lb\LanFu.iss

# 4) Windows：静默安装
LanFu-Setup-x64.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART
```

## 下一步建议

把上述流程固化到 GitHub Actions 的 `windows-latest` runner：

1. `pnpm install --prod --nodeLinker=hoisted`（或 npm）得到扁平依赖，彻底绕开链接与长路径问题；
2. 用 `actions/upload-artifact` 收集 `LanFu-Setup-x64.exe` 与 `SHA256SUMS.txt`；
3. 自启改用 Startup 目录 / HKCU Run，避免提权；
4. 在 runner 上跑一次「安装 → 启动 → HTTP 200 → 卸载」冒烟测试。
