# 远程连接方案对比与选型（iOS 客户端接入如意）

- 更新时间：2026-11-07
- 状态：**C（relay 账号登录）已端到端跑通**：如意作为 Host 上线、iOS 客户端登录即连、公网 IP + HTTPS 中继已部署（§11）。未完成：真实 iPhone 真机验收、多账号（当前单账号，见 §16）、账号适配 IAM（§13）、App 默认地址固化（§13.2）。
- 读者：接手本仓库的智能体、开发者
- 相关：`docs/ios-ruyi-handoff-2026-11-07.md`（iOS 适配与同后端连接的实施记录）

## 0. 当前状态总览（2026-11-07 14:00）

按「已验证 / 部分 / 未做」三档区分，**避免把计划当成已完成**。

### 0.1 已完成并实测

| 事项 | 证据 | 出处 |
|---|---|---|
| 选型定为 C（relay 账号登录） | 五种方式对比 + 可实现性分类 | §2 §4 |
| 如意装 `ds-harness-remote` 0.6.3 并热加载 | `application=applied`，PID/端口未变 | §5 |
| 局域网自建 relay 跑通 | 登录→发现设备→连接→会话列表 | §9 |
| 公网 IP 的 Let's Encrypt 证书 | `SAN=IP:118.196.18.181`，6 天，自动续期已演练 | §10 |
| Nginx 443 反代 + WebSocket 升级 | `/ws/v1/connect` 返回 101 | §10.4 §11.1 |
| 公网中继部署 | 容器只绑 `127.0.0.1:18080`，对外只有 443 | §11.1 |
| 如意作为 Host 上线 | `ws_hello_authenticated role=host plugin=0.6.3` | §11.3 |
| 公网端到端回合 | 客户端库登录→连接→9~10 会话→发消息收到「中继连通」 | §11.3 |
| iOS 模拟器登录即连 | `signedIn=true online=1 listed=true`，真实表单集成测试 | §11.3 |
| 登录页循环依赖缺陷 | 已修，37 项 relay 测试通过 | 提交 `993f075` |
| 首次拉设备列表偶发失败 | 自动重试两次 | 提交 `dd80770` |
| 状态持久化目录 | 改挂命名卷到 `/data`（原先落在匿名卷） | §11.5 |

### 0.2 部分完成

| 事项 | 现状 | 缺口 |
|---|---|---|
| 账号体系 | 自建中继的单账号（`DSH_SERVER_ACCOUNT`） | 不支持一人一号，见 §16 |
| 地址配置 | 手机端可填自定义地址，服务器地址已预置 | App 默认值仍指向 `dsh.r2049.cn`（§13.2） |
| WebRTC | 客户端库有代码 | 未启用 STUN/TURN，实际只走 relay |
| 证书运维 | 6 天证书 + cron 续期 + reload 钩子 | 只做过 `--dry-run`，尚未观察一次真实自动续期 |

### 0.3 尚未开始

- 真实 iPhone 真机验收（模拟器之外的一次完整验收）。
- 多账号 / 组织隔离（§16）。
- 接公司 IAM（§13/§15），硬阻塞是 IAM 未提供 token 校验接口。
- 审计日志、设备吊销面板、监控告警、备份策略。

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

## 10. 公网服务器 IP + HTTPS 实施记录（2026-11-07）

目标服务器：`118.196.18.181`（Ubuntu 24.04 / x86_64，Docker 29.1.3，Nginx 1.24）。
该机已有在跑的业务站点 `vastudio.thchengtay.com`，本实施**未改动**其配置与证书。

### 10.1 为什么可以用 IP 而不买域名

Let's Encrypt 自 2026-01 起正式签发 IP 证书（IPv4/IPv6），但有两个硬约束：

- **必须是 shortlived 配置档，有效期 160 小时（约 6 天）**，续期必须全自动。
- 验证只支持 HTTP-01 / TLS-ALPN-01，且必须打到该 IP 的 80 或 443。

客户端要求 Certbot ≥ 5.4（`--ip-address` 自 5.3 起，webroot 支持自 5.4 起）。
服务器自带的 2.9.0 不满足，且 `python3.12-venv` 未安装，因此采用 **pip --target 隔离安装**：

```bash
mkdir -p /root/.certbot-ip
python3 -m pip install --index-url https://pypi.org/simple --target /root/.certbot-ip "certbot==5.9.0"
```

注意：该机 pip 默认指向内网镜像，镜像里只有 5.2.2，必须显式 `--index-url https://pypi.org/simple`。

### 10.2 签发（与系统证书完全隔离）

```bash
export PYTHONPATH=/root/.certbot-ip
B=/root/.certbot-ip/bin/certbot
CFG="--config-dir /root/.certbot-ip/config --work-dir /root/.certbot-ip/work --logs-dir /root/.certbot-ip/logs"

# 先用 staging 验证
$B certonly --staging --preferred-profile shortlived --webroot   --webroot-path /var/www/certbot --ip-address 118.196.18.181   --non-interactive --agree-tos --register-unsafely-without-email $CFG

# 正式签发（已有同标识证书时需先 delete，否则报 "not yet due for renewal"）
$B delete --cert-name 118.196.18.181 --non-interactive $CFG
$B certonly --preferred-profile shortlived --webroot   --webroot-path /var/www/certbot --ip-address 118.196.18.181   --non-interactive --agree-tos --register-unsafely-without-email $CFG
```

结果：`SAN = IP Address:118.196.18.181`，签发者 `Let's Encrypt YE1`，链 4 段，`openssl verify` 通过。
证书落在 `/root/.certbot-ip/config/live/118.196.18.181/`，**未触碰 `/etc/letsencrypt`**。

ACME 验证复用现有站点的 80 端口规则（`/.well-known/acme-challenge/` → `/var/www/certbot`），**无需改 Nginx**。

### 10.3 自动续期

6 天证书必须高频续期，已配置：

```text
/etc/cron.d/certbot-ip      每天 03:17 / 15:17 执行 renew
/root/.certbot-ip/deploy-hook.sh   先 nginx -t 再 systemctl reload nginx
```

`certbot renew --dry-run --run-deploy-hooks` 演练通过，钩子实际执行并写入
`/root/.certbot-ip/deploy.log`。

### 10.4 Nginx 挂载

新增 `sites-available/dsh-remote-ip.conf`，软链为
`sites-enabled/zz-dsh-remote-ip.conf`（**zz- 前缀保证排在现有站点之后**）。

关键坑：

1. `nginx.conf` 里 `conf.d/*.conf` **先于** `sites-enabled/*` 加载，配置放 conf.d 会抢走默认站点。
2. **客户端访问纯 IP 时不发送 SNI**，Nginx 只能落到 `default_server`。因此 IP 站点必须显式
   `listen 443 ssl http2 default_server;`，否则永远返回域名站的证书，报
   `no alternative certificate subject name matches target ipv4 address`。
3. 域名站靠 `server_name` 匹配 SNI，**不受** default_server 影响。

实测：

| 目标 | 结果 |
|---|---|
| `https://118.196.18.181/healthz` | 200，`verify=0`，返回 `ok` |
| `https://vastudio.thchengtay.com/` | 200，`verify=0`，证书仍是原生产证书（至 2027-01-04） |

### 10.5 该机的宝塔（BT Panel）评估

结论：**不建议在本机直接安装**。

- 系统与资源满足（Ubuntu 24.04、31G 内存、24G 空闲盘）。
- 但宝塔官方要求「服务器上未安装任何 Web 环境，为纯净系统」。本机已有 apt 版 Nginx 在服务
  真实业务站点，另有 PostgreSQL、Redis 与 3 个 Docker 容器，80/443 已被占用。
- 宝塔会安装自己的 `/www` 与 Nginx 并接管 80/443，有搞挂现有站点的实质风险。

若确实要用宝塔，应另开一台干净服务器，或先做快照与完整备份并接受接管现有 Nginx 的代价。

### 10.6 尚未完成

- 中继服务本体尚未部署；当前 `https://118.196.18.181` 只返回占位响应。
- 未配置 WebSocket 反代（`/ws/v1/connect`，idle timeout 需 > 75 秒）。
- 如意与手机端仍指向家中局域网中继 `192.168.1.6:8090`。

## 11. 公网中继部署与双端验证（2026-11-07）

### 13.1 部署形态

服务器 `118.196.18.181`，中继容器**只绑回环**，由现有 Nginx 的 443 对外：

| 位置 | 端口 | 说明 |
|---|---|---|
| 容器 `dsh-relay-server-1` | `127.0.0.1:18080` → 容器 `8080` | 不直接对外 |
| Nginx | `443`（IP 站点 `default_server`） | 反代到 `18080`，含 WebSocket 升级 |
| Nginx | `80` | 仍是原有域名站点 + ACME 验证 |

对外地址：`https://118.196.18.181`（**不写端口**）。填 `:80` 会打到原有业务站点，填 `:18080` 只有服务器本机可达。

部署文件在 `/root/dsh-relay/`：

```yaml
services:
  server:
    image: ghcr.io/liguobao/ds-harness-remote/server:latest
    restart: unless-stopped
    ports: ["127.0.0.1:18080:8080"]
    environment:
      DSH_SERVER_ACCOUNT: ${DSH_SERVER_ACCOUNT}
      DSH_SERVER_PASSWORD: ${DSH_SERVER_PASSWORD}
      DSH_SERVER_PUBLIC_URL: ${DSH_SERVER_PUBLIC_URL}   # https://118.196.18.181
      DSH_SERVER_HOST: "0.0.0.0"
    volumes: [relay-data:/app/data]
```

Nginx 反代要点：

```nginx
location / {
    proxy_pass http://127.0.0.1:18080;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection $dsh_relay_upgrade;   # map: upgrade / close
    proxy_read_timeout 3600s;    # 控制通道空闲上限是 75 秒，必须远大于它
    proxy_send_timeout 3600s;
    proxy_buffering off;
}
```

### 13.2 部署时踩到的坑

| 现象 | 原因 | 处理 |
|---|---|---|
| `docker pull ghcr.io/...` 卡住 8 分钟无进展 | 该机直连 ghcr 极慢 | 用 `ghcr.nju.edu.cn` 镜像源拉取（10 秒），再 `docker tag` 打回原名 |
| WebSocket 握手测出 404 | 用 HTTP/2 发 `Upgrade` 头无意义 | 必须用 `curl --http1.1` 测；服务端本身正常 |
| 容器起了但外网打不开 | 容器只绑 `127.0.0.1` | 这是刻意的，对外由 Nginx 443 承担 |

### 13.3 双端实测结果

服务端日志（如意上线）：

```json
{"event":"ws_hello_authenticated","meta":{"role":"host","clientVersion":"0.6.3",
 "capabilities":["transport.lan","transport.p2p","transport.relay"]}}
```

客户端库走公网中继的完整回合：

```
LOGIN ok provider=password
HOSTS count=1  XBB-4.local online=true harness=0.2.2-rc.1 plugin=0.6.3
state=connecting → connected transport=relay
CONNECTED sessions=9
REPLY len=4 text=中继连通        ← 真实模型回复
PROMPT_OK
```

iOS 模拟器（原生界面，非测试入口）：

```
RELAY_LOGIN: signedIn=true online=1 listed=true names=XBB-4.local
All tests passed!
```

即：**如意作为 Host 上线 → 手机登录 → 发现设备 → 走 relay 建立加密连接 → 拉会话 → 发消息收到回复**，全链路在公网 IP + HTTPS 下成立。

### 13.4 一个间歇性缺陷（尚未根治）

三次 iOS 登录验证中**有一次**出现「没能获取主机列表」，同一时刻 `signedIn` 也变成 `false`。Nginx 访问日志对应：

```
GET /api/v1/devices/01a1b47d-...  401
POST /api/v1/auth/refresh         401
```

即设备详情请求 401，随后刷新令牌也 401，客户端据此判定为登出。属于令牌刷新相关的偶发失败，不是网络不通（同一轮里 `POST /auth/login` 和 `/devices` 都是 200）。

已做的缓解：`RelayAccountController.build()` 首次拉列表失败时**自动重试两次**（0.5s / 1s 退避），避免首次请求抖动直接显示重试卡片。缓解后连续运行 2 次中仍有 1 次失败，说明重试没覆盖到 `401 → 登出` 这条路径。

待办与判断依据：

- 优先怀疑 iOS 钥匙串**跨重装保留旧凭证**（集成测试每次重装 App，钥匙串不清），旧 refresh token 已被轮换 → 401。可用 `xcrun simctl keychain reset` 验证。
- 若排除旧凭证，则查 `dsh_remote` 的单飞刷新是否覆盖 App 内多个 `RemoteAccount` 实例（单实例内有 `_refreshing` 保护，跨实例没有）。

日志里另有一类 404（`/api/v1/auth/oauth/providers`、`/oauth/status`、`/oauth/github/status`）：App 探测的服务端能力，这台自建服务器未实现该路径，不影响密码登录，属正常降级。

### 11.5 状态持久化修复（同日晚）

镜像自身声明了 `VOLUME /data`，并且默认 `DSH_SERVER_DATA_FILE=/data/state.json`；
但 compose 最初把卷挂在 `/app/data`，于是：

- `/app/data` 是空的（白挂一个卷）；
- 真正的 `state.json` 落在 Docker 为 `/data` 自动创建的**匿名卷**里。

匿名卷不会被 compose 复用逻辑管理，`docker system prune --volumes` 或清理机器时会**静默删除设备凭据**，所有设备都要重新登录。

已改为命名卷挂到正确路径，并把现有 `state.json` 迁进去：

```yaml
volumes:
  - relay-data:/data     # 不是 /app/data
```

迁移后核对：`/data/state.json` 在命名卷中、属主 `node`，如意用原 deviceId 自动重连，登录后仍能看到 10 个会话。

## 12. 未验证项（不要当成已通过）

- 真实 iPhone 上的 relay 连接（iOS 尚未做过任何真机验证）。
- 手机 App 界面里完成登录与连接的完整交互（本轮只验到客户端库层）。
- WebRTC 直连（LAN/P2P/TURN）在 iOS 的表现；本轮实际走的是 relay。
- 如意升级后的插件兼容性。
- 公网部署 + HTTPS 反代 + TURN 的完整流程。

## 13. 下一步（2026-11-07 记录，未开始实现）

远程通道在链路上已跑通，但**账号和地址两件事还是临时的**，需要收口成正式形态。以下为待办，不含已完成工作。

### 13.1 待办 A：账号适配 IAM

**现状问题**：当前用的是 ds-harness-remote 自带的账号体系，与公司/项目其他系统不互通。

| 项 | 现状 |
|---|---|
| 登录提供方 | ds-harness-remote 自己的 provider 列表（`password` / `github` / `zhihu` / `google`），由 `server_api.oauthProviders()` 动态返回 |
| 凭据 | 各 Server 独立一套账号，`DSH_SERVER_ACCOUNT` / `DSH_SERVER_PASSWORD`；**每个 server 各自登录** |
| 客户端存的是 | `deviceToken` + `refreshToken`（`RemoteAccount` + `secret_store`），绑定 `serverUrl.origin` 的 hash 作用域 |
| 与 IAM 的关系 | **无**，目前完全是另一套身份 |

**目标**：登录走 IAM，一套账号通用；不再维护独立的中继账号。

#### 11.1.1 登录方式要求（硬性）

适配 IAM 之后，客户端必须**同时**保留下面三种入口，不能只留一种：

| 方式 | 要求 | 现状 |
|---|---|---|
| **扫码登录** | App 内展示二维码供其他已登录设备扫；或 App 扫网页端的码完成授权 | ⚠️ 半成品：库层有 QR 会话（`RemoteAccount.startLogin` → `api.startQrLogin`，轮询 `scanUrl`），但 **App 只是把该链接丢给浏览器打开**（`_Waiting`），界面上没有二维码，扫码动作发生在浏览器里 |
| **账号密码登录** | App 内直接输入账号 + 密码，不跳浏览器 | ⚠️ 只在「自建服务器」高级选项（`SelfHostedLoginSheet`）里有，且强制先填服务器地址；正式入口没有 |
| 浏览器 OAuth 兜底 | IAM 若支持第三方身份，仍可作为补充 | ✅ 现有主路径（`remote_browser_sign_in`） |

**扫码登录的具体形态需要定**——两种都叫"扫码"，实现和适用场景完全不同：

| 形态 | 谁显示码 | 谁扫 | 适用场景 |
|---|---|---|---|
| **A. App 显示码** | 手机 App | 另一台已登录设备 | 多设备加登、换手机时确认身份 |
| **B. App 扫码** | 桌面端（如意远程面板）或网页 | 手机 App 相机 | **本项目的真实场景**：手机连自己的电脑 |

**倾向**：单独实现 B 需要新增相机权限与二维码解析依赖（现有依赖里没有扫码组件），成本不低；而 **A3 内嵌 IAM 登录页天然覆盖 B**——IAM 登录页里本来就有"手机扫页面上的码"这条路，客户端不用碰相机。所以形态选择应跟路径选择一起定，不要先拆开做。

**密码登录的注意点**：密码不落盘、不进日志；`secret_store` 只存 token。现有 `SelfHostedLoginSheet` 已经这么做了，复用即可。

#### 11.1.2 候选路径（含对登录方式的影响）

| 路径 | 做法 | 扫码 | 密码 | 客户端改动 |
|---|---|---|---|---|
| **A1 服务端桥接** | 中继 Server 加一个身份源，把 IAM 当认证方，自己仍签发 device token | 需额外加二维码会话端点（开源 Server 没有） | 需 IAM 暴露密码校验 API（**多数 IAM 不开**，见风险） | 零改动（客户端仍走 provider 列表） |
| **A2 客户端直连 IAM** | App 走 IAM 的 OIDC 授权码 / 设备码流程，中继只校验 IAM token | App 自己渲染二维码、自己轮询 | App 直接调 IAM 密码接口 | 大：改 `remote_account.dart`、`server_api.dart`、登录 UI、token 刷新 |
| **A3 内嵌 IAM 登录页** | App 用 WebView 打开 IAM 登录页，页面自带扫码与密码两种 tab，回调换 token | IAM 页面提供 | IAM 页面提供 | 小：复用现有 `loginUrl` 打开方式 |

**A3 值得优先评估**：它把"扫码 + 密码"两件事交给 IAM 登录页本身，不需要 IAM 额外开放两套登录 API，客户端改动最小。缺点是体验上仍是网页（现有主路径已经是这样，用户无感知落差），且要确认 IAM 登录页允许被内嵌（`X-Frame-Options` / CSP 只影响 iframe，WebView 通常不受限，但需实测）。

**关于密码登录的风险**：多数统一身份平台**不开放明文密码校验接口**（只给 OAuth/OIDC 或扫码）。若 IAM 属于这类，A1/A2 的"账号密码"就无法直连实现，只能走 A3 的内嵌登录页，或由 IAM 侧单独开通。**这是 11.1.3 的首要待确认项。**

#### 11.1.3 待确认（阻塞项）

1. **具体对接哪套 IAM**？（自建统一身份平台 / `ai.thchengtay.com` 体系 / 其他 OIDC 提供方）
2. **IAM 是否开放这三种能力**：① 扫码登录（生成码 + 轮询状态）② 账号密码校验接口 ③ 登录页可被 WebView 内嵌。任一不支持都会砍掉对应路径。
3. IAM 侧能否新增 OAuth 客户端（client_id / redirect_uri / 回调域名）？由谁开通？
4. Host 端（如意插件）是否也要跟着改登录方式，还是继续用本地配置？

### 13.2 待办 B：固化中继服务器地址

**现状问题**：地址散落在 4 处、默认指向第三方公共服务，用户还能在高级选项里随便改成别的 Server。

| 位置 | 内容 | 性质 |
|---|---|---|
| `packages/dsh_remote/lib/src/server/server_api.dart:13` | `defaultRemoteServer = 'https://dsh.r2049.cn'` | 库层默认值 |
| `app/lib/state/hosts_state.dart:374` | `defaultRelayServer = 'https://dsh.r2049.cn'` | App 层默认值（与上面重复定义） |
| `app/lib/remote/relay/relay_backend.dart:182` | `serverLabel => 'dsh.r2049.cn'` | 界面显示用的硬编码字符串 |
| `app/lib/ui/remote/remote_screen.dart:47`、`relay_login_sheet.dart` | 副标题文案、高级选项输入框 | 界面入口 |

另有 `app/lib/l10n/*.arb` 里 3 条含 `dsh.r2049.cn` 的文案（`remoteRestoreServer` / `remoteWebConsoleProvider` / `remoteSelfHostedSignInHelp`），改地址时一并处理，并跑 `python3 app/tool/l10n_merge.py`。

**目标**：默认地址指向**自有中继**，且只有一个来源，改地址不需要动多处。

**要做的三件事**：
1. 消除双份默认值：`dsh_remote` 与 App 各一份 `dsh.r2049.cn`，统一到单一常量（或编译期注入）。
2. 地址改为可配置：建议走 `--dart-define`（如 `RELAY_SERVER`）+ 单一兜底常量，避免再出现"改了一处忘了另一处"。
3. 定夺高级选项里的自定义 Server 是否保留。若要"固化"，应默认隐藏或降级为仅内网调试可见；若不隐藏，需明确它不参与正式分发版本。

**待确认**：自有中继的正式域名/地址还没定，取决于并行进行的中继测试结果（见 13.3）。

### 13.3 与并行任务的分工

**中继服务器的测试由另一个任务在推进中**，本任务不重复做部署与联调，避免两边同时改同一套服务配置。

| 事项 | 归属 |
|---|---|
| 中继服务部署、公网可达性、HTTPS/TURN、压测与稳定性 | **另一个任务（进行中）** |
| 正式中继地址定稿 | 等中继任务结论 |
| 账号适配 IAM 的方案与实现（含扫码 / 密码两种登录入口） | 本任务（待 IAM 信息补齐） |
| 客户端地址固化（13.2 的代码改动） | 本任务，等地址定稿后执行 |
| 手机端 UI 全流程真机验证（含扫码、密码两条登录路径） | 地址与账号都定下来之后 |

### 13.4 可实现性分类

| 事项 | 状态 | 判断依据 | 兜底方案 | 回滚方案 |
|---|---|---|---|---|
| 地址单一化 + `--dart-define` 注入 | 可实现项 | 4 处硬编码已定位，改动局部；现有测试可覆盖 | 地址未定时保留现有默认值 | 还原改动文件，恢复 `dsh.r2049.cn` 默认 |
| 默认地址切到自有中继 | **待确认项** | 依赖 11.3 中继测试结论 | 未定稿前继续用现有地址 | 保留 `relayServerProvider` 手工覆盖入口 |
| App 内渲染二维码（形态 A：App 显示码） | 可实现项 | 库层已有 QR 会话与 `scanUrl` 轮询；只需加一个二维码渲染组件 + 状态页 | 继续用浏览器打开链接 | 保留 `_Waiting` 的原始链接入口 |
| App 扫码（形态 B：相机扫桌面码） | 当前暂不实现项 | 需新增相机权限与二维码解析依赖 | 走 A3 内嵌 IAM 登录页，扫页面上的码 | 不引入权限即退回 A3 / 浏览器 |
| 密码登录提升为正式入口 | 可实现项 | `SelfHostedLoginSheet` 的登录逻辑可复用，去掉"必填服务器地址"即可 | 保留高级选项入口 | 恢复原高级选项形态 |
| IAM 服务端桥接（A1） | 待确认项 | 需 IAM 开通 OAuth 客户端并暴露密码校验；Server 可二开（见 §12），但单账号改多账号是主要工作量 | 改用 A3 内嵌登录页 | 移除新增 provider，回到原 provider 列表 |
| IAM 客户端直连（A2） | 待确认项 | 需改客户端登录链与 token 刷新，工作量最大 | 退回 A1 或 A3 | 保留旧登录路径开关 |
| IAM 内嵌登录页（A3） | 待确认项 | 需实测 IAM 登录页能否在 WebView 内完成回调 | 退回浏览器 OAuth 主路径 | 关闭内嵌开关，走系统浏览器 |
| 密码由 IAM 接口直校验 | **技术不可实现项**（若无条件变化） | 多数统一身份平台不开放明文密码校验接口 | 走 A3 内嵌登录页，密码在 IAM 页面输入 | — |
| 去掉高级选项自定义 Server | 当前暂不实现项 | 内网联调仍需它；正式分发前才收口 | 用编译期开关按构建类型隐藏 | 恢复输入框 |

### 13.5 本节不作为承诺

本节只记录方向与前提，**未做任何代码改动，也没有与中继测试任务合并结论**。动手前需先补齐 11.1.3、11.2 的待确认项，并按仓库规则走方案共识。

登录方式的硬性要求已明确：**扫码登录与账号密码登录两个入口都要有**，不能只保留浏览器 OAuth 一种。具体形态（App 显示二维码 / App 扫码）与实现路径（A1 / A2 / A3）取决于 IAM 实际开放的能力。

## 14. 中继服务器二开可行性（2026-11-07 核实上游源码）

### 14.1 结论先说

**可以二开，且没有许可障碍。** 但要把话说准：**「接 IAM」不是加一个 provider 配置项，而是要把 Server 的单账号模型改成多账号模型**——真正的成本在这一块，不在登录那一行代码。

| 前置条件 | 结论 | 依据 |
|---|---|---|
| 许可允许修改分发 | ✅ | 仓库根 `LICENSE` 为 **MIT**（`THIRD_PARTY_NOTICES.md:120-126` 已登记），允许修改、商用、闭源分发，只需保留版权声明 |
| 源码完整可得 | ✅ | 上游 `apps/server/src` 共 7 个文件（`config.ts` / `gateway.ts` / `ice.ts` / `logger.ts` / `main.ts` / `server.ts` / `store.ts`），合计约 70KB，无二进制黑盒 |
| 官方态度 | ✅ 明确鼓励 | `apps/server/README.zh.md` 的 FAQ：「为什么没有多账号、完整 membership 和 Remote Web？这些能力本身实现门槛不高……**建议按自己的需求修改**」 |
| 是否已有先例 | ✅ 本仓库已改过 | `packages/dsh_remote/tool/e2e/patch-relay-attach.mjs` 就是用字符串锚点替换给上游 `gateway.ts` 挂 relay node 的补丁，注释写明「Fails loudly if upstream moved」 |
| 完整版 Server 是否开源 | ❌ | README 明确「完整 Server Web 的产品形态仍在调整，暂不承诺在本仓库开源」。开源的是**最小自部署版**（单账号） |

### 14.2 认证层的真实现状（改造前）

不要被"provider 列表"迷惑——**开源最小 Server 里没有任何 provider 抽象**，认证写死在一个分支里。

| 环节 | 实现位置 | 真实做法 |
|---|---|---|
| 账号密码校验 | `server.ts` `/api/v1/auth/login`（约 237–246 行） | 直接两次字符串比较：`equal(email, store.account)` 且 `equal(password, config.password)`。账号密码来自环境变量 `DSH_SERVER_ACCOUNT` / `DSH_SERVER_PASSWORD` |
| 登录产物 | 同上 | `secret()` 随机串存进**内存 Map**（`sessions`，key 是 token 的 hash，value **只有过期时间**），8 小时；同时下发 `dsh_session` HttpOnly Cookie |
| 会话校验 | `accountAuth()` | 只判断 token 在 sessions 里且未过期。**不携带任何身份信息**——因为只有一个账号，不需要 |
| 持久化模型 | `store.ts` state schema | `{ version: 1, account, salt, verifier, devices, tokens }`，**单个 `account` 字段为根**；账号变了就清空 `devices` 与 `tokens`（第 39–40 行） |
| 设备归属 | `server.ts` 的 `descriptor()` | `membershipId = account:${hash(store.account).slice(0,16)}`，**所有设备同一个 membershipId** |
| 连接授权 | `gateway.ts` | 全文只有一处 `authorization: 'account'`（约 422 行），**没有任何跨账号校验**，因为不存在第二个账号 |
| 扫码登录 | — | **不存在**。`/api/v1/auth/login` 只有密码一条路。客户端库的 `startQrLogin` 打的是**托管版** `dsh.r2049.cn` 的端点，开源版没有对应路由 |
| 部署形态 | `compose.yaml` | 单容器 + `server-data` 命名卷 + `restart: unless-stopped`，全是环境变量注入，改造成本低 |

### 14.3 接 IAM 的改造分解

四块，按依赖顺序。**第 3 块是主要工作量，不是登录那块。**

| # | 改造块 | 落点 | 改动内容 | 规模 | 风险 |
|---|---|---|---|---|---|
| 1 | 登录分支接 IAM | `server.ts` login 分支 | 把两个 `equal()` 换成「调 IAM 校验 / 验 IAM 签发的 token」，返回账号标识 | 小（几十行） | 低。取决于 IAM 是否开放密码校验接口 |
| 2 | 会话承载身份 | `sessions` Map + `accountAuth()` | value 从 `expiresAt` 改为 `{ account, expiresAt }`，`accountAuth()` 返回账号而非 void，`profile()` 不再返回常量 | 中 | 低。但所有调用 `accountAuth()` 的路由要跟着改签名 |
| 3 | **数据模型多账号化** | `store.ts` + `server.ts` `descriptor()` | state schema 从单 `account` 改为 `accounts: Record<id, {...}>`，`devices` / `tokens` 按账号分区，`membershipId` 按设备所属账号计算；**存量单账号数据要有迁移路径** | **大** | 中高。数据迁移 + 现有 `server-data` 卷里的设备凭据不能丢 |
| 4 | **连接授权按账号隔离** | `gateway.ts` `connect.incoming` | 建立连接前校验双方 `owner_account` 一致，否则拒绝 | 中 | **高（安全）**。不做就是越权：A 账号的手机能连 B 账号的电脑，Noise 加密也救不了——因为身份授权在 Server 侧 |

补充：`gateway.ts` 里还有 relay 分配、TURN 凭据下发等逻辑，多账号后要确认 TURN 凭据也按账号签发（现有 `username=<时间戳>:<deviceId>` 已带 deviceId，问题不大）。

### 14.4 扫码登录的缺口

这是二开里独立的一块缺口，**两条路只能选一条**：

| 做法 | 说明 | 代价 |
|---|---|---|
| 服务端自建二维码会话 | 加 `POST /api/v1/auth/qr`（生成码）+ 轮询状态 + 确认接口，签名沿用现有 session 机制 | 要新增 3 个端点与状态存储；客户端 `startQrLogin` 的字段恰好能对上（它本来就是按托管版协议写的） |
| 走 IAM 登录页（A3） | Server 只留一个「打开 IAM 登录页」的入口，扫码和密码由 IAM 页面提供 | Server 端改动最小，但 App 里是网页体验 |

**建议**：若选 A1（服务端桥接）就必须自建二维码会话；若选 A3 则连第 1 块改造都能省掉一半（只换登录页，不动 `equal()` 比较）。

### 14.5 二开方式：fork，不要继续用字符串补丁

| 方式 | 适用 | 判断 |
|---|---|---|
| 字符串锚点替换（现有 `patch-relay-attach.mjs` 手法） | 挂一个小模块、改一两行 | ⚠️ 只适合 relay node 这种局部挂载。**上游一改锚点就整体失效**，脚本自己都要 `throw` |
| Fork 独立仓库 | 改数据模型、改授权逻辑 | ✅ **本次应该用这个**。改动涉及 `store.ts` schema、`gateway.ts` 授权、登录分支三处联动，补丁方式无法维护 |

Fork 后的维护约定建议：
- 保留 `LICENSE` 与版权声明（MIT 唯一硬性要求）。
- 记录 fork 起点 commit，上游安全修复要能 cherry-pick 回来。
- 与上游协议的线格式**不要动**，否则 `packages/dsh_remote` 客户端与如意插件要同步改，得不偿失。

### 14.6 可实现性分类

| 事项 | 状态 | 判断依据 | 兜底方案 | 回滚方案 |
|---|---|---|---|---|
| Fork `apps/server` 并独立构建 | **可实现项** | MIT 许可 + 源码完整 + 官方鼓励 + 已有补丁先例 | 继续用托管版 `dsh.r2049.cn` | 保留原 `compose.yaml` 与镜像 tag，随时切回 |
| 登录分支换成 IAM 校验（块 1） | 可实现项 | 落点单一，`server.ts` 一处分支 | IAM 不支持密码校验时改走 A3 | 恢复 `equal()` 比较 |
| 会话承载账号身份（块 2） | 可实现项 | 内存 Map 结构简单，改动局限 | 临时用单账号跑通后再改 | 恢复 `expiresAt` 单值 |
| Store 多账号化（块 3） | 可实现项，工作量最大 | schema 集中在一个文件；需写迁移 | 一期可只支持单账号 + IAM 登录，多账号延后 | 保留原 `state.json` 备份，回退旧镜像 |
| Gateway 跨账号校验（块 4） | 可实现项，**安全必做** | `gateway.ts` 只有一处 `authorization: 'account'` 需扩展 | 无兜底——多账号上线前必须做，否则是越权缺陷 | 回退到单账号模式 |
| 服务端自建二维码会话 | 待确认项 | 需先定扫码形态（见 11.1.1）与是否走 A1 | 走 A3 内嵌 IAM 登录页 | 关闭该端点，回退密码登录 |
| 直接对接 IAM 密码校验接口 | **技术不可实现项**（若 IAM 不开放） | 多数统一身份平台不开放明文密码校验 | 走 A3 内嵌登录页 | — |
| 复用上游「完整版 Server」 | 技术不可实现项 | 上游明确不开源完整版 | 自建最小版 + 二开 | — |

### 14.7 风险清单

| 风险 | 影响 | 应对 |
|---|---|---|
| 块 3 数据迁移出错 | 存量设备凭据丢失，所有设备要重新登录 | 迁移前备份 `server-data` 卷；先在同构环境演练 |
| 块 4 漏做跨账号校验 | **跨账号越权**，A 的手机可连 B 的电脑 | 列为一期阻塞项，配一条跨账号连接必须失败的测试 |
| 上游大改导致 fork 偏离 | 无法 cherry-pick 安全修复 | 改动尽量收敛在 4 个落点，不动 `packages/protocol` |
| 误改线协议 | 客户端与插件全要跟着改 | 协议字段只加不改；`packages/dsh_remote` 的 fixtures 当契约测试 |
| 只做块 1、跳过 3/4 | 看起来能用，实为单账号换皮 | 明确分期：一期单账号 + IAM 登录可交付，多账号单独排期 |

## 15. 手机端 IAM 登录完整方案（2026-11-07 实测桌面端登录态）

### 15.1 先厘清一个容易误解的前提

「桌面端如意已经登录 IAM」是事实，但**它登录的 IAM 和中继 Server 用的账号是两套系统，彼此不知道对方存在**。

| 对比项 | 桌面端已登录的 IAM | 中继 Server 的账号 |
|---|---|---|
| 系统 | `https://ai.thchengtay.com/aiserver` | ds-harness-remote 的 `DSH_SERVER_ACCOUNT` |
| 插件 | `@xianxingtong/dsh-ai-server-account` | 无（Server 内置单账号） |
| 凭据形态 | IAM JWT（HS256，24h）+ opaque refreshToken | 账号密码 → 内存 session token |
| 存放位置 | `~/.xianxingtong/.credentials.yaml` 的 `ai-server-account/account` | 环境变量 / `server-data` 卷 |
| 用户标识 | `user.id` / `username` / `email` | 单个字符串 `account` |

实测到的桌面端登录态（值不外泄，只看结构与形态）：

```
status       = active
issuer       = https://ai.thchengtay.com/aiserver
accessToken  = JWT，388 字符，3 段，alg=HS256，有效期 24h
refreshToken = opaque，67 字符（非 JWT）
claims       = user_id, email, role, token_version, sid, bnd, exp, nbf, iat
                （无 iss、无 aud）
user         = { id, username, email, balance, frozen_balance, total_recharged }
```

**所以「手机端呢」的直接答案是**：手机端即使也登录了 IAM，**仍然连不上桌面**——因为中继不认识 IAM，它只认环境变量里那个单账号。桌面端"已登录 IAM"这件事，对中继是隐形的。

要让手机连上，必须**先打通中继与 IAM 的身份识别**，这是所有路径的共同前置。

### 15.2 一个硬约束：中继无法自己验证 IAM 的 token

这一条决定了方案形态，实测证据如下：

| 探测项 | 结果 | 含义 |
|---|---|---|
| JWT 签名算法 | `alg=HS256` | **对称密钥**，第三方没有密钥就无法验签 |
| `iss` / `aud` 声明 | 均缺失 | 没法按标准 OIDC 校验签发方与受众 |
| `/aiserver/.well-known/jwks.json` | 200，但返回 **SPA 的 index.html** | 假 200，实际**不存在** JWKS |
| `/aiserver/.well-known/openid-configuration` | 同上，实为 index.html | **没有 OIDC discovery** |
| `/aiserver/backend-api/auth/{me,userinfo,introspect}` 等 | 全 404 | 常规身份验证接口不存在 |
| 对照：`/backend-api/codex/models` | 无 key → **401**，带 key → **200** | 证明 `backend-api` 前缀是真实 API 区，上面的 404 是真不存在 |

**结论**：现有 IAM **不具备**让中继服务端独立完成身份验证的能力（HS256 无法本地验，又没有 introspect/userinfo/JWKS）。

因此方案有一个**外部阻塞项**：必须由 IAM 侧提供下列任一能力，否则中继无法确认"这个人是同一个人"。

| 需 IAM 提供 | 用途 | 优先级 |
|---|---|---|
| `POST /introspect`（输入 accessToken，返回 user_id 与有效性） | 中继验 token 的唯一可行方式（HS256 前提下） | **必须** |
| 或改为 RS256/ES256 + 提供 JWKS | 中继可本地验签，无需每次回源 | 更优，但要改 IAM |
| 或发放"中继专用"的 client 凭据 + 授权码流程 | 标准 OIDC 路径 | 需 IAM 开 client |

### 15.3 手机端要不要登录 IAM？—— 不必，推荐不登录

关键认知：**手机需要的是中继签发的 device token，不是 IAM 身份本身**。IAM 只在「首次证明我和桌面是同一个人」时用一次。

| 方式 | 手机要登录 IAM 吗 | 用户操作 | 体验 | 前提 |
|---|---|---|---|---|
| **M1 桌面绑定码（推荐）** | ❌ 不需要 | 桌面显示码 → 手机扫码/输码 | 最好，两下完成 | 中继支持 client 绑定码（需二开） |
| **M2 手机自己登录 IAM** | ✅ 需要 | 手机输 IAM 账号密码 / IAM 扫码 | 一般 | IAM 开放登录 + 13.2 的验证接口 |
| **M3 中继独立账号（现状）** | ❌ 不需要 | 手机输另一套账号密码 | 差，记两套密码 | 无，现在就能用 |

**推荐 M1 为主、M2 兜底**：
- 平时用 M1：手机零 IAM 凭据，桌面在线就能授权
- 桌面不在线、需新增手机时用 M2：手机自己登录一次 IAM
- M3 保留为内网调试与 IAM 不可用时的退路

### 15.4 推荐方案端到端流程（M1 为主）

```
桌面如意(已登IAM)        中继 Server              IAM              手机App
     |                      |                     |                  |
     |--① 注册Host(带IAM accessToken)------------->|                  |
     |                      |--② introspect ----->|                  |
     |                      |<-- user_id ---------|                  |
     |<--③ device token ----| owner=iam:<user_id> |                  |
     |                      |                     |                  |
     |--④ 生成绑定码-------->| code → iam:<user_id>|                  |
     |   (界面显示二维码/6位码)                     |                  |
     |                      |                     |                  |
     |                      |<--⑤ 提交码(扫码/输入)------------------|
     |                      |--⑥ 校验码(未用/未过期)                  |
     |                      |---⑦ 签发 device token(同 owner)-------->|
     |                      |<--⑧ 连接(device token)------------------|
     |<=====⑨ Noise 端到端加密(P2P/TURN/Relay) =====>|                  |
```

要点：

| 环节 | 关键设计 |
|---|---|
| ① | 桌面把**已有**的 IAM accessToken 交给中继，不要求重新登录 |
| ② | 中继调 IAM 验证（13.2 的阻塞项）。**只此一次**，之后不再依赖 IAM |
| ③ | 中继签发自己的 device token，`owner_account = iam:<user_id>`。这是长期凭据，走协议已有的 refresh 轮换 |
| ④ | 绑定码 **10 分钟过期、单次消费**，沿用协议 `host-registration-codes` 的既有约束 |
| ⑤⑥⑦ | 手机不需要任何 IAM 凭据，只交一个码 |
| ⑧⑨ | 与现有链路完全一致，Noise IK 端到端加密，中继看不到明文 |

**为什么不让手机直接复用桌面的 IAM token**：IAM accessToken 只有 24h，桌面要长期在线必须能自动续；把 refreshToken 复制到手机等于凭据扩散到多设备，IAM 侧无法区分是哪台设备在用，吊销时会把桌面一起踢掉。**用中继 device token 才是正解**——它本来就有按设备吊销的能力。

### 15.5 三端改造清单

| 端 | 改造 | 依赖 | 规模 |
|---|---|---|---|
| **中继 Server** | ① 加 IAM 身份适配（login 分支换成"收 IAM token → introspect → 写 owner"）<br>② session 承载账号（§12 块 2）<br>③ store 多账号化（§12 块 3）<br>④ gateway 跨账号校验（§12 块 4）<br>⑤ `register-with-code` 扩展支持 `role=client`（协议现状只允许 host）<br>⑥ 新增「账号侧生成绑定码」端点 | IAM introspect 接口 | 大 |
| **桌面如意** | ① Host 注册时带上 IAM accessToken（读 `ai-server-account` 凭据）<br>② 远程面板加「授权手机」入口：生成码 + 显示二维码<br>③ IAM token 过期后自动用 refreshToken 续，再向中继换新 device token | 中继①~⑥ | 中 |
| **手机 App** | ① 新增「扫码绑定」入口：相机扫码 + 手输 6 位码<br>② 新增「用 IAM 账号登录」入口（M2，扫码或密码）<br>③ 登录 UI 按服务端能力动态展示（现有 `providers` 机制可复用） | 中继端点 | 中 |

**手机端扫码要加的依赖**：现有 `pubspec.yaml` 没有二维码解析组件，需引入（如 `mobile_scanner`）并申请相机权限；二维码**渲染**（M1 桌面端显示码）也需要一个轻量组件。

### 15.6 实施顺序（每步都可独立验证）

| 阶段 | 内容 | 验证方式 |
|---|---|---|
| P0 | IAM 侧提供 introspect 或改非对称签名 | 拿真实 token 调通，返回 user_id |
| P1 | 中继：IAM 适配 + session 身份（§12 块 1+2） | 桌面用 IAM token 注册 Host 成功，设备 owner 是 `iam:<user_id>` |
| P2 | 中继：绑定码端点 + `register-with-code` 支持 client | 手工 curl：生成码 → 用码注册 client → 两端 owner 一致 |
| P3 | 桌面：授权手机 UI + 二维码 | 面板能出码，10 分钟过期，二次使用被拒 |
| P4 | 手机：扫码绑定入口 | 真机扫码 → 连上 → 出新消息 |
| P5 | 中继：多账号化 + 跨账号校验（§12 块 3+4） | **跨账号连接必须失败**的测试用例 |
| P6 | 手机：M2 IAM 登录入口（兜底） | 手机独立登录 IAM 后能列出自己的 Host |

**P1~P4 打通就已经能"手机连自己电脑"了**，P5 是上线多用户前必须补的，P6 是体验补充。

### 15.7 可实现性分类

| 事项 | 状态 | 判断依据 | 兜底方案 | 回滚方案 |
|---|---|---|---|---|
| 桌面显示绑定码 + 手机扫码绑定（M1） | **可实现项** | 协议已有匹配码机制可复用；桌面已持 IAM 凭据 | 退 M3 中继账号密码 | 关掉入口，回退密码登录 |
| 手机自己登录 IAM（M2） | 待确认项 | 卡在 13.2：IAM 无 introspect/JWKS，HS256 无法自验 | 只做 M1，M2 延后 | 隐藏入口 |
| 中继验 IAM token | **待确认项（外部阻塞）** | 实测无 introspect、无 JWKS、无 OIDC discovery | 由 IAM 改 RS256 或开 introspect | — |
| `register-with-code` 支持 client | 可实现项 | 协议限定 `role=host`，需改校验；客户端已有对应请求 schema | 不改协议，手机走 M2/M3 | 恢复只允许 host |
| 手机扫码（相机） | 当前暂不实现项 | 需新增加密依赖与权限；P0 不阻塞 | 手输 6 位码 | 不引入权限即只留手输 |
| 桌面 IAM token 过期自动续 | 可实现项 | 凭据里已有 refreshToken 与 expiresAt | 过期后要求重新登录 | 保留手动重登入口 |
| 手机复用桌面 IAM token | **技术不可实现项** | 24h 过期 + 凭据扩散 + 无法按设备吊销 | 用中继 device token 代替 | — |
| IAM 支持标准 OIDC（含 JWKS） | 技术不可实现项（现状） | 无 discovery、无 JWKS，HS256 | 由 IAM 团队改造 | — |

### 15.8 风险与待确认

| 风险 | 影响 | 应对 |
|---|---|---|
| IAM 不提供验证接口 | 整个 M1/M2 无法成立，只能留 M3 | **P0 是唯一硬阻塞**，先谈 IAM |
| IAM token 24h 过期 | 桌面需定期续期，否则无法再注册 Host | 用 refreshToken 自动续；中继 device token 长期有效，断连不影响 |
| 绑定码泄露 | 他人可把自己的手机绑定到你的账号 | 10 分钟 + 单次消费 + 绑定后弹窗确认；协议已有此约束 |
| 跨账号越权（P5 未做） | 任意手机可连任意桌面 | P5 列为上线阻塞项 |
| 手机端多一条相机权限 | 应用商店审核与用户信任 | 仅在扫码时申请，明确文案 |

**待确认（按阻塞顺序）**：
1. IAM 能否提供 introspect / 或改 RS256 提供 JWKS？（**决定方案能否成立**）
2. IAM 是否允许桌面端的 accessToken 被第三方服务验证（跨服务信任）？
3. 绑定码的展示形态：二维码 + 6 位码是否都要？
4. 是否允许多台手机绑同一账号？（协议支持多 Client，确认产品是否要限制）

## 16. 多账号（企业级）方案与成本

### 16.1 现状：上游是**单账号**设计

不是配置没开，而是数据模型和文档都只有一个人：

- 官方 README 第一句：*"A single-account Remote Server ... configured through environment variables."*
- FAQ 明确：*"Why are multi-account support ... not included? These capabilities are not especially difficult to build, but users have different scenarios and trade-offs, so it is reasonable to adapt them to your own needs."*
- 本机实测 `state.json` 结构：

```json
{"version":1,"account":"<唯一账号>","salt":"...","verifier":"...","devices":{"<deviceId>":{...}}}
```

`account` 是**顶层单值**，`devices` 是**扁平表**，没有 owner 字段。

### 16.2 为什么企业级必须解决

单账号下所有同事共用一个登录：

| 问题 | 后果 |
|---|---|
| 设备列表不隔离 | 任何登录的人都能看到并连上别人的电脑 |
| 无法按人吊销 | 一个人离职只能改密码，全员重新授权 |
| 无审计 | 不知道谁在什么时候连了哪台机器 |
| 密码共享 | 无法追责，也不符合最小权限 |

所以「每人一个账号」不是体验优化，是能不能给同事用的前提。

### 16.3 三条路线

| 路线 | 做法 | 隔离方式 | 服务端改动 | 运维成本 | 适合规模 |
|---|---|---|---|---|---|
| **A. 一人一实例** | 每人一个容器 + 独立卷 + 独立地址 | 进程级，天然隔离 | **0** | 每人一个地址/证书，升级要逐个滚 | ≤ 10 人 |
| **B. Fork 改多账号** | 把 `account` 单值改成 `accounts{}`，设备加 `accountId` | 数据级，同一服务 | 中等（见 16.5） | 一套服务，一次升级 | 10 人以上 |
| **C. 网关按子域分流** | 泛域名 + 每个子域一个实例，网关自动建/路由 | 实例级 | 0（只写网关） | 中，要维护实例编排 | 10–50 人 |

三者的共同点：**客户端不用改**。手机端本来只做两件事——填服务器地址、用账号密码登录；账号怎么存、设备怎么隔离全在服务端。

### 16.4 推荐路径

1. **先用 A**，1–2 个实例，把「同事用自己的账号连自己的电脑」真实跑一遍，暴露使用问题（谁需要连谁的机器、是否要跨人协作）。
2. 人数超过 10 或地址管理开始烦，再上 **B**（或先用 C 过渡）。
3. 不建议直接跳到 B：多账号一旦上线就要承担数据迁移和长期跟上游同步的成本，先确认团队真的按"一人一机"用。

### 16.5 B 的改造清单（供评估，未实施）

| 改动点 | 内容 | 难度 |
|---|---|---|
| 数据模型 | `state.json` 升到 v2：`accounts{account:{salt,verifier,devices{}}}`，写迁移函数兼容 v1 | 低 |
| 登录 | `DSH_SERVER_ACCOUNT/PASSWORD` 从单值改为账号表（或接 IAM），登录返回绑定 accountId 的会话 | 低 |
| 令牌 | access/refresh 里带 accountId；刷新时校验仍属同一账号 | 中 |
| 设备 | `devices` 每条加 `accountId`，`GET /api/v1/devices` 按当前账号过滤 | 低 |
| 连接授权 | `connect` 只允许同账号的 host↔client，跨账号直接拒 | 中 |
| Web UI | 登录态 cookie 带 accountId，页面只显示自己的设备 | 中 |
| 测试 | 现有 server 测试 + 新增"跨账号不可见/不可连"用例 | 中 |

**工作量估计**：熟悉 Node/TS 的前提下，MVP 3–5 人日，加回归与上线约 1 周。主要风险不是写代码，而是**长期跟上游同步**——上游还在演进（WebRTC、Remote Web），fork 越深越难合。

### 16.6 企业级还差的其他能力

即使做了多账号，正式给团队用还缺：设备吊销面板、审计日志（谁连了哪台、什么时候）、账号与公司 IAM/SSO 打通（§13 的硬阻塞是 IAM 没有 token 校验接口）、监控告警、数据备份与恢复演练。

### 16.7 一句话结论

**「中继多账号登录」要实现，但不必现在从头改**：单账号是上游的明确设计，不是配置遗漏。最省事的是先一人一实例（零改代码），确认团队用法后再决定要不要 fork 成多账号；客户端在这两种方案下都不用改。

