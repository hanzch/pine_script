# Pine Script 🚀

**Pine Script** 是一个用于系统部署的公共脚本库，旨在简化部署流程、提高效率并确保系统稳定性。项目名称灵感来自 **松树（Pine）**，象征坚韧、长青和可靠，正如这些脚本在系统部署中的重要作用。

---

## 🌟 项目特点

- **高效部署**：提供一键式部署脚本，减少手动操作，提升部署速度。
- **模块化设计**：脚本按功能模块划分，易于扩展和维护。
- ~~**开箱即用**：提供详细的文档和示例，快速上手。~~ 待确认
- ~~**稳定可靠**：经过严格测试，确保脚本的稳定性和安全性。~~ 待确认

---

## 🛠️ 脚本列表

以下是当前支持的脚本列表：

| 脚本名称            | 功能描述                     |
|-----------------|--------------------------|
| `setup_raid.sh` | 设置raid1。                 |
| `setup_secure_user.sh`     | 添加基于证书的新用户并更新SSH只允许证书登录。 |


---

## 🚀 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/hanzch/pine_script.git
cd pine_script/lib
```

### 2. 运行脚本

根据需要运行对应的脚本。例如，运行部署脚本：

```bash
./deploy.sh
```

### 3. 查看日志

脚本执行后，日志会保存在 `logs/` 目录下，方便排查问题。

---

## 📚 文档

~~- [脚本使用指南](./docs/USAGE.md)~~
~~- [常见问题解答](./docs/FAQ.md)~~
~~- [贡献指南](./docs/CONTRIBUTING.md)~~
待添加

---

## 🤝 如何贡献

我们欢迎任何形式的贡献！~~请阅读 [贡献指南](./docs/CONTRIBUTING.md) 了解如何参与项目。~~

1. Fork 项目仓库。
2. 创建新的分支（`git checkout -b feature/your-feature`）。
3. 提交更改（`git commit -m 'Add some feature'`）。
4. 推送分支（`git push origin feature/your-feature`）。
5. 提交 Pull Request。

---

## 📜 许可证

本项目采用 [MIT 许可证](./LICENSE)，请自由使用和修改。

---

## 🌲 为什么叫 Pine Script？

松树（Pine）象征坚韧、长青和可靠，正如这些脚本在系统部署中的重要作用。我们希望这个项目能像松树一样，成为你系统部署中的坚实后盾。

---

**Happy Deploying!** 🎉