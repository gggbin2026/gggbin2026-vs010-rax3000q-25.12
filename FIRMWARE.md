# 出厂默认与排障

## 默认

| 项 | 值 |
|---|---|
| 管理地址 | `172.10.10.241` / `255.255.252.0`（/22）；**WDS 与 AP 两套固件出厂都是 `.241`** |
| 账号 | `root` / `admin`（SSH 22、串口 `ttyMSM0` 115200n8、TTYD :7681） |
| 根路径 | `/` 按当前模式自动跳 `/bridge/` 或 `/ap/`，3 秒兜底 |
| 后台 | `http://172.10.10.241/cgi-bin/luci/`（`/cgi-bin/luci` 同效） |
| 产品标识 | `WDS/AP（仿UBNT）`，写在 `/etc/nwrt/product` 与 SSH banner |
| 工作模式 | **单包双模式**：一个固件内置 AP + WDS，界面里切，不用重刷 |
| 首启默认 | `default_mode=wds`（刷机不勾「保留配置」回到默认；切模式写 overlay，重启不丢） |
| 单常驻 | `nwrt-tick`（NTP 校时 + WDS 关联只读巡检），出厂 `DRYRUN=1` 只记录不动作 |
| 首启默认 | `default_mode=wds`（刷机不勾「保留配置」回到默认；切模式写 overlay，重启不丢） |
| 单常驻 | `nwrt-tick`（NTP 校时 + WDS 关联只读巡检），出厂 `DRYRUN=1` 只记录不动作 |
| 首启默认 | `default_mode=wds`（刷机不勾「保留配置」回到默认；切模式写 overlay，重启不丢） |
| 单常驻 | `nwrt-tick`（NTP 校时 + WDS 关联只读巡检），出厂 `DRYRUN=1` 只记录不动作 |
| 首启默认 | `default_mode=wds`（刷机不勾「保留配置」回到默认；切模式写 overlay，重启不丢） |
| 单常驻 | `nwrt-tick`（NTP 校时 + WDS 关联只读巡检），出厂 `DRYRUN=1` 只记录不动作 |
| 网络 | WAN + LAN + 2.4G + 5G 全在 `br-lan` 纯二层；上级 DHCP 透传 |
| 防火墙 / IPv6 / 本机 DHCP 服务端 | 全部关闭 |
| 无线 | CN；5G ch36 HE160；2.4G ch1 HE40；`noscan` 默认不开 |
| 5G CAC | HE160 开机约 60 秒 DFS 等待，期间 5G 不可见、2.4G 先起；改 HE80 可免等 |
| WDS | 只用 5G 4addr，2.4G 关闭；SSID `NWRT-WDS`，默认 `psk2` / `WDS123456` |
| AP | 2.4G `NWRT-AP-2G`、5G `NWRT-AP-5G`，默认 `psk2` / `AP123456` |

## ⇄ 切模式（AP ⇄ WDS，不用重刷）

| 路径 | 操作 |
|---|---|
| LuCI（推荐） | 登录 `http://172.10.10.241/cgi-bin/luci/` →「WDS / AP 模式」，点两个按钮之一 |
| 直链 | `http://172.10.10.241/cgi-bin/luci/admin/nwrt` |
| TTYD / SSH / 串口 | `nwrt-apply-mode wds` 或 `nwrt-apply-mode ap` |

切换只写 overlay + 一次 `wifi reload`，不重建 radio、不 `wifi down`、不重启。
若直链 404（该基线未编 `luci-compat`），用命令那条，效果完全一致。
根路径 `/` 会自动跳到当前模式的状态页；三页仍可直接互访。

改 SSID / 密码 / 信道：LuCI 后台或串口 `uci set wireless...` 后 `wifi reload`（不要 `wifi down`）。

## 🔴 两台 WDS 组网必读（IP 冲突）

出厂写死 `.241`，**没有自动分配主/客 IP**。两台 WDS 桥接前必须把客户端改成别的地址，
否则同网段 IP 冲突、SSH / 界面时通时断。本仓支持一个覆盖文件，重启不会被
`bridge-netfix` 重写回去：

```sh
echo 172.10.10.242 > /etc/nwrt/ipaddr
uci set network.lan.ipaddr='172.10.10.242'
uci commit network
/etc/init.d/network reload
```

留空或删掉 `/etc/nwrt/ipaddr` 就回到 `.241`。AP 固件保持 `.241` 即可。

## 一键核对

串口或 SSH：

```sh
wifi-fullspeed        # 内核、模块、NSS、eth0/eth1、射频、模式、巡检、温度
health-fix            # LuCI / 主题 / 缓存 / 桥 / 防火墙 / DHCP 防护 / 巡检 全量自助修复
oem-stack-check       # 只读自检：确认本仓是主线 ath11k，不是闭源 QSDK 栈
nwrt-apply-mode ap    # 切到 AP（wds 则回网桥），不用重刷
```

## 常见现象

| 现象 | 原因 / 处理 |
|---|---|
| LuCI 报 `dispatcher.lua:427` 或白屏 | 串口 `sh /usr/sbin/health-fix`，刷新浏览器，不用重刷 |
| 5G 开机 1 分钟看不到 | HE160 的 DFS CAC，正常；2.4G 先起。改 HE80 可免等 |
| `br-lan` 速率很低但测速正常 | 流量被 NSS 卸载，根本不经过 Linux 网桥；看 `eth0/eth1` |
| 2.4G 只有 20MHz | 邻区共存扫描退化；`uci set wireless.radio0.noscan=1` 强开 HE40 可 +50%，但无视共存，默认不开 |
| 无线端拿到错地址 | `l2-guard` 尽力拦无线侧 DHCP；NSS 卸载后部分报文不过 host hook，必要时在上级关无线侧 DHCP |
| 模式切换页 404 | 该基线没编 `luci-compat`，控制器不 dispatch；用 `nwrt-apply-mode wds|ap`，效果一致 |
| 想让机器狗真动作 | 把 `/etc/nwrt/tick.conf` 的 `DRYRUN=1` 改 `0` 后 `/etc/init.d/nwrt-tick restart`；仍限 30 轮冷却 |
| 模式切换页 404 | 该基线没编 `luci-compat`，控制器不 dispatch；用 `nwrt-apply-mode wds|ap`，效果一致 |
| 想让机器狗真动作 | 把 `/etc/nwrt/tick.conf` 的 `DRYRUN=1` 改 `0` 后 `/etc/init.d/nwrt-tick restart`；仍限 30 轮冷却 |
| 模式切换页 404 | 该基线没编 `luci-compat`，控制器不 dispatch；用 `nwrt-apply-mode wds|ap`，效果一致 |
| 想让机器狗真动作 | 把 `/etc/nwrt/tick.conf` 的 `DRYRUN=1` 改 `0` 后 `/etc/init.d/nwrt-tick restart`；仍限 30 轮冷却 |
| 模式切换页 404 | 该基线没编 `luci-compat`，控制器不 dispatch；用 `nwrt-apply-mode wds|ap`，效果一致 |
| 想让机器狗真动作 | 把 `/etc/nwrt/tick.conf` 的 `DRYRUN=1` 改 `0` 后 `/etc/init.d/nwrt-tick restart`；仍限 30 轮冷却 |
| 刷完起不来 | 先确认不死 U-Boot 支持 aarch64 64 位引导；接 TTL 看 `console=ttyMSM0,115200n8`；别勾「保留配置」 |

## 版本口径

内核版本由编译期 `make -s kernel_version` 实抓（退回 `LINUX_VERSION`，再退回 `baseline.env` 提示值），
固件名、Release tag、`/etc/nwrt/build` 三处一致，不写死旧 SDK 编号。
