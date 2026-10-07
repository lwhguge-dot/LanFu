# LanFu 发布说明

## Release 资产

首版目标资产：

- LanFu-Setup-x64.exe
- lanfu_0.1.0_amd64.deb
- SHA256SUMS.txt
- RELEASE_NOTES.md

MSI 不阻塞 0.1.0，作为后续企业批量部署包。

## 发布门槛

- Windows 安装器携带固定 Node.js。
- Linux DEB 可安装、启动和卸载。
- .openclaw 到 .lanfu 迁移可回滚。
- 构建产物不包含官方在线文档、更新或市场依赖。
- Release 资产与 SHA-256 清单一致。
- 不把用户数据、凭据、日志或私钥提交到仓库。
