# 机器狗插件 · 用户配置说明（第 58 次）

🔴 **配置 100% 由你自己设置**。编译期不注入、首启不覆写、升级不冲掉。

## 三种配置方式（任选，优先级从高到低）

| 优先级 | 方式 | 说明 |
|---|---|---|
| ★ 最高 | `/etc/wdsdog.conf` | 纯 `KEY=VALUE`。`bridge-watchdog config` 一键生成全注释模板，自己取消注释填值 |
| 中 | `uci set wdsdog.main.<key>=<值>; uci commit wdsdog` | 或 `bridge-watchdog set-delay 10` / `set-peer auto` / `set-mode or` 等 CLI |
| 低 | 出厂 `/etc/config/wdsdog` | 仓库自带默认值（enabled=1 / delay=5 / grace=6 / max_reboots=3），**冻结基线保留** |

删掉 `/etc/wdsdog.conf` 即完全回到 UCI 出厂值。

## 完全自己配（推荐流程）

```sh
bridge-watchdog config                  # 生成 /etc/wdsdog.conf（全注释）
vi /etc/wdsdog.conf                     # 自己取消注释、填值
/etc/init.d/bridge-watchdog restart
bridge-watchdog status                  # 看「配置源 / 启用 / 距重启还剩」
```

## 未配置时不会乱重启

`/etc/wdsdog.conf` 不存在 **且** UCI 段被删光 → 标记「未配置」：插件只待命、
`status` 显示 🔴 提示、**绝不重启**。写好配置后 restart 或下次开机立即生效。

## 可调参数

| key | 默认 | 含义 |
|---|---|---|
| `enabled` | 1 | 1=启用 / 0=彻底停用 |
| `delay` | 5 | **连续**不通多少分钟才重启（1~120） |
| `grace` | 6 | 开机宽限分钟（等 WiFi 校准 / 主备收敛，期间可从容 SSH） |
| `interval` | 30 | 每多少秒检查一次 |
| `iface` | auto | 固定 WDS 接口名 |
| `peer` | auto | auto=按主备互 ping **对端** / off=不 ping / 具体 IP |
| `anchor` | 空 | 可选锚点（上级网关），任一通即算通 |
| `mode` | or | `or`(任一判据通即通，最不容易误重启) / `ping` / `wireless` |
| `max_reboots` | 3 | 连续重启上限，达到后自动转 dryrun 停手 |
| `dryrun` | 0 | 1=只记日志不重启（调试用） |

## 常用命令

```sh
bridge-watchdog status | once | config
bridge-watchdog on | off | dryrun on|off
bridge-watchdog set-delay 10 | set-grace 8 | set-interval 60
bridge-watchdog set-peer auto | set-anchor 172.10.10.254 | set-mode or
bridge-watchdog set-max-reboots 3 | resync   # 改网桥 IP 后必跑
```

⚠️ `peer` 要 ping **对方**，不是自己 —— 自己 IP 永远通，判不出断链。
改管理 IP 不会误重启（链路本地别名 169.254.241.1/.2 与管理 IP 解耦）。

## 插件装卸

本包是标准 OpenWrt package：`CONFIG_PACKAGE_bridge-watchdog=y` 编入镜像，
也可改成 `=m` 只产出安装包、镜像里不带；装好后用 `apk del/add bridge-watchdog`
（25.12 用 apk）单独装卸升级，不影响其它 82 项冻结基线。
