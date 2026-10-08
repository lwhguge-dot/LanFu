# Windows 图标规范

## 尺寸（关键）

`packaging/windows/lanfu.ico` 必须包含 7 个尺寸：**16 / 24 / 32 / 48 / 64 / 128 / 256**。

历史问题：0.1.x 的 .ico 里**只有一个 16×16 的图**，Windows 桌面需要 256px 时只能把 16px 放大，
快捷方式图标因此糊成一团。这是"图标很糊"的唯一根因。

## 小尺寸简化

- **≤32px**：使用去掉发丝级线条的简化版（对 alpha 通道做形态学开运算，去掉细环与羽毛碎线）。
- **≥48px**：使用完整标志。

原因：完整标志的浅灰细环在 16～32px 会糊成"脏光晕"，反而看不清主体。

## 文件格式

`.ico` 内 **16～128 用 BMP 条目、256 用 PNG 条目**（标准做法，兼容性最好；全 PNG 内嵌在部分旧渲染路径下可能不显示）。

## 生成方式

从 `LanFu-品牌资产/png/lanfu-mark-1024.png` 生成，脚本：`scripts/lanfu/make-windows-ico.py`。

生成后写入三处：

1. `LanFu-品牌资产/favicon.ico`
2. `packaging/windows/lanfu.ico`（安装器与快捷方式用）
3. `ui/public/favicon.ico`（Control UI 网页用）

## 验证

在 Windows 上用 `System.Drawing.Icon` 实际渲染 16/32/48/256 并生成对比图（与资源管理器同一条加载路径），
不要只看源 PNG。预览图：`LanFu-品牌资产/预览-Windows实际渲染.png`。
