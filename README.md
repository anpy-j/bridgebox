# 桥坞 Bridgebox

跨端（iOS / Android / macOS / Windows / Linux）个人服务器管理客户端。

电脑或手机上运行，通过 **SSH** 管理远端 Linux：systemd 启停、Docker 容器与镜像、主机指标。服务器上 **不必再装 Agent、不必再开管理端口**。

## 它做什么

- 主机列表：地址、端口、用户；口令或私钥只进系统安全存储
- 指标：CPU、内存、Swap、根分区、负载
- systemd：列出服务，启动 / 停止 / 重启（名称经白名单校验）
- Docker：容器启停删除、镜像拉取与删除、日志尾部

## 它不做什么

- 不在仓库或安装包里附带任何 SSH 私钥、`.pem`、密码、Token
- 不把 Docker socket 或数据库端口映射到公网
- 不在服务器上常驻第二个管理网关

远端账号只要能执行 `systemctl`（或带 sudo）和 `docker` 即可。数据库请继续用本机隧道，不要从本客户端对公网暴露 3306 / 5432。

## 安全约定

1. 传输只走已有 SSH（默认 22），由安全组限制来源 IP。
2. 优先密钥登录；密钥由你在本机选择，内容写入 `flutter_secure_storage`（Keychain / Keystore / 凭据管理器），配置文件只存主机元数据。
3. 停服务、删容器、删镜像会二次确认。
4. 远端命令的服务名 / 容器名 / 镜像名必须通过本地白名单，禁止拼进 `sh -c`。
5. 建议用普通用户 + `docker` 组，不要默认 root。

## 生成本地工程（不要提交密钥）

本仓库只包含 Dart 源码。生成各端工程目录（不启动应用）：

```bash
cd /home/ijx/anpengyu/bridgebox
flutter create . --org com.anpengyu --project-name bridgebox \
  --platforms=android,ios,macos,windows,linux
```

`flutter create` 会保留现有 `lib/`。然后用你自己的 IDE 打开工程。按你的要求，初始化仓库时 **没有执行** `flutter run` / `flutter build`。

## 连接你自己的机器

1. 打开应用 → 添加主机
2. 填写 SSH 地址、端口、用户名
3. 选择「密码」或「私钥」：私钥用系统文件选择器导入，不要把 PEM 拷进项目目录
4. 进入该主机即可看指标、管服务和 Docker

腾讯云安全组：入站 22 只放行你的 IP；不要为了客户端把 22 改成 `0.0.0.0/0`。

## 技术栈

| 层 | 选择 |
|---|---|
| 跨端 UI | Flutter（手机 + 桌面同一套） |
| 远端通道 | SSH（`dartssh2`），无 Agent |
| 密钥存放 | `flutter_secure_storage` |
| 主机列表 | `shared_preferences`（不含密钥） |

## 许可

MIT
