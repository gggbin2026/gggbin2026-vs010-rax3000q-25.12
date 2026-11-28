# 出厂默认与排障

## 默认

| 项 | 值 |
|---|---|
| 管理地址 | `172.10.10.241` / `255.255.252.0`（/22）；**WDS 与 AP 两套固件出厂都是 `.241`** |
| 账号 | `root` / `admin`（SSH 22、串口 `ttyMSM0` 115200n8、TTYD :7681）；`nwrt-passwd`(START=19) 只在密码为空时设，用户改过不覆盖 |
| 主题 | **UBNT（仿 UniFi）深色**：三页状态页 + LuCI 后台统一；`/luci-static/ubnt` 覆盖层 + 官方 bootstrap 底资源 |
| 根路径 | `/` 按当前模式自动跳 `/bridge/` 或 `/ap/`，3 秒兜底 |
| 界面 | 三页 UBNT 同款：GAUGE 三环 → SETUP 八分组 → NETWORK（内网LAN1… 6 列）→ 业务块；六入口互访 + 右上角 ⚙ 高级设置后台 |
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
| 网络 | **所有网口（含 WAN 物理口）+ 2.4G + 5G 全在同一个 `br-lan`**，纯二层、无 WAN 逻辑口；上级 DHCP 透传 |
| STP | **开**（`br-lan` `stp=1`），防两台 WDS 桥接成环；代价是端口 up 有转发延迟 |
| WAN / WAN6 | 出厂 `/etc/config/network` 里没有，`bridge-netfix` 每次开机再 `uci delete` 兜底 |
| 无线侧 DHCP Snooping | **开**：独立 nft bridge 表 `hook prerouting` 丢无线口进来的 67→68 / 547→546；状态页显示实际是否生效 |
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

出厂默认 `172.10.10.241` / `255.255.252.0`，**没有自动分配主/客 IP**。两台 WDS
桥接前必须把第二台改成别的地址，否则同网段 IP 冲突、SSH / 界面时通时断。

🟢 **改了就保存，系统绝不自动改回**（本轮修复）：优先级是
`/etc/nwrt/ipaddr`|`netmask` 覆盖文件 > `user.cfg` 的 `ip`|`mask` > 出厂默认。
`bridge-netfix`(21) 与 `nwrt-apply-config`(24) **只读**覆盖文件，不删、不写、不覆盖；
`role=client` 也不再自动写死 `.242`。唯一会写覆盖文件的地方是面板 `save` 里
**显式提交**了 ip/mask 字段（避免「只改 SSID 保存」把串口设的 .243 悄悄盖掉）。

三条改法，效果一样、都持久（重启 / 切模式 / 重刷不勾保留配置除外）：

```sh
# ① 串口 / SSH / TTYD（最快，推荐第二台用）
echo 172.10.10.242 > /etc/nwrt/ipaddr
echo 255.255.252.0 > /etc/nwrt/netmask      # 掩码也改才写这行；不改就省略
/etc/init.d/bridge-netfix start

# ② 面板 ⑤「本机与网络」填管理 IP / 子网掩码 → 保存（立刻生效 + 写覆盖文件）
# ③ uci 直改
uci set network.lan.ipaddr='172.10.10.242'; uci commit network; /etc/init.d/network reload
```

⚠ 只有「删掉 /etc/nwrt/ipaddr|netmask 且 user.cfg 也是默认值」才回 `.241`；
删文件是用户主动动作，脚本不会替你删。掩码默认写死 /22，上级若是别的网段
（如 192.168.1.x/24）请一并改 `netmask` 或 `ip`，否则管理页打不开。
AP 模式保持 `.241` 即可。改 IP 不影响 WDS 桥接本身（靠 MAC/4addr，不靠 IP）。

## 一键核对

串口或 SSH：

```sh
/etc/init.d/l2-guard status   # 看无线侧 DHCP 防护到底生没生效
/etc/init.d/l2-guard restart  # 手工重建规则
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
| 无线端拿到错地址 | `l2-guard` 尽力拦无线侧 DHCP；NSS 卸载后部分报文不过 host hook，必要时在上级关无线侧 DHCP；状态页「DHCP 防护」会显示「已生效／失败：…」，不假装成功 |
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

## 无线界面新增（本轮）

| 需求 | 落地 | 真值来源 |
|---|---|---|
| 网桥页搜索并自动加入 SSID | ② 分组 `🔍 搜索 SSID` → 结果表「选用」一键带入 SSID / BSSID / 信道 / 频宽；密码手填；手动填写区保留 | `iw scan` 的 `DS Parameter set` / `STA·VHT channel width` |
| 自动匹配频宽 | 160→HE160 / 80→HE80 / 40→HE40 / 20→HE20；未广播留空提示手选 | 同上，不猜 |
| AP 页弱信号拒绝连接 | `rssi_reject_assoc_rssi` / `rssi_reject_assoc_timeout` / `rssi_ignore_probe_request` 真实下发到 wifi-device | `wifi-scripts/.../hostapd.sh:128,245`（v25.12.6 实证） |
| AP 页弱信号剔除 | `disassoc_low_ack=1`（hostapd 默认）+ `kick_enabled` 开关（默认关）按 `kick_rssi` 用 `iw station del` deauth | `hostapd.sh:574,611` + 标准 iw |
| WDS 桥接后信号 / 距离 / 速率 | 回程 LINK 卡片 + 终端表距离列；TX/RX 实读，距离 FSPL **估算并标注非实测** | `iw link` / `iw station dump` |
| 接口 MAC 不手填 | NETWORK 新增 MAC 表格；ART 分区 base + 所有接口 MAC 自动读取 | DTS `nvmem-cells` + `/proc/mtd` + sysfs |
| WMM / MU-MIMO | WMM `wmm_enabled=1` 恒定开；MU-MIMO 随 HE / `ieee80211ax` 由固件协商；**无独立 UCI 开关，不伪造** | `hostapd.sh:614` / `mac80211.sh:464,492+` |

⚠ WDS 是 STA 模式，hostapd 不运行 → 弱信号拒绝连接项在 WDS 下**删除不下发**，
状态页会如实写明；AP 模式才生效。QSDK 私有 `db_rssi_thr` / `db_timeout` / `HT*` 仍禁用。

## NAND ECC 补丁口径（第 21 轮实证）

用户给出 [上游 fb90296 邮件](https://lists.infradead.org/pipermail/lede-commits/2025-May/025412.html)
（*qualcommax: ipq50xx: spi-qpic-snand: default to 4-bit ECC*），问 VS010 / RAX3000Q
是否要加入。**结论：不需要，上游三条基线已内置，本仓 DTS 另有一重保险。**

| 基线 | 0401 位置 | 状态 |
|---|---|---|
| `official-25.12` / `v25.12.6`（默认） | `target/linux/qualcommax/patches-6.12/0401-spi-spi-qpic-snand-default-to-4-bit-ECC.patch` | ✅ 1589 字节 |
| `qosmio-25.12-nss` | 同名 | ✅ 内容一致 |
| `official-main`（KERNEL_PATCHVER=6.18） | `target/linux/qualcommax/patches-6.18/0401-...` | ✅ 随内核目录迁移 |
| `kuncy7-6.18-nss` | REPO 留空，workflow 拒绝 | ⚠ 无法实证 |

补丁本身：芯片 ID 表声明 1/2-bit 最小 ECC → QPIC-SNAND 只支持 4/8-bit → 旧驱动
probe 失败；0401 把 1/2-bit 回退成 `ECC_MODE_4BIT`。`v25.12.6` 内置版 hunk 为
`@@ -304,6 +304,24 @@`（邮件原版是 `-296,6`，因为前面叠了 backport）。

**本仓双保险**：`v25.12.6` 的 generic backport `412`（DT `user_conf` 优先于芯片
`reqs`）+ `417`（新增 8-bit 支持）都在；本仓 DTS 显式写
VS010 `step=512 / strength=4`、RAX3000Q `step=512 / strength=8`，
直接命中 `case 4` / `case 8`，不会走进 1-bit 回退分支。

把邮件原版 diff 放进本仓 `patches/` 会 `git apply --check` 失败（OpenWrt 树里没有
`drivers/spi/spi-qpic-snand.c`，内核源码构建期才展开），脚本只打 warning 跳过，
**不会生效也不会破坏编译**。`nand_patch` 保持默认 `false` 即可。
EUCLEAN / FM25LS01 V2 批次是 UBI 层坏块问题，与这个驱动修复不是一回事。
