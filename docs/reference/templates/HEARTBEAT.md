---
summary: "已停用的 HEARTBEAT.md 工作区文件迁移说明"
title: "HEARTBEAT.md 已停用"
read_when:
  - 迁移仍带有 HEARTBEAT.md 的旧工作区
---

# HEARTBEAT.md 已停用

LanFu 不再在新工作区创建 `HEARTBEAT.md`，运行时也不再读取它。心跳指令现在存放在共享状态数据库中由系统管理的监控任务备注里。

用 `lanfu automations list --all` 找到监控任务的 jobId 后管理它的备注：

```bash
lanfu automations scratch <jobId>
lanfu automations scratch <jobId> --set "..."
lanfu automations scratch <jobId> --file notes.md
lanfu automations scratch <jobId> --unset
```

如果旧工作区里还有 `HEARTBEAT.md`，运行 `lanfu doctor --fix`：doctor 会把它的指令导入监控任务备注、把有效的旧式 `tasks:` 条目转成定时任务、把原文件归档到状态目录，然后从工作区移除。
