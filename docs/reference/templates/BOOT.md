---
summary: "BOOT.md 工作区模板"
title: "BOOT.md 模板"
read_when:
  - 添加 BOOT.md 启动清单
---

# BOOT.md

在这里写简短、明确的启动指令。内置的 `boot-md` 钩子会在网关每次启动时对每个工作区运行一次本文件（文件存在且非空白时）。多助手共享一个工作区只触发一次。

该钩子默认关闭，先启用：

```bash
lanfu hooks enable boot-md
```

此钩子会关闭常规的最终回复投递。如果清单项需要发消息，用消息工具并在每次调用中写明渠道和目标，然后回复静默令牌 `NO_REPLY`（大小写均可）。
