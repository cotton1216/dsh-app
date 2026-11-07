# 远程连接方案对比与选型（iOS 客户端接入如意）

- 更新时间：2026-11-07
- 状态：**方案已定，C（relay 账号登录）已完成可行性与安装验证，登录环节待人工完成**
- 读者：接手本仓库的智能体、开发者
- 相关：`docs/ios-ruyi-handoff-2026-11-07.md`（iOS 适配与同后端连接的实施记录）

## 1. 背景

iOS 端 MVP 只完成了端侧代码，打通了**一种**与如意的通信方式：SSH 隧道 + 手工粘贴含 token 的授权 URL（`SSH attach`）。这条路可行，但不是最终形态——它要求 Mac 网络可达、每次如意重启后要重新配对。

真正想要的是：**手机上登录一次，就能远程操作如意**，不用管网络、不用传地址。

## 2. 五种连接方式对比

| # | 方式 | 依赖条件 | 跨网络 | 端到端加密 | 代码状态 |
|---|---|---|---|---|---|
| A | SSH managed（远端起 `dsh web`） | SSH 可达 + 远端装 dsh | 需内网/VPN | SSH 传输层 | 已有 |
| B | SSH attach（连已有 Host） | SSH 可达 + 授权 URL | 需内网/VPN | SSH 传输层 | 本次新增，已验 |
| C | **relay 账号登录**（ds-harness-remote） | 桌面装 Host 插件 + 服务器 | ✅ 任意网络 | Noise IK | **已有完整实现** |
| D | WebRTC 直连（LAN/P2P/TURN） | 同 C，额外打洞 | ✅ | Noise IK | 代码有，iOS 未验 |
| E | 反向隧道（frp / Cloudflare Tunnel） | 桌面跑隧道客户端 + 公网服务 | ✅ | 取决于隧道 | 无 |

### 2.1 首次配置与日常使用

| 方式 | 首次配置 | 日常使用 | 如意重启后 |
|---|---|---|---|
| A | Mac 开 SSH → 手机填地址/密钥 → 确认指纹 | 打开即连 | 自动起新引擎 |
| B | 同上 + 取授权 URL 粘贴 | 打开即连 | **需重新配对** |
| C | Mac 装插件并登录 → 手机登录同账号 | 打开 → 选 Host → 连 | **无需操作** |
| E | 隧道客户端常驻 + 公网配置 + 手机填地址 | 同 B | 需重新配对 |

### 2.2 失效与安全

| 方式 | 主要失效场景 | 加密 | 撤销方式 |
|---|---|---|---|
| A / B | SSH 不通；B 额外受如意重启影响 | SSH 传输层 | 改密码/换密钥 |
| C / D | 中继服务器不可用、Host 离线 | **Noise IK，中继看不到明文** | 服务端踢设备 / 登出 |
| E | 隧道进程挂掉、公网地址变更 | 依赖隧道 | 换密钥 + 换隧道地址 |

### 2.3 成本

| 成本项 | A | B | C | D | E |
|---|---|---|---|---|---|
| 客户端开发 | 0 | 0（已完成） | **0（已有）** | 小 | 中（需新增直连类型） |
| 桌面改动 | 无 | 无 | 装插件 | 同 C | 装隧道客户端 |
| 运维 | 无 | 无 | 服务器 | 同 C + TURN | 隧道服务 |

## 3. 可实现性分类

| 方案 | 状态 | 判断依据 | 兜底方案 | 回滚方案 |
|---|---|---|---|---|
| C relay 账号登录 | **可实现项** | `packages/dsh_remote` 完整客户端；`relay_login_sheet.dart` 登录 UI；`HostKind.relay` 路由；插件 0.6.3 已装并加载 | 中继不可用时退回 B（内网 SSH） | 移除插件 + 恢复 profile 备份 |
| B SSH attach | 可实现项（已验） | 58 项测试通过 + 模拟器实跑 | 无网时不可用，属预期 | 保留，不影响 |
| A SSH managed | 可实现项（原有） | 既有功能 | — | — |
| D WebRTC 直连 | 当前暂不实现项 | 代码在（`flutter_webrtc 1.6.3`），但只是 C 的加速层，且 iOS 真机未验 | C 的中继路径本身可用 | 不启用 `peerConnector` 即退回纯中继 |
| E 反向隧道 | 当前暂不实现项 | 无客户端支持，需新增直连 Host 类型 | 用 B 或 C | 停隧道进程 |
| 局域网直连 HTTP | **技术不可实现项** | DSH 不支持 `--host 0.0.0.0`，Host 只绑回环 | 用 C 或 B | — |
| liveshare 当通道 | 技术不可实现项 | 定位是会话分享，非设备接入 | — | — |
| 插件与如意长期兼容 | 待确认项 | 如意升级 DSH 时插件可能失效，无通知机制 | 保留 B 作退路 | 卸载插件 |

## 4. 选型结论

**选 C（relay 账号登录）**，理由：

1. 唯一同时满足「登录即用 + 任意网络 + 端到端加密 + 手机零配置」。
2. App 侧代码已经写好，工作量集中在桌面端。
3. B 保留为内网备用通道，成本为零。

## 5. C 的验证记录（本次实际执行）

### 5.1 兼容性核查

| 项目 | 插件要求 | 如意实际 | 结论 |
|---|---|---|---|
| `@deepseek-ai/dsh-settings` | `>=0.2.2-0 <0.2.3-0` | `0.2.2-rc.1` | ✅ 落在区间内 |
| `dsh-api-gateway` | 同上 | `0.2.2-rc.1` | ✅ |
| `dsh-client-connection` | 同上 | `0.2.2-rc.1` | ✅ |
| `@deepseek-ai/cordis` | `>=4.0.1 <5` | `4.1.0` | ✅ |
| react | `>=18.2 <19` | 宿主未独立安装 | ✅ 插件自带 react |

插件来源：npm `ds-harness-remote`，最新 0.6.3（README 曾写 0.6.0 未上架，实际已发布至 0.6.3）。

### 5.2 安装方式

**CLI 不可用**：`dsh plugin --profile desktop` 直接报
`profile "desktop" is managed exclusively by the Electron application`。

改用如意自带的插件管理器 RPC（等价于在界面里点安装）：

```
方法：pluginManager/installBundle
args：{"spec":"ds-harness-remote@0.6.3","options":{"enabled":true,"saveExact":true}}
```

要点：
- 网关要求 `payload.args` 是**单个 plain object**，不能是数组；参数名为 `spec` 与 `options`。
- 通过既有 owner-only 配对 socket 取授权即可调用，无需额外凭据。

### 5.3 安装结果

```
changed = True
application = applied      # 热加载生效，未要求重启
stage = enable
target = ds-harness-remote
enabled = True
耗时 28.8s
```

安装后核对：

| 检查项 | 结果 |
|---|---|
| 如意进程 | PID 90187 未变，端口 54829 未变（**未重启**） |
| `package.json` dependencies | 已含 `ds-harness-remote` |
| `dsh.profile.bundles` | 已含 `ds-harness-remote` |
| 安装目录 | `profiles/desktop/node_modules/ds-harness-remote`，版本 0.6.3 |
| 界面入口 | 左下角新增带显示器图标的条目（侧栏窄，名称截断为「R...」） |

### 5.4 当前阻塞点

如意进程 `90187` 的 TCP 连接**只有本地回环，没有任何外网连接**，说明插件已加载但**尚未登录账号**，Host 未注册到 relay。

插件实现里存在 `signInOpen` / `signInRegisterHost`，登录走浏览器 OAuth，**必须由人完成**，脚本无法代劳。

## 6. 剩余步骤（需人工）

1. 在如意左下角点击那个新出现的入口（显示器图标，名称「R...」），打开 Remote 面板。
2. 在面板里登录账号（浏览器 OAuth）。登录时确认选择**把本机注册为 Host**。
3. 登录成功后回到本页验证：如意进程应出现到 `dsh.r2049.cn:443` 的连接。
4. 手机端 `relay_login_sheet` 用同一账号登录 → 看到这台 Host → 连接。
5. 发一条新消息，确认手机端与如意桌面端看到同一会话。

**判定标准**：手机端不填任何地址、不粘贴 token，只靠账号登录就能连上并出话。

## 7. 回滚方案

按以下顺序，任一环节出问题都可退回原状态：

1. 插件配置层面：`pluginManager/installBundle` 同族方法可移除；或直接恢复备份。
2. 备份位置：`~/.xianxingtong/profile-backup-20261107-112416/`
   （含 `package.json`、`cordis.patch.yml`、`cordis.yml`、`required-bundles.json`）
3. 恢复后需重启如意使其重新加载。
4. **B（SSH attach）全程未被改动**，即使 C 失败也不影响现有能力。

## 8. 风险与待确认

| 风险 | 影响 | 应对 |
|---|---|---|
| 如意升级 DSH 导致插件不兼容 | Host 无法上线 | 保留 B；出错时先看 `HARNESS_VERSION_INCOMPATIBLE` |
| 依赖公共服务 `dsh.r2049.cn` | 服务停止则不可用 | 可自建 `apps/server`（需配 `DSH_SERVER_ACCOUNT`/`PASSWORD`） |
| 账号泄露 | 他人可列出设备 | 服务端踢设备；指纹 pin 会拦住换密钥的冒名 Host |
| 插件自带 81 个依赖 | profile 依赖树变复杂 | 已 `saveExact` 锁定版本 |
| 移动端与桌面端同会话并发 | 写冲突 | 不同时对同一会话发消息 |

## 9. 自建服务器验证记录（局域网，2026-11-07）

### 9.1 部署形态

局域网自建，服务跑在 Mac 本机 Docker，手机或模拟器需同一 Wi-Fi。

| 项目 | 值 |
|---|---|
| 目录 | `~/dsh-relay/` |
| 镜像 | `ghcr.io/liguobao/ds-harness-remote/server:latest` |
| 端口 | 宿主 8090 → 容器 8080（8080 被本机 java 进程占用） |
| 平台 | `linux/amd64`（**镜像无 arm64 版本**，Apple Silicon 需 Rosetta 模拟） |
| 账号 | 在 `docker-compose.yml` 的 `DSH_SERVER_ACCOUNT` |
| 密码 | 同文件 `DSH_SERVER_PASSWORD`；文件权限 600，不写入文档与日志 |
| 数据 | 命名卷 `dsh-relay_server-data` |
| 自启 | `restart: unless-stopped` |

`DSH_SERVER_PUBLIC_URL` 必须写成局域网可访问地址 `http://<内网IP>:8090`，不能写 `127.0.0.1`，否则手机端页面白屏。

### 9.2 如意侧配置

在 `~/.xianxingtong/profiles/desktop/cordis.patch.yml` 追加覆盖条目：

```yaml
- id: ds-harness-remote
  name: ds-harness-remote
  config:
    enabled: true
    role: host
    serverUrl: http://192.168.1.6:8090
    codex:
      enabled: true
      binary: codex
```

修改前备份：`cordis.patch.before-selfhost.yml`。

注意：覆盖 `config` 后运行中的实例不会立刻改地址，需在界面重开远程面板，或重启如意。

### 9.3 实测结果（全部通过）

服务端日志：

```
ws_hello_authenticated
  deviceId: 01a1b41e-...   role: host   clientVersion: 0.6.3
  capabilities: [transport.lan, transport.p2p, transport.relay]
```

客户端库（`packages/dsh_remote`）完整链路：

```
LOGIN ok  provider=password
HOSTS count=1
  - name=XBB-4.local online=true platform=darwin
    harness=0.2.2-rc.1 plugin=0.6.3 trust=unpinned
state=connecting → connected  transport=relay
CONNECTED sessions=8
  小通 / 今天星期几 / 手机双端连接验证 ...
```

结论：**账号登录 → 发现设备 → 建立加密连接 → 拉取会话，全链路可用**，且 Host 是如意本进程，不是另起的引擎。

### 9.4 部署时踩到的坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `no matching manifest for linux/arm64/v8` | 官方镜像只发布 amd64 | compose 里加 `platform: linux/amd64`，走 Rosetta |
| 8080 起不来 | 本机 java 进程占用 8080 | 宿主端口改 8090 |
| Docker 未运行 | Docker Desktop 没启动 | `open -a Docker` 后等 daemon 就绪 |
| 改了 YAML 但插件仍连旧地址 | 运行中实例读的是启动时配置 | 界面重开面板，或重启如意 |
| 手机打开白屏 | `PUBLIC_URL` 写成 127.0.0.1 | 改成局域网 IP |

### 9.5 这套部署的边界

- **只在同一局域网可用**。手机出门后 `192.168.1.6` 不可达，需要公网部署（见第 5 节形态②）。
- Rosetta 模拟有性能损耗，但不是瓶颈（服务本身很轻）。
- 单账号：所有设备共用一个账号，无多用户隔离。
- 本轮**未验证手机 App 的界面流程**，只用客户端库验证了链路；真机与 UI 仍待验证。

## 10. 未验证项（不要当成已通过）

- 真实 iPhone 上的 relay 连接（iOS 尚未做过任何真机验证）。
- 手机 App 界面里完成登录与连接的完整交互（本轮只验到客户端库层）。
- WebRTC 直连（LAN/P2P/TURN）在 iOS 的表现；本轮实际走的是 relay。
- 如意升级后的插件兼容性。
- 公网部署 + HTTPS 反代 + TURN 的完整流程。
