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

## qosmio-25.12-nss：加速 / 占用 / 速度（第 22 轮实证）

用户问「这个基线的固件能无线加速吗、资源占用低吗、运行速度快吗」。逐条实证：

**① 能加速，但要先修两个写错的包名。** qosmio 的 `feeds.conf.default` 确实含
`src-git nss_packages https://github.com/qosmio/nss-packages.git;NSS-12.5-K6.x`，
workflow `feeds update -a && install -a` 会装；主树
`package/kernel/qca-nss-dp/Makefile` 存在。但本仓 `gen-config.sh` 旧写法
`nss-ecm` / `qca-nss-fw-ipq50xx-retail` 在 feed 里**不存在**
（feed 实名 `KernelPackage/qca-nss-ecm` → `kmod-qca-nss-ecm`、
`Package/nss-firmware-ipq50xx`），`make defconfig` 静默丢弃 → ECM 不进镜像。
r22 已改名为 5 个实证符号并在 defconfig 后硬校验、缺包停编。
**默认 `official-25.12` 是 NSS=0，不受影响。**

**② 加速的是转发，不是空口。** NSS/ECM/DP 卸载 Linux 网桥 + CPU 的转发路径，
5G 空口速率由 ath11k / HE160 / 射频环境决定。参考仓 PZ-L8 实测的
`ECM→NSS + wifili 双射频卸载` 来自 QSDK 闭源 `qca_ol/umac` 栈；
本仓是**主线 ath11k**，wifili 无线卸载在 VS010 / RAX3000Q 上**未实机验证**，
不能把旧栈数字当本仓保证。能确认的是有线/桥接卸载与 CPU 下降。

**③ 占用：静态更高、运行时 CPU 更低。** 多编 5 个加速包 + `qca-nss0/1-retail.bin`，
镜像更大、内核模块与常驻内存更多；NSS 基线还保留 IPv6 内核符号（官方基线编译期
直接 `CONFIG_IPV6=n`）。「占用最低」是默认 `official-25.12` 那条；
qosmio 是拿静态资源换 CPU 与吞吐。规格日志边界第 11 条写得很明确。

**④ 速度口径（参考仓 / 老仓实测，非这两台实机）**

| 项 | 数字 | 来源 |
|---|---|---|
| 5G 160MHz（NSS 基线） | 773~833 Mbps | `baseline.env` 注释 |
| 5G 160MHz（PZ-L8 QSDK 参考仓） | 697 Mbps @ 2.9% CPU | README 参考实现段 |
| 5G 80MHz | 462 Mbps（少约 1/3） | 同上 |
| 有线 | 949/949 Mbps @ +0% 主机 CPU | 同上（QSDK 双 GMAC） |
| `official-25.12` 无 NSS | DSA 软转约 502 Mbps 跑满双核 | README 基线表 |
| `kuncy7-6.18-nss`（尝鲜，本仓编不了） | 915 Mbps AP→STA @ CPU 1~3% | README |

代价：CN + HE160 开机约 60 秒 DFS CAC（期间 5G 不可见、2.4G 先起），
改 HE80 可免等；2.4G HE40 因共存扫描退 20MHz，MCS 6–7 是该平台固有弱项。
**判速看 `eth0/eth1` + NSS debugfs，不看 `br-lan`**（卸载流量不过 Linux 网桥）。

**⑤ 边界**：三条基线都没有这两台板级（RAX3000Q 2026-09-27 才入 main、
稳定 tag 与 qosmio 25.12-nss 都没有），靠本仓注入；RAX3000Q 板级未在
6.12 主线实机验证，首次刷接 TTL。所有速率是参考仓实测，本仓未在 Actions
真跑 `make`、未实机。选 qosmio 要在 Run workflow 手动选
`baseline=qosmio-25.12-nss`，默认仍是 `official-25.12`。

## 第 23 轮 · Actions run `46149348907` 失败分析与修复

### 拿到的日志信息

页面 `https://github.com/gggbin2026/gggbin2026-vs010-rax3000q-25.12/actions/runs/46149348907`
（HEAD `11ad569`，2026-11-28 13:23，2m22s，**Failure**，0 artifacts）：

- **6 errors**：`build (vs010)` / `build (rax3000q)` 各
  `Process completed with exit code 1.` +
  `nftables 未进 .config（feed 缺包或被依赖覆盖），无线侧 DHCP 防护会失效` +
  `请检查 feeds.conf.default 与所选基线；不要编一个假防护的固件`。
- **2 warnings**：`Node.js 20 is deprecated ... actions/checkout@v4 ... forced to run on Node.js 24`
  —— runner 层面提示，**与失败无关**。
- 页面显示 `Sign in to view logs`，完整 step 日志需登录；匿名 GitHub API
  被 rate limit。上述 annotation 已给出确切失败点（gen-config 的 6.5 段），
  结合本地 `openwrt/openwrt @ v25.12.6` 源码实证即可精确定位，不靠猜。

### 根因（逐基线实证）

| 基线 | `package/network/utils/nftables/Makefile` 的 BuildPackage |
|---|---|
| `openwrt/openwrt @ v25.12.6`（默认） | `nftables-nojson`、`nftables-json` |
| `openwrt/openwrt @ main` | 同左（2006 字节） |
| `qosmio/openwrt-ipq @ 25.12-nss` | 同左（2006 字节） |

`define Package/nftables/Default` 只是被两个变体继承的模板，
里面的 `PROVIDES:=nftables` 是**虚拟提供名**，不会生成
`CONFIG_PACKAGE_nftables` Kconfig 符号。本仓 `common.seed` 写
`CONFIG_PACKAGE_nftables=y` 是幽灵符号 → `make defconfig` 静默删除
→ 6.5) 硬校验 `grep "^CONFIG_PACKAGE_nftables=y"` 必然失败。

`kmod-nft-bridge` 实证存在（`package/kernel/linux/modules/netfilter.mk`
的 `define KernelPackage/nft-bridge`，`$(eval $(call KernelPackage,nft-bridge))`），
无需改。循环是先查用户态，所以只报了 nftables 一条。

**这次失败是好事**：第 5 轮加的「防假防护」硬校验在真编译里第一次生效，
拦下了一个镜像里没有 `nft` 命令、无线侧 DHCP Snooping 会完全空转的固件。

### 修复

1. `config/common.seed`：`CONFIG_PACKAGE_nftables=y`
   → `CONFIG_PACKAGE_nftables-nojson=y`（默认变体，不带 `jansson`，**占用更低**）。
2. `config/gen-config.sh` 6.5)：接受 `nftables-nojson` / `nftables-json` /
   `nftables` 任一 `=y`（兼容旧树）；全缺时打印 `.config` 里实际
   `CONFIG_PACKAGE_(nft|kmod-nft)` 行；成功日志改为
   `[gen-config] 二层防护 OK：nft=nftables-nojson + kmod-nft-bridge 均已进 .config`。
3. `scripts/verify.sh` 新增 `[4.12/9]` 9 条断言（禁裸幽灵符号回归）。
4. README / 修复总览 / 交付核对规范 / 规格日志同步；
   `docs/DHCP与SSH防护.md` 口径对齐。

### 线上仓库状态（clone 实证）

`git clone` 当前 HEAD `11ad569`（*Expand wireless controls and NAND workflow*，
2026-11-28 21:21 +0800）逐文件比对：`common.seed` 与本地一致，
但 `gen-config.sh` / `verify.sh` / `baseline.env` / `README.md` 仍是 **r21** 状态
→ **r22 的 NSS 包名修复没上线**。所以本次增量包基于 r21，
一次补齐 **r22 + r23 全部改动**（含 NSS 5 个实证包名与缺包停编）。

### 本地 mock 真跑（模拟 defconfig 删除幽灵符号）

| 场景 | 结果 |
|---|---|
| r23 + NSS=0（默认 official-25.12） | `二层防护 OK：nft=nftables-nojson ...`、`RESULT: OK ... nss=0 nss_pkgs=0/0` |
| r23 + NSS=1（qosmio） | `5/5` NSS 包 + `nft=nftables-nojson` 同时通过 |
| 改回 r21 裸 `nftables=y` | `rc=1`，`::error::nft 用户态未进 .config ... 裸 CONFIG_PACKAGE_nftables=y 是幽灵符号` |

刷机后核对：`/etc/init.d/l2-guard status` 应显示「已生效」；
`nft list table bridge nwrt_l2guard` 能看到 `udp sport 67` 规则。
