# LanFu 发布说明

## 版本号规则

产品有两个版本号，不要混用：

| 用途         | 值       | 位置                                                                          |
| ------------ | -------- | ----------------------------------------------------------------------------- |
| 对外产品版本 | 0.1.0    | package.json 的 lanfu.productVersion；CLI、关于页、安装包、Release 标签都用它 |
| 内部上游基线 | 2026.9.6 | package.json 的 version，必须保持与上游同族                                   |

为什么不能把内部版本改成 0.1.0：它驱动配置的时间戳守卫、插件版本区间与更新逻辑。实测改成 0.1.0 后网关会拒绝启动：Refusing to start the gateway service because this LanFu binary (0.1.0) is older than the config last written by LanFu 2026.9.6。

## 发布流程

1. 发版方式是**推 tag**（推荐）：
   ```bash
   git tag lanfu-v0.1.1 && git push github lanfu-v0.1.1
   ```
   版本号从 tag 名推导，安装器、deb、Release 全用它，保证一致。也可以到 Actions → LanFu Release → Run workflow 手动填 version。
2. 流水线分两段：`build` 任务产出 dist 并打包成 artifact；`windows-exe` / `linux-deb` 从**全新 checkout**开始，切到扁平布局装生产依赖（避免在已有 node_modules 上原地转换），下载 dist、捆绑固定版本 Node 24.19.0、用 Inno Setup 出 LanFu-Setup-x64.exe，然后**在 runner 上静默安装并等待安装器自己启动的网关返回 HTTP 200**——这一步不通过就不出包。
3. Linux 任务同样产出 lanfu_<version>_amd64.deb。
4. 创建 **draft** Release（标签 lanfu-v<version>，含 exe / deb / SHA256SUMS.txt），在 Releases 页面点 **Publish release** 后员工才能下载。

## 发布产物

- LanFu-Setup-x64.exe（Windows 安装器，自带 Node，员工无需安装任何运行时）
- lanfu_<version>_amd64.deb（Ubuntu）
- SHA256SUMS.txt
- RELEASE_NOTES.md

## 为什么用扁平依赖布局

发布流水线刻意使用 --config.nodeLinker=hoisted。原因见 windows-packaging.md：pnpm 默认的链接式布局会被 Inno Setup 展开成实体目录，导致运行时解析不到兄弟依赖；同时 .pnpm 目录名会超出 Windows 的 260 字符路径上限。

## 已知问题

见 windows-packaging.md 的必须解决问题一节。当前 Windows 安装包已经能做到装得上、起得来、界面能开，但正式对外前仍需处理：

1. 内置插件的完整物化（实测网关加载 14 个插件，开发机参考为 20 个）；
2. 登录自启改用 Startup 目录或 HKCU Run（当前 Register-ScheduledTask 在非管理员会话下会被拒绝）。

## 测试现状

- 类型检查：tsgo:core / tsgo:ui / tsgo:extensions / tsgo:scripts 全部通过。
- 全量测试套件（上游 10000+ 用例）不作为发布门禁：在开发机上一次全量运行会把 WSL 打崩，且大量用例属于上游专用夹具。CI 只跑与产品边界相关的定向用例（8 个文件 / 102 个用例，本机实测全绿）。
- `src/cli/program/error-output.test.ts` **已被排除**：该文件在依赖树里存在多份 commander（7.2.0 / 8.3.0 / 15.0.0），`instanceof CommanderError` 会因为模块副本不同而失败，并且失败数量在每次运行间波动（实测 10 / 16 / 18 / 26 个），属于上游测试的环境性问题；用基线提交的文件跑同样失败，不是 LanFu 改动引入的。
