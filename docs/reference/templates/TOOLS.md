---
summary: "已停用的 TOOLS.md 工作区模板"
title: "TOOLS.md 已停用"
read_when:
  - 手动初始化工作区
---

# TOOLS.md 已停用

本地工具和环境备注现在写在 `AGENTS.md` 的 `## 工具` 一节里。工具的具体用法仍由技能文件定义。

运行 `lanfu doctor --fix` 可以归档工作区里已有的 `TOOLS.md`：定制内容会合并进 `AGENTS.md`，然后移除这个停用的文件。
