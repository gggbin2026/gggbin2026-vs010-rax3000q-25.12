# FIRMWARE.md —— 出厂默认 / 刷机 / 排障

## 一、两种固件六处区分

| 区分点 | WDS 网桥 | 普通 AP |
|---|---|---|
| 文件名 | `Nwrt-WDS-<内核>-<日期>-<机型>-*` | `Nwrt-AP-<内核>-<日期>-<机型>-*` |
| Release tag | `fw-<内核>-时间戳-<机型>-wds` | `fw-<内核>-时间戳-<机型>-ap` |
| 管理地址 | 主 `172.10.10.241` / 备 `172.10.10.242` | `172.10.10.241` |
| SSID | 5G `WDS_AP`（4addr）/ 2.4G `BRIDGE-SETUP` | `NwrtAP-2G` / `NwrtAP-5G` |
| hostname | `<机型>-WDS` | `<机型>-AP` |
| 状态页 | `/bridge/`（主备 / 机器狗 / 端口 / 仪表盘 / 温度 / NSS） | `/ap/` + `/bridge/` 简版 |
| 本机 DHCP | 主开备关（1h 租期） | **关**，地址由上级分配 |

内核版本取自 `make -s kernel_version`，例：`Nwrt-AP-6.12.116-20261124-vs010-...`。
**不再使用任何旧 SDK 编号前缀。**

`cat /etc/firmware_mode` 看模式；`uname -r` 看实际内核；`cat /etc/build-info` 看编译记录。

## 二、出厂默认（两台一样）

- 账号 `root` / `admin`，SSH 22 开（`dropbear`）；**TTYD `http://<管理IP>:7681`** 开
- **WAN + LAN + 2.4G + 5G 全在 `br-lan`**：DSA `list ports lan1 lan2 lan3 wan`，纯二层，无 NAT/路由
- `2.4G` band 2g / ch1 / HE40（`noscan=0`），`5G` band 5g / **ch36 / HE160 / country CN**
- LuCI：`/cgi-bin/luci`，中文 `zh_cn`，**默认 `bootstrap`**（官方 feed 唯一确定性主题）；
  编了 argon 时由 `luci-fix` 开机按实际目录自动切过去，主题下拉只列真实存在的主题
- 开机自修链：`luci-fix`(18) → `bridge-netfix`(21) → `l2-guard`(22) →
  `wifi-fullspeed`(24) → `bridge-role`(99) / `ap-rssi-guard`(96，默认停用) /
  `bridge-watchdog`(95)
- **关闭防火墙**：`firewall4`/`firewall` 编译期 n，运行期 stop+disable，
  `/etc/config/firewall` 清空，flow_offloading 关闭
- **无线端 DHCP 防护**：独立 nft bridge 表 `nwrt_l2`
- 自检：`health-fix`、`wifi-fullspeed`、`wifi-bdf-check`、`wifi-heal`、
  `l2-guard status`、`bridge-watchdog status`

## 三、包清单（最稳，只留必要）

| 类别 | 包 |
|---|---|
| 必留 | `dropbear`、`ttyd` + `luci-app-ttyd`、`luci-base`、`luci-i18n-base-zh-cn`、`luci-mod-{admin-full,network,status,system}`、`uhttpd`/`cgi-io`/`rpcd-mod-*` |
| 主题 | `luci-theme-bootstrap`（官方 feed）。`argon`/`footstrap` 为社区主题，默认不编 |
| 无线 | `ath11k-firmware-ipq5018-qcn6122`、`kmod-ath11k-{ahb,pci}`、`iw`/`iwinfo`/`wireless-regdb`、`wpad-basic-mbedtls`、本地 `ipq-wifi-cucc_vs010` |
| 网络 | `dnsmasq`、`bridge`、`ethtool`、`nftables` + `kmod-nft-bridge`（仅二层防护） |
| **不编** | `firewall4`/`firewall`/`odhcpd-ipv6only`、所有第三方 `luci-app-*`、adblock/sqm/wireguard/statistics/dashboard/librespeed、smartdns/https-dns-proxy、`iperf3`/`htop`/`nano`/`curl`/`wget-ssl`、`material`/`edge` |

`verify.sh` 硬校验 `luci-app-*` 只能有 1 个（ttyd）。

## 四、无线加速：正确口径与实测

### 判据（参考 mufeng05/openwrt-cmcc-pz-l8-nss）

| 项 | 正确做法 | 之前写错/已修 |
|---|---|---|
| NSS 固件 | **12.5 优先**，12.2 仅回退（自测 +65%） | 旧文档把 12.2-156 写成默认 |
| 加速路径 | **ECM→NSS + `wifili` 双射频卸载** | 把 `nss.general.wifi_offload=1` 当通用总开关 |
| UCI 配置 | 只有 c3po 基线确有 `nss.general.wifi_offload` 时才拉回 1 | 无条件 `uci set` 会凭空造 `/etc/config/nss` |
| SFE | `shortcut_fe` 连接表为空属预期（平台缺 3 个钩子） | 把它当加速项报告 |
| 判速 | **eth0/eth1 + `cpu_load_ubi` + `connection_count`** | 用 `br-lan` 计数判断「没加速」 |
| 温度 | CPU=thermal `type` 含 cpu；射频=`ath11k_hwmon`，按设备树节点 | 按 `phy` 编号命名（wifi reload 后会变） |
| 板级 | `DEVICE_PACKAGES` 必须含 ath11k 固件 + board data | 官方 25.12.x `Device/cmcc_pz-l8` 缺此定义，射频不 probe |

**实测参考（非本板保证值）**

| 场景 | PZ-L8 参考仓 | 社区其它 |
|---|---|---|
| 有线 LAN↔WAN | 949 / 949 Mbps @ +0% 主机 CPU | qosmio M79 940 / 939 Mbps |
| 5G 160MHz | 697 Mbps（四路 HTTP）@ 2.9% CPU | kuncy7 AX55 915 Mbps、CPU 1~3% |
| 5G 80MHz | 462 Mbps | — |
| 2.4G 20 / 40MHz | 75 / 112.5 Mbps（noscan） | — |
| 原生 OpenWrt DSA | 502 Mbps @ 100% 双核 | — |

**纯二层桥的如实边界**：被 NSS 卸载的流量根本不经过 Linux 网桥（参考仓实测 eth0/eth1
各 989 Mbps 时 br-lan 只有 52）。本仓仍按你要求保持 WAN+LAN 同桥，所以状态页把
`br-lan` 只当拓扑展示，**判速一律用 eth0/eth1 + NSS debugfs**；`l2-guard` 也因此在真
offload 下属尽力防护，见 `docs/DHCP与SSH防护.md`。

### 五件套与两条固有代价

`NSS FW 12.5` · `ECM→NSS/wifili` · `CN` · `5G ch36 HE160` · 本机 BDF + `256M LOW`

- **CN + HE160 覆盖 DFS**：开机 5G 约 **60 秒 CAC** 期间不可见，2.4G 先起；
  `uci set wireless.radio1.htmode=HE80` 可免等，吞吐少约 1/3。
- **2.4G HE40 默认退 20MHz**（共存扫描）；`uci set wireless.radio0.noscan=1` 强开 +50%，
  但无视邻区，默认关闭。2.4G 速率停在 MCS 6–7 是邻区丢包导致，不是配置 bug。
- 世界域（country 00）下 5G 被切成两段、无 160MHz 信道，radio1 会悄悄退回 80MHz。

**BDF**：`vs010/bdf/board-cucc_vs010.*` 是单个 BDF，不是 `board-2.bin` 容器。按
`board/README.md` 合成/解包出 `vs010/bdf/board-2.bin` 放进仓库即自动装配；没有就保留
官方通用 `board-2.bin`（射频能起，校准不一定满血）。直接改名单 BDF 会读错校准。

## 五、刷机

| 机型 | 首刷 | 系统内升级 |
|---|---|---|
| RAX3000Q / QY | 不死 U-Boot Web 刷 `*-factory.ubi` | `sysupgrade -n *-sysupgrade.bin` |
| VS010 | 原厂 Web API 需 `.img`，或 TTL+U-Boot TFTP 刷 `factory.ubi` | `sysupgrade` |

VS010 Web API：`POST /api` 取 stok → `POST /api/;stok=TOKEN/admin/advance/upgrade`，
字段 `file` + `size`，格式 `.img`（`board-inject.sh` 保留 `qsdk-ipq-factory-nand`）。
TTL：VS010 UART GPIO28/29，115200 8N1，3.3V。

**刷前确认 64 位不死 U-Boot**；首次一定接串口。

> 补充：参考仓提到 PZ-L8 有 V2 批次用复旦微 FM25LS01 SPI-NAND（ID 0xA5），主线 25.12.5
> 不认，需要 `440-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch`。本仓两台机器
> 暂未发现该批次差异；若你的板子起不来且 dmesg 报闪存 ID 未知/EUCLEAN，先查这一条。

## 六、必须知道的边界

1. **WDS 4addr 在开源 ath11k + NSS 下社区标 Unvalidated**：满速/信号优先用 **AP 模式**；
   WDS 两台桥不通时，若基线确有该 UCI 项才 `uci set nss.general.wifi_offload=0;
   uci commit nss; reboot` 回退，不要反复重编。TTL 看 `iw dev wlan1 station dump`、
   `brctl show`、`dmesg | grep -iE 'ath11k|nss|wds'`。
2. **NSS 卸载后部分报文不过 host bridge hook**，`l2-guard` 是尽力防护，不是硬件级 DHCP Snooping。
3. **官方 25.12.6 无 NSS 且不含 RAX3000Q**；要无线满速用默认 `qosmio-25.12-nss`。
4. 官方 PZ-L8 固件不要直接刷到 VS010（GPIO/ART/校准布局不同），本仓只借 DTS 与源码骨架。
5. Web 报 `dispatcher.lua:427` / 主题切换后 500 / 白屏：不是显示器也不是浏览器问题。
   串口 `sh /usr/sbin/health-fix`（或单跑 `luci-fix`），刷新即可，**不用重刷**。
   根因与四层兜底见 README「主题页面为什么不再报错」；`health-fix` 会逐项列出
   named main、mediaurlbase、每个主题目录是否存在、CGI 与 uhttpd 配置。
6. sysupgrade 勾「保留配置」时旧 overlay 可能盖掉编译期 `/etc/config/luci`/`uhttpd`，
   `files/etc/rc.local` 每 boot 兜底；极端情况再跑 `health-fix`。
7. 温度依赖 `thermal_zone*` / `ath11k_hwmon`；没暴露显示「—（无传感器）」，**不编造数值**。

## 七、主题页面 / LuCI 排障（老仓库高频问题）

| 现象 | 根因 | 一条命令 |
|---|---|---|
| `dispatcher.lua:427 unable to find section 'main'` | `/etc/config/luci` 被旧 overlay 盖成匿名 `config main` | `luci-fix` |
| 打开 LuCI 白屏、`/luci-static/argon` 404 | 编译期配置指向没编进去的社区主题 | `luci-fix` |
| 「系统 → 语言与样式」切主题后 500、再也进不去 | 下拉里列了不存在的 Argon/Footstrap | `luci-fix` |
| `/bridge/` 能开但数据全是「—」 | `uhttpd` 的 `cgi_prefix` 丢了 / CGI 非 755 | `health-fix` |
| 状态页扩展区提示「扩展数据未返回」 | CGI 报错，主页面与 LuCI 仍可用 | `health-fix` |

开机自修链（**每次冷启都跑，不依赖首启 uci-defaults**）：

```
luci-fix(18) → bridge-netfix(21) → l2-guard(22) → wifi-fullspeed(24)
```

`luci-fix` 做四件事：① 保证 `config core 'main'`；② 扫描
`/www/luci-static/` 下真实目录，重建 `config internal 'themes'`（清掉幽灵项）；
③ `mediaurlbase` 指向空气就落到真实主题；④ 清 `/tmp/luci-*cache`。
用 heredoc / awk 直接写文件，**绝不用 `uci set luci.main=...` 建段**（那正是 427 元凶）。

三个状态页是独立静态页 + 只读 CGI，**不经过 LuCI 主题**：LuCI 万一没起来，
直接开 `http://<管理IP>/bridge/`（WDS）或 `http://<管理IP>/ap/`（AP）即可，
页面底部也有指向 `/cgi-bin/luci` 的按钮。

要编 argon / footstrap：先在 `feeds.conf.default` 加对应第三方 feed，核对包名，
再把 `config/themes.seed` 里对应行改成 `=y`；**不要只改 `/etc/config/luci`**。
没加 feed 就写 `=y`，`gen-config.sh` 会显式关掉并打 warning，镜像仍只有 bootstrap。

## 八、ART / 本机校准（默认不启用，只读可查）

两份完整 `0:ART` 已离线采集：VS010 `010-smem_0-ART.bin`、RAX3000Q
`RAX3000Q-mtd13-0ART`，都是 1 MB 完整分区，有效数据在前 256 KB。
真值 `art/art-truth.conf`，完整报告 **[docs/ART与无线校准.md](docs/ART与无线校准.md)**。

| | VS010 | RAX3000Q |
|---|---|---|
| 整片 MD5 | `e6799786…` | `4f6f51ad…` |
| 头 MAC | 4 个单播 MAC（ART+0/+6/+0xC/+0x12） | 全 0xFF |
| 2G 切片 @`0x1000` | `26b9b9ad…` | `9a78b59f…` |
| 5G 切片 @`0x26800` | `dcf46e01…` | `ef733f2c…` |

**运行期**：`art-check`（或 `health-fix` 第 6 段）只读定位 `0:ART`、算整片与切片 MD5、
与 `/etc/art-truth.conf` 比对判定机型、列出头 MAC。不改 flash、不改配置。

**默认行为**：`ART_CALIBRATION=0`，固件用官方通用 `board-2.bin`，ART 完全不参与编译。
原因：`vs010/wifi-truth.conf` 实证信号正常的好固件报 `Caldata not present` 且双频正常，
改这条链路风险大于收益。`board-inject.sh` 只把**文本真值**放进 rootfs 供自检。

**想用本机产线校准（可选）**：按 docs 用 `art/make-board2.py` 切 BDF、把条目
**追加**到官方容器（保留兜底），产物放 `art/out/<机型>/board-2.bin`，
再显式 `ART_CALIBRATION=1` 编译。单个 BDF 直接改名会被签名校验拦下停编，
因为 `board-2.bin` 是 `QCA-ATH11K-BOARD` 容器，不是裸 BDF。
`qmi-board-id` / `variant` 必须以实机 `dmesg` 与树内 DTS 为准，别猜。
回退：删掉对应 `board-2.bin` 重编即可。

**RAX3000Q 两个已修的点**：`board-inject.sh` 现会探测并补齐 `DEVICE_PACKAGES`
（缺 ath11k 固件/board data 射频不 probe）；ART 头全 FF，`art-check` 会提示
从 `0:appsblenv` / 机身标签取 MAC 并用 `uci set wireless.default_radio*.macaddr=` 固化，
不自动写。

> ⚠ 产线校准逐台独立，只用于你这台；别跨机刷、别外传这两份 ART。

## 九、NAND 补丁（V2 批次，默认不启用）

补丁原文已放进 `patches/440-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch`
（来自 `mufeng05/openwrt-cmcc-pz-l8-nss` → `CrazyBoyFeng/openwrt-pz-l8`，未改一字），
应用逻辑在 `scripts/apply-nand-patch.sh`，完整风险说明见 **[patches/README.md](patches/README.md)**。

**默认不打。** 它只针对 PZ-L8 **V2 批次**的复旦微 FM25LS01（ID `0xA5`），
替代 V1 的 ESMT F50D1G41LB；VS010 原厂是 ESMT，RAX3000Q 闪存型号未实证。
补丁声明 `NAND_ECCREQ(8,512)` 而数据手册是 `1-bit/512`——QPIC 按声明值配硬件 ECC，
与 U-Boot 写入时不一致就读不出 UBI（`-74 EUCLEAN`）→ 变砖。上游自己也只验证到
「干净应用、能编过」，**没有在真 FM25LS01 上跑过**。

**但 U-Boot 侧已有实证**：用户上传的两份 640 KB U-Boot strings 名称表里同时有
`F50D1G41LB(2M)`（ESMT V1）与 `FM25LS01` / `FM25LS02BI3`（复旦微 V2），
说明 V2 批次真实存在、U-Boot 认这颗芯片 → Linux 侧补丁对 V2 **必需**。
判断批次：TTL 看 U-Boot 打印的 `flash_type / flash_index / flash_density`，
或 `dmesg | grep -iE 'qpic|spinand|flash id'`，报 `unknown flash ID 0xA5` 即 V2。

**Run workflow 时勾 `nand_patch` 才生效**，且仍要过三道门：

1. 基线是 6.12（`qosmio-25.12-nss` / `official-25.12.6`）；`kuncy7-6.18-nss` 自动跳过
2. 树里有 `drivers/mtd/nand/spi/fmsh.c`（它本身由 OpenWrt backport 401/435 加入）
3. `git apply --check` 通过，且尚未含 `FM25LS01`（幂等）

任何一道不满足**只警告、不停编**，内核保持干净树；结果写进 `build.env` 的
`NAND_PATCH=` 行。刷完看 dmesg，出现 EUCLEAN 立刻关掉重编。

> 什么时候才开：TTL 看到 `unknown flash ID 0xA5` / EUCLEAN，且确认板子是 V2 批次。
> 回退：不勾 `nand_patch` 重编即可。

## 十、编译失败怎么定位

- Actions 上传完整 `build.log` artifact；两份 workflow 都会打印失败摘要。
- 本地先 `sh scripts/verify.sh`：命名带内核、12.5、温度口径、NSS 字段、精简包、防护、板级、BDF。
- 常见：`DEVICE_*` 符号拼错 → `make defconfig` 丢设备；`ipq-wifi-cucc_vs010` 本地包未生成 →
  检查 `board-inject.sh` 是否先跑；`luci-theme-*` 包名不存在 → 检查 feeds；
  apk 依赖缺失 → 重跑 `./scripts/feeds install -a`。

## 十一、闭源好固件取证（第 41 次，2026-11-24）

两个 27 MB `Nwrt-QSDK12.2-2024-04-16-*-squashfs-nand-factory.bin` 已从
`Actions-OpenWrt-RAX3000Q-VS010-WDS / 3000Q-VS010-固件` 解开。完整报告见
**[docs/OEM-QSDK12.2-取证报告.md](docs/OEM-QSDK12.2-取证报告.md)**，真值见
`vs010/oem-qsdk-truth.conf` / 运行期 `/etc/config/oem-qsdk-truth.conf`。

| 项 | 值 |
|---|---|
| 内核 / 发行版 | **5.4.213** / OpenWrt 19.07-SNAPSHOT r0-f3013a33b |
| WiFi FW | `WLAN.HK.2.8-01492-QCAHKSWPL_SILICONZ-1 v1` |
| 无线栈 | `qca_ol / umac / wifi_3_0 / qdf / ipq_cnss2 / cfg80211`，**无 ath11k、无 mac80211** |
| 真实 DTB | 2G `board_id` VS010 `0x10` / RAX3000Q `0x24`；5G 都是 `0x60`；`bdf-addr` `0x4C400000`/`0x4D300000`；`caldb-addr=0` |
| 有线 | `qcom,ess-switch-ipq50xx` + `qcom,ess-switch-qca83xx`；`/soc/dp1` + `/soc/dp2` 双 GMAC |
| 加速 | `ecm acceleration_engine=auto`；`nss enable_rps=1` + `nss_queue1/2/3 → CPU 2/4/8`；`qcacfg80211 enable=1` |

**能不能拿文件过来加速：不能。** 好固件 5.4.213 闭源栈 vs 本仓 6.12 主线 ath11k，
vermagic / 导出符号 / cfg80211 ABI 全不匹配；`.ko` 会 `Invalid module format`；
`q6_fw.*`/`m3_fw.*` 与主线 `amss.bin`/`m3.bin` 格式不同；`bdwlan.b10/b60` 单 BDF
不是 `QCA-ATH11K-BOARD` 容器。四套 BDF（好固件两台、本仓模板、4.4.60、ART 切片）
MD5 互不相同 → 也没有哪份能证明「就是本仓该用的那份」。

**能用的是口径，本仓已落地**：ECM→NSS 卸载、qca-ssdk 双 GMAC、NSS FW 12.5 优先、
wifi_offload、不加载独立 caldata、判速看 `eth0/eth1 + NSS debugfs` 不看 `br-lan`。

串口跑 `oem-stack-check`（`health-fix` 第 7 段会自动调）可只读核对：
有没有误塞 QSDK `.ko` / 单 BDF / caldata、NSS/ECM 是否加载、加速判速提示。

**要真达到好固件那种满速**：① 直接用 NWRT 官方固件；② 取得 QSDK 12.2 OEM 授权
换 target 重编；③ 在 6.12 主线按 NSS/ECM 口径继续调。**不要往 6.12 塞 5.4 闭源件。**

> 提取出的 4 份 BDF + `regdb.bin` + `fw_version.txt` 在 `art/oem-qsdk-bdf/`，
> **只读存档、不参与编译、不跨机使用**。

## 十二、第一次编译日志复盘与后续关卡（第 43 次）

第一次 `Run workflow` 的两个 job 都挂在 Prepare 步的自检：

```
✗ .gitignore 缺末尾 3 行 → RESULT: FAIL (1 项) → exit 1
```

`sh scripts/verify.sh` 在 `set -euo pipefail` 里返回非 0，后面的 `prepare.sh` 完全没执行，
所以 **没有 `git clone` / `feeds update` / `make`，也没有 `openwrt/build.log`**。
这属于 CI 自检把纯卫生项当硬失败，不是固件编译错误。

**修复**：`verify.sh` 分级（纯文档/命名/卫生项降为警告，真阻断项才 `exit 1`）；
`.gitignore` 补回 `openwrt/` / `firmware_out/` / `build.log` 三行。

**但只补这三行仍不够**——在真实 qosmio 25.12-nss 树上预检发现两道必停编的关卡：

| 关卡 | 现象 | 第 43 次修复 |
|---|---|---|
| DTS 布局 | 25.12 把 dts 放在 `qualcommax/files/arch/arm64/boot/dts/qcom/`，旧脚本报「不是 ipq50xx 源码树」 | 新增 `qualcommax-files` 布局；`02_network` 锚点兼容 `pz-l8|` |
| RAX3000Q 板级 | 该树 `rax3000q` 0 命中，`ipq50xx.mk` 无 `Device/cmcc_rax3000q` | 新增 `board/ipq5018-rax3000q.6.12.dts` + 编译期注入设备定义；`baseline.env` 断言纠正 |

真实树上实测：两台 `board-inject.sh` 都成功、Device/DTS/`02_network` 都注入、`sh -n` 通过。
`make defconfig` 的完整结果未在沙盒验证（本机是 `mawk`，OpenWrt 需要 `gawk` 的 `asort`；
Actions 已装 gawk），`gen-config.sh` 已加对应检测与排错提示。

⚠ **RAX3000Q 板级未在 6.12 实机验证**：按同芯片 PZ-L8 骨架 + 好固件 FIT DTB 的
`model="CMCC RAX3000QY"` / `compatible="cmcc,rax3000qy"` 融合；为避免悬空 GPIO 误进
failsafe，DTS **不定义 keys/leds**；ART 头全 FF，**不引用 nvmem macaddr**，MAC 按机身标签
用 `uci` 固化。首次刷务必 3.3V USB-TTL，建议先 `device=vs010` 单编验证编译链。

详见 **[docs/编译链预检与板级缺口.md](docs/编译链预检与板级缺口.md)**。

## 十三、第 44 次板级真值校正（DTS / DTB 取证）

用户上传的 `docs/oem-dts/vs010.dtb`（原厂运行态 FDT）与
`docs/oem-dts/ipq5018-rax3000q.MAIN.dts`（OpenWrt main 逐字节官方原文）
给出了两台**不同的**硬件真值，本仓不再两台共用一套 PZ-L8 推断值：

| 项 | VS010 | RAX3000Q |
|---|---|---|
| 按键 | 仅 WPS GPIO34，**无 reset** | reset GPIO23 / mesh GPIO38（**本仓故意不定义**） |
| LED | mesh GPIO33 + pwr GPIO31（低有效） | 红24 / 绿19 / 蓝17（**故意不定义**） |
| NAND ECC | **4 bit / 512** | **8 bit / 512**（GD5F1GQ5REYIG） |
| QCA8337 | 排序待实机核对（本次不改） | **PHY0=WAN、PHY1/3/4=LAN1/2/3**，单条 SGMII CPU 链路 |
| 5G bdf-addr | 原厂 0x4d300000（**不照抄**，主线骨架 0x4d100000） | 0x4d100000 |

⚠ **刷前必读**：核查报告记录 2026-04-25 一例 VS010 刷 CMCC RAX3000Q 的
U-Boot/大分区后，因复位键 GPIO 不一致循环重启、TTL 失联、最终需编程器。
**VS010 绝不刷 CMCC 机型的 U-Boot / MIBIB / 大分区包**；刷前至少备份
`0:MIBIB`、`0:APPSBLENV`、`0:APPSBL(_1)`、**`0:ART`(1 MiB，校准+MAC 不可再生)**、
`0:TRAINING` 及 BOOTCONFIG/DEVCFG/CDT 三对。

刷后若某个网口不通，上级线逐个换口（VS010 端口 label 待实证）；
若 LuCI 操作 OOM，官方因 256 MiB 关 WiFi，社区做法是 `ath11k-smallbuffers` +
zram（报告建议，未在两台实机验证）；若报 `unknown flash` / `-74 EUCLEAN`，
按本机闪存型号核对 DTS 里两行 `nand-ecc-*`。

详见 **[docs/板级真值-第44次.md](docs/板级真值-第44次.md)**，
原始 7 份资料在 **[docs/oem-dts/](docs/oem-dts/README.md)**（只读，不进编译链）。

## 十四、第 44 次配置收口：IPv6 关闭 · DHCP 防护 · 插件精简

用户这次把边界又说了一遍，逐条落成**编译期 + 运行期双层**，不是只写文档：

| 要求 | 状态 | 落地 |
|---|---|---|
| **无线 DHCP Snooping 是否开启** | ✅ **默认开启** | `files/etc/config/l2guard` 的 `option enabled '1'`，开机 `l2-guard` 建独立 `nft bridge` 表，只丢无线口 `wlan* / phy*-ap*` 进来的 **67→68（DHCPv4 Offer/ACK）** 与 **547→546（DHCPv6）**；有线侧上级 DHCP 正常透传 |
| 插件只留 TTYD | ✅ | `common.seed` 里 `luci-app-*` **只有 `luci-app-ttyd` 一个**（`verify.sh` 硬校验）；SSH=`dropbear`；LuCI 模块/中文/bootstrap 属底座不算插件，其余第三方/统计/科学/下载工具全部显式 `n` |
| 防火墙关闭 | ✅ | 编译期 `firewall4` / `firewall` 显式 `is not set`；运行期 `99-no-firewall` stop+disable、清空 `/etc/config/firewall`、关软/硬 flow offload |
| **IPv6 关闭** | ✅ **本次新增** | 编译期 `CONFIG_IPV6=n` + 不编 `odhcpd/odhcpd-ipv6only/odhcp6c/luci-proto-ipv6/ip6tables`（`gen-config.sh` 兜底再写一遍）；运行期新增 `99-no-ipv6`：sysctl `disable_ipv6=1`、清 ULA / RA / DHCPv6 / wan6、停 odhcpd |
| WAN + LAN 一个桥 | ✅ | `port-overlay.sh` 生成 `config device 'br_lan'` + `list ports lan1 lan2 lan3 wan`；2.4G/5G 也进 `br-lan`，纯二层、本机 DHCP 关 |
| 尽量少占资源 | ✅ | 不编 firewall4 / odhcpd / IPv6 协议族工具 / 任何第三方插件；状态页是独立静态页 + 只读 CGI，不依赖 LuCI 主题 |

⚠ **如实说明「DHCP Snooping」这个词**：本仓开的**不是** IEEE 标准 DHCP Snooping（不维护 binding 表、不做 trust/untrust 端口分级、不占额外守护进程），而是等价目标的**轻量二层过滤**——只拦无线侧冒充 DHCP 服务器的报文。真端口级 snooping 需要 QCA8337/NSS 数据面支持；且 NSS wifi_offload 下部分射频报文不过 host bridge hook，属**尽力防护**。边界见 `docs/DHCP与SSH防护.md`。
关闭 IPv6 后，`l2-guard` 若发现内核不接受 DHCPv6 匹配行，会**自动降级为仅拦 IPv4**，绝不因为一行规则把整张表丢掉。

## 十五、第 45 次：编译失败修复 + 机器狗默认停用

**编译为什么失败**：13:54 两份 WDS 日志都是 `exit code 2`，但 `make download` / `make` 根本没跑、
`build.log` 不存在。根因是 Prepare 步骤里探测内核版本那行调用了 make 的一个目标，
在 `set -euo pipefail` 下返回非 0 就静默终止（错误还被 `2>/dev/null` 吞了）。
现在改成**纯读源码树**：`KERNEL_PATCHVER` + `LINUX_VERSION-<主版本>` 拼接，带兜底，绝不调用 make。
日志里满屏 `recursive dependency detected!` 是 qosmio feed 里 dnsdist/snort3 等包的
Kconfig 告警，`make defconfig` 最终 `No change to .config` 且成功，**不是失败原因**。

顺带修掉日志里 `luci-app 数量: 0（只应为 ttyd）`：`gen-config.sh` 旧探测把
**`luci-app-ttyd` 和 `ath11k-firmware-ipq5018-qcn6122` 当成「feed 里没有」删掉了**
（feeds install 明明装了）。现在必需包永不自动删，只对主题类做存在性剔除。

**★ 机器狗（bridge-watchdog）在第 45 次默认停用** —— 第 49 次已按用户要求恢复 WDS 启用，详见后文「第 49 次」。

旧默认 `enabled=1 / delay=5 / grace=6` + 首启 `enable+start`：单机、无对端 WDS、
或只当有线网桥时，开机约 **6+5≈11 分钟**就 `reboot -f`，之后每个周期反复重启，
连 SSH 排障窗口都没有。现在：

| 层 | 值 |
|---|---|
| `files/etc/config/wdsdog`（WDS）/ `files.ap/etc/config/wdsdog`（AP） | `enabled '0'` |
| WDS 基底 `dryrun` | `'1'`（双保险，即便被手动 on 也先只记日志） |
| WDS 首启 `99-bridge-ready` 7c 段 | `stop + disable`，并 `uci set wdsdog.main.enabled=0`（防 sysupgrade 保留配置带回旧值） |
| `/usr/sbin/bridge-watchdog` 代码缺省 | `enabled 0` / `dryrun 1`（配置文件丢失也不回落成自动重启） |
| 脚本与 init.d | **完整保留**，成对 WDS 部署可手动启用 |

成对部署真要用时：
```sh
bridge-watchdog set-peer 172.10.10.242   # 先设对端，ping 判通最准
bridge-watchdog set-delay 10             # 或延长触发时间
bridge-watchdog on                       # 启用（dryrun=1 仍只记日志）
bridge-watchdog dryrun off               # 观察一两天确认不误重启，才真启用
```

刷机动作本身仍会**正常重启一次**（原厂 Web API 返回 `isreboot=1`），这是刷机流程自带，不是故障；
开机之后不会再无故重启。

## 十六、第 46 次：编译链已跑通，卡在上游树自带坏 DTS

第 45 次的修复**已生效**：日志里能看到 `[prepare] 实际内核版本 = 6.12.91`、
`luci-app 数量: 1（只应为 ttyd）`，`make` 完整跑了约 48 分钟并生成了 `build.log`。
这次不是 Prepare 也不是配置问题，是 `target/linux/install` 阶段编 DTB 失败：

```
Error: ipq5018-nss.dtsi:118.1-7 Label or path wifi0 not found
FATAL ERROR: Syntax error parsing input tree
make[5]: *** [image-ipq5018-wrc-x3000gs2.dtb] Error 1
make[5]: *** [image-ipq5018-gl-b3000.dtb] Error 1
ERROR: target/linux failed to build.
```

qosmio 25.12-nss 树自带的 `ipq5018-nss.dtsi` 引用 `&wifi0`，但整棵树根本没有
`wifi0:` label（只有 `wifi:` / `wifi1:` / `wifi2:`）。树自带的两台设备
（ELECOM WRC-X3000GS2、GL.iNet GL-B3000）的 DTS include 了它，编 DTB 必炸；
而 OpenWrt 会为 `ipq50xx.mk` 里**所有** `TARGET_DEVICES` 编 DTB，不管你选了哪台，
于是把整个编译拖垮。

**修复**：`board-inject.sh` 现在会把 `ipq50xx.mk` 里非白名单的
`TARGET_DEVICES +=` 行注释掉，只保留 `unicom_vs010` 和 `cmcc_rax3000q`
（备份为 `ipq50xx.mk.orig46`）。我们这两台的 DTS 与能编过的 PZ-L8 同款 include，
都不碰 nss.dtsi，所以只编自己的 DTB 即可通过，还少编 13 个无关 DTB。

NSS 有线/无线加速依赖 `qca-nss-drv` / `ecm` 内核模块与 NSS 固件包，**不依赖**
这段 dtsi；裁掉不影响加速，也不改动任何上游源码文件。

刷前边界不变：64 位不死 U-Boot 是硬门槛、VS010 绝不刷 CMCC 机型的
U-Boot/MIBIB/大分区、刷前备份 `0:ART`(mtd13) 与 `0:TRAINING`(mtd14)、
RAX3000Q 板级未在 6.12 实机验证首次务必 3.3V USB-TTL。

## 十七、第 47 次：SSH 可达性 / 内网 NTP / 删 WAN / STP / 干净系统

**SSH 配置本身完全正常**（`0.0.0.0:22`、`root/admin`、密码/根登录全开、四层开机兜底），
但逐文件核验发现首启 `99-bridge-ready` 与 `bridge/role.sh` 里还留着 21.02 老兜底：
删掉所有 `config device` 段 + 写 `lan.type=bridge / ifname=eth0 eth1`。
25.12 DSA 下这会让 `br-lan` 建不出来 → **管理 IP 消失 → SSH / LuCI / TTYD / NTP 全连不上**。
本次把三处改成 DSA 原生写法并加防呆，这是本轮最关键的修复。

配置现状（编译日志 + 端到端模拟实证）：

| 项 | 值 |
|---|---|
| 登录 | `root / admin`（刷完请 `passwd` 改掉）；SSH :22 / LuCI :80 / TTYD :7681 |
| 插件 | 仅 `luci-app-ttyd`；LuCI 底座 + 中文 + bootstrap，无任何第三方 `luci-app-*` |
| 无线 DHCP 防护 | `l2guard enabled=1 / dryrun=0`，独立 nft bridge 表，含 DHCPv6 |
| 防火墙 / IPv6 | 编译期 + 运行期双层关闭 |
| wan / wan6 | 三层接口已删（五处）；**物理 WAN 口仍在 br-lan 的 `list ports 'wan'`**，WAN+LAN 同桥 |
| NTP | 只当客户端：`192.168.1.254` / `172.10.10.254`，`enable_server=0 / use_dhcp=0`，无公网源 |
| STP | `config device 'br_lan'` 的 `option stp '1'`（DSA 下必须写 device 段） |
| 资源 | 停用 cron / ucitrack / led / gpio_switch；`packet_steering` 保留（非 NSS 基线需要） |
| 日志 | CI 默认 `V=0` 静默 + 精准失败摘要（可勾 `build_verbose` 看详细）；运行期 log buffer 32KB、banner 12 行 |

**NTP 与 /22 网段**：管理地址改为 `172.10.10.241 / 255.255.252.0`
（`/22` = `172.10.8.0 ~ 172.10.11.255`）。NTP 源 `172.10.10.254` 就在本网段，
二层直连可达，**不需要任何路由**；另一个源 `192.168.1.254` 跨网段，纯二层桥
没有默认网关时不可达，但 busybox ntpd 以多个 `-p peer` 启动，一个不通会自动
用另一个，不影响校时。第 47 次那条 `config route 'ntp172'`（`172.10.10.254/32
via 192.168.1.254`）已删除——目标本来就在 /22 内，而 `192.168.1.254` 不是
同网段网关，netifd 会拒绝该路由。若确实要让 `192.168.1.254` 也可达，在
`/etc/config/network` 里取消 `config route 'ntp192'` 注释，把 `gateway` 改成
**本网段内**的实际网关（例如 `172.10.10.1`），再 `/etc/init.d/network restart`。


刷前边界不变：64 位不死 U-Boot 是硬门槛、VS010 绝不刷 CMCC 机型的 U-Boot/MIBIB/大分区、
刷前备份 `0:ART`(mtd13) 与 `0:TRAINING`(mtd14)、RAX3000Q 板级未在 6.12 实机验证首次务必 TTL、
WDS 机器狗默认启用（5 分钟 / 3 次上限），AP 模式仍停用。

## 第 48 次：管理网段统一 172.10.10.241 / 255.255.252.0（2026-11-25）

**所有设备、两种模式、两台机型的管理 IP 统一为 `172.10.10.241`，掩码 `255.255.252.0`**
（`/22`，网络 `172.10.8.0 ~ 172.10.11.255`）。覆盖 28 个文件：network 源文件、
首启兜底、CGI、状态页、banner、`bridge-ap`、Release NOTES 与全部说明文档。

| 项 | 值 |
|---|---|
| AP / WDS 主 / VS010 / RAX3000Q | `172.10.10.241` / `255.255.252.0` |
| WDS 备机（唯一例外） | `172.10.10.242`，仅成对部署时由 `bridge-role` 自动顺延，防 ARP 冲突 |
| PC 直连调试 | 设 `172.10.10.10/22` → `http://172.10.10.241` |
| 链路本地兜底 | `169.254.240.1/16` 不变 |
| NTP 两源 | `192.168.1.254` / `172.10.10.254` 不变 |

⚠️ **两台机器（VS010 + RAX3000Q）若都刷 AP 且同时在线，会都是 `172.10.10.241` 而冲突**。
第二台刷后 SSH/串口改：`uci set network.lan.ipaddr='172.10.10.243'; uci commit network; /etc/init.d/network restart`
（或任意 `/22` 内未占用地址）。WDS 成对部署不受影响，备机自动 `.242`。

⚠️ **第 47 次的 `config route 'ntp172'` 已删除**：`/22` 下 `172.10.10.254` 同网段二层直连，
而 `192.168.1.254` 不是同网段网关，netifd 会拒绝该路由。纯二层桥无默认网关时
`192.168.1.254` 不可达，但 busybox ntpd 多 `-p peer`，会自动用可达的
`172.10.10.254` 校时，不影响功能。需要两个源都可达时，在 `/etc/config/network`
取消 `config route 'ntp192'` 注释，把 `gateway` 改成本网段内实际网关后
`/etc/init.d/network restart`。

其余配置（SSH :22 / TTYD :7681 / LuCI :80、无线 DHCP 防护、防火墙与 IPv6 关闭、
删 wan/wan6、WAN+LAN 同桥、STP、NTP 客户端、WDS 机器狗按第 49 次口径、简洁日志）全部不变。

## 第 49 次：机器狗恢复启用 + 时间可自定义 + 防误重启/防无限重启（2026-11-25）

> 用户问：「机器狗是不是被删了？网桥还是要机器狗，5 分钟不通自动重启；
> 能不能改成我自定义时间？怎么保证它不乱重启？是不是要互相 ping IP？」

### ① 没删，文件一直都在

`/usr/sbin/bridge-watchdog`、`/etc/init.d/bridge-watchdog`、`/etc/config/wdsdog`、
首启 `99-bridge-ready` 的启用链、状态页机器狗面板，**一个都没删**。
第 45 次只是把 WDS 默认从 `enabled=1` 改成 `0`（外加 `dryrun=1`、首启 stop+disable、
代码缺省也改成安全值），原因是你当时实测「刷机后约 11 分钟自动重启」。
第 49 次按你要求**恢复 WDS 默认启用**，但不是简单改回 `1`，而是补齐三条防误伤机制。

### ② 出厂值（WDS 网桥）

| 项 | 值 | 含义 |
|---|---|---|
| `enabled` | `1` | WDS 网桥默认启用；**AP 模式仍 `0`**（刷 AP 不会自动重启） |
| `delay` | `5` | 连续不通 **5 分钟**才 `sync; reboot -f` |
| `grace` | `6` | 开机宽限 6 分钟，等 ath11k 校准 + 主备收敛；这段可从容 SSH 改配置 |
| `interval` | `30` | 每 30 秒检查一次 |
| `mode` | `or` | 三条判据任一通即通 |
| `peer` | `auto` | 自动推导**对端**管理 IP |
| `anchor` | 空 | 可选额外锚点 |
| `max_reboots` | `3` | 连续重启 3 次仍不通 → 自动转 `dryrun=1` 停手 |
| `dryrun` | `0` | 真重启（调试可 `dryrun on`） |

### ③ 时间怎么自定义（两种，都不用重编）

**刷后 SSH / TTYD（推荐，立即生效、UCI 持久化）：**

```sh
bridge-watchdog set-delay 10        # 5 → 10 分钟（1~120）
bridge-watchdog set-grace 8         # 开机宽限
bridge-watchdog set-interval 60     # 检查间隔
bridge-watchdog set-max-reboots 5   # 重启上限
bridge-watchdog status              # 看当前配置 / 连续不通多久 / 距重启还剩多久
bridge-watchdog once                # 逐条检测一次，绝不重启
```

**编译期**：`build-wds.yml` 手动 Run 时新增两个输入框
`wds_delay`（默认 5）、`wds_peer`（默认 auto），`prepare.sh` 写进 UCI。
非法值（0 / 非数字 / >120）自动回落 5。

**临时不重启**：`bridge-watchdog dryrun on`（只记日志），恢复 `dryrun off`；
彻底关 `bridge-watchdog off`。开机 6 分钟宽限期内随便改。

### ④ 怎么保证「通的时候不误重启」

默认 `mode=or`，**三条判据任一通就算通**，计时立刻清零：

1. WDS 接口的无线关联（`iw link` 有 `Connected to` / `iw station dump` 有 `Station`）
2. ping **对端**管理 IP
3. ping 可选锚点（如 `172.10.10.254` 或上级网关）

另外：无线接口压根没注册 = 驱动未就绪，返回「未就绪」**不计故障、不重启**；
计时用 `/proc/uptime` 单调时钟，不受 NTP 跳变误判。

### ⑤ 是不是要互相 ping IP？——是 ping **对方**，不是 ping 自己

⚠️ **ping 自己的 IP（或 127.0.0.1）永远通，判不出桥断没断，没有意义。**
要 ping 的是**对端那台路由器的管理 IP**：主 `172.10.10.241` ↔ 备 `172.10.10.242`。

`peer=auto` 已经自动做了这件事：读 `/etc/bridge_role` 和本机 `network.lan.ipaddr`，
`ap`(主 .241) → ping .242；`sta`(备 .242) → ping .241。不用手填。
想显式指定或加锚点：

```sh
bridge-watchdog set-peer 172.10.10.242     # 本机是主，填备的 IP
bridge-watchdog set-anchor 172.10.10.254   # 再加一个稳定锚点（NTP 服务器/网关）
bridge-watchdog set-mode ping               # 只按 ping 判（or 更稳，不建议改）
```

### ⑥ 怎么保证「不通时不会无限重启」

`max_reboots=3` + 持久计数 `/etc/wdsdog-reboot-count`：
每次真重启前 +1，**网络一恢复就自动清零**；连续 3 次仍不通，自动把 `dryrun` 置 1、
写日志「已连续重启 3 次仍不通 → 自动转 dryrun 停手」，不再循环。
状态页 `/bridge/` 会显示重启计数并在达上限时给出排障提示。
配合 `grace=6` 的开机窗口，即使真出问题也有充足时间 SSH/TTL 进去 `off`。

### ⑦ 状态页同步

`/bridge/` 机器狗面板新增：判据模式、对端（含 ping 结果）、重启计数 / 上限，
CGI 的 `peer=auto` 解析与脚本同口径，并把开机宽限缺省从 3 改成 6。
AP 页面仍显示「停用，不会循环重启」。

其余配置（SSH :22 / TTYD :7681 / 管理 `172.10.10.241/22`、无线 DHCP 防护、
防火墙与 IPv6 关闭、删 wan/wan6、WAN+LAN 同桥、STP、NTP 客户端、简洁日志、
第 46 次 TARGET_DEVICES 裁剪）全部不变。

## 第 50 次：改网桥 IP 不会误重启 + 自动发现对端 + 下载页红字说明（2026-11-25）

> 用户追问：「网桥要是变 IP 地址是不是会导致重启？修改网桥 IP 要提示我去改
> 机器狗那的设置及 IP，或是网桥客户端自动检测主网桥的 IP；编译后在固件下载
> 日志那说明并标红。」

### ① 先直接回答：改 IP 本身**不会**触发重启

- 机器狗 `mode=or`，**无线关联**判据仍在；改 IP 后只要 WDS 关联正常，计时立刻清零。
- 必须**连续**不通满 `delay`(5) 分钟才重启；`network restart` 只是秒级断链。
- 开机 `grace=6` 分钟内根本不判故障。
- **但**旧 `peer` 指向 `.241/.242`：若「改 IP 后 + 无线也断」，互 ping 会失效 → 三条全不通才可能重启。这就是本轮要堵的口子。

### ② 三件套：与管理 IP 完全解耦

**ⓐ WDS 角色链路本地别名（最稳的兜底）**

| 角色 | 自己挂 | 互 ping 对方 |
|---|---|---|
| 主 `ap` | `169.254.241.1/16` | `169.254.241.2` |
| 备 `sta` | `169.254.241.2/16` | `169.254.241.1` |

避开 AP 模式调试别名 `169.254.240.1`。**管理 IP 改成任何地址，这两个别名都不变**，
`_wd_ping_ok` 优先 ping 别名 → 改 IP 不会让 ping 判据失效。
挂载点三处冗余：`bridge-netfix`(开机)、`role.sh`(角色收敛后)、
`health-fix`(手动自检)；`bridge-watchdog` loop 启动时还会 `_ensure_ll_alias` 补挂。

**ⓑ 网桥客户端自动检测主网桥 IP**

`_discover_peer()`：从 WDS 链路对端射频 MAC（`iw link` / `station dump`）取前 5 组字节，
在 `ip neigh show dev br-lan` 里反查同前缀的管理 IP（排除自己 / 链路本地 / 组播），
写入 `/tmp/wdsdog-peer-discovered`；loop **每 10 轮自动刷新**，`_resolve_peer()` 优先用它。
`status` 与 `/bridge/` 状态页都显示「自动发现对端」。

> 如实边界：NSS 卸载下 `station dump` 可能为空、neigh 可能还没学到对端 → 静默失败，
> 由 ⓐ 别名 + 角色推导 `.241/.242` 兜底，**绝不会因此误重启**。

**ⓒ `bridge-watchdog resync`（改完 IP 手动跑，两台各一次）**

重挂自身别名 → 重新发现对端新 IP → 写缓存 → 打印红字提示 → 重启机器狗。

### ③ 改 IP 的提示，四个地方都有（含「标红」）

| 位置 | 形式 |
|---|---|
| **固件下载页 Release NOTES** | 开头 `🔴 **【改 IP 必读】**` + `> ⚠️` 引用块（GitHub 不支持 CSS 字体色，用红圆+加粗+引用达到最醒目） |
| **Actions 编译日志** | `printf '\033[31m' ... '\033[0m'`，GitHub Actions 渲染 **ANSI 真红** |
| **随固件附的 `CHANGE-IP-NOTICE.txt`** | 和 `.bin/.ubi` 一起上传、进 `sha256sums`，下载时直接可见 |
| **设备端** | `bridge-watchdog status`（ANSI 红字）、`/bridge/` 状态页红色告警条（本机 IP 不是 .241/.242 时自动显示）、两份登录 banner、`health-fix`、`bridge-ap ip` |

`/bridge/` 新增显示：本机 IP、自身↔对端别名（含 ping 结果）、自动发现的对端 IP、改 IP 红条。

### ④ 改 IP 操作清单

```sh
uci set network.lan.ipaddr='172.10.10.243'; uci commit network; /etc/init.d/network restart
bridge-watchdog resync            # 本机：自动发现对端新 IP
# 另一台也改了 IP 的话，在另一台同样跑一次 resync
bridge-watchdog status            # 复核；IP 非 .241/.242 会打印红字
# 或显式指定（两台互相指向对方）：
bridge-watchdog set-peer 172.10.10.244
```

⚠️ **ping 自己 / 127.0.0.1 永远通，判不出断链；必须 ping【对端】**。
`peer=auto` 已自动做到主 `.241` ↔ 备 `.242` 互指。

### ⑤ 没动的东西

第 49 次全部保留：WDS 默认启用、5 分钟、时间可自定义（`set-delay` / `wds_delay`）、
`mode=or` 三判据、`max_reboots=3` 防无限重启、`dryrun`、`grace=6`。
AP 模式机器狗仍停用。网段 `172.10.10.241/22`、SSH/TTYD、DHCP 防护、防火墙/IPv6 关、
WAN+LAN 同桥、STP、简洁日志、第 46 次 TARGET_DEVICES 裁剪全部不变。

## 第 51 次：NTP 改成「每 5 分钟循环同步一次」（2026-11-25）

> 用户要求：「帮我设置一下 NTP，5 分钟同步一次。5 分钟同步是这样循环的同步。」
> 即不是开机同步一次、也不是自适应轮询，而是**固定每 300 秒一轮、无限循环**。

### ① 为什么不能只改 `/etc/config/system`

OpenWrt 的 `sysntpd` 常驻跑的是 **busybox ntpd**：轮询间隔是编译期常量
`MINPOLL`(32s) 起步、稳定后自适应拉长到几十分钟，**没有任何 UCI 参数能钉成 5 分钟**，
也不接受「立刻重新查询」信号。加 cron 做 `*/5` 固然可行，但会重新启用之前刻意停用的
cron，和「干净系统 / 低资源」冲突。

### ② 做法：`ntp-poller` 顶替 `sysntpd`

```
/usr/sbin/ntp-poller        # 周期触发器（sh 循环）
/etc/init.d/ntp-poller      # procd 常驻，START=96
```

每轮调用 `ntpd -q -n -p <server>`（`-q` = 设完时钟就退出），
**成功后 `sleep 300` → 下一轮 → 无限循环**：

```
开机立即同步一次
   ├─ 任一源成功 → sleep 300 秒 → 下一轮（严格 5 分钟周期，循环往复）
   └─ 两个源都不通 → sleep 30 秒快速重试；恢复成功后自动回到 300 秒周期
```

- **不启用 cron**、不装任何额外包/插件；一个 sh 循环 + `sleep`，几乎不占 CPU/内存。
- **日志简洁**：成功每 12 轮（1 小时）才写一条，失败每 6 轮写一条，
  `/tmp/ntp-poller.log` 上限 120 行；`status` 随时可查。
- **源不变**：仍是 `192.168.1.254` / `172.10.10.254`，`enabled=1`、
  `enable_server=0`（不对外服务）、`use_dhcp=0`（不收 DHCP 下发的源）、无公网 NTP。
- **源智能排序**：上次成功的源 > 与本机同 `/22` 网段的源 > 其余，去重。
  `172.10.10.254` 同网段直连，会排第一，开机第一次就同步成功，不用白等
  `192.168.1.254`（跨网段不可达）的超时。一个源不通自动用另一个。
- **带超时**：单源最多等 12 秒；busybox 没编 `timeout` 时用后台进程 + 轮询兜底。
- **单调时钟**：`status` 的「距下次同步」用 `/proc/uptime` 算，不用 `date`。
  NTP 每次校时都会改 wall clock，用它算倒计时会乱跳；
  机器狗 `bridge-watchdog` 同样用单调时钟，**NTP 跳变不会造成误重启**。
- **两个源都不通**：只记日志、继续循环，不改时间、不影响网络、绝不重启。

### ③ 服务切换（带兜底）

`sysntpd` 常驻必须停 —— 两个进程同时改系统时间会打架。切换在四处保证：
`99-bridge-ready`(WDS/AP 首启) + `rc.local` + `health-fix`(每次开机/手检)，
专治 sysupgrade「保留配置」把旧 `rc.d` 链接带回来。
**兜底**：`ntp-poller` 没编进固件时**不碰 sysntpd**，避免彻底没有 NTP。
`ntp-poller` 与 init.d 在 `prepare.sh` 里显式补 755 执行位。

### ④ 怎么改间隔（都不用重编）

```sh
ntp-poller status                # 看周期 / 上次同步 / 成功失败次数 / 距下次还剩多久
ntp-poller once                  # 立刻校时一次（绝不循环、绝不常驻）
ntp-poller set-minutes 10        # 5 → 10 分钟（1~1440），立即生效、UCI 持久化
ntp-poller set-interval 300      # 直接按秒改（30~86400）
ntp-poller set-retry 30          # 失败重试间隔
ntp-poller set-timeout 12        # 单源等待上限
ntp-poller on | off              # 启用 / 停用
```

**编译期**：两份 workflow 新增 `ntp_poll_minutes` 输入框（默认 5，1~1440 分钟），
`prepare.sh` 转成秒 → `port-overlay.sh` 写进 `system.ntp.poll_interval`；
非法值（0 / 非数字 / >1440）自动回落 5 分钟。
Prepare 日志会打印 `✓ system → … + 每 5 分钟循环校时（300s）`。

### ⑤ 配置项

`/etc/config/system` 新增一行，其余不变：

```
config timeserver 'ntp'
    option enabled '1'
    option enable_server '0'
    option use_dhcp '0'
    option poll_interval '300'    ← 第 51 次：固定 300 秒 = 5 分钟
    list server '192.168.1.254'
    list server '172.10.10.254'
```

`retry_interval` / `sync_timeout` 不写 UCI，脚本自带缺省（30 / 12），
`ntp-poller set-retry` / `set-timeout` 改时才会写入。

⚠️ 刷后别在 LuCI「系统 → 系统属性」里点 NTP 开关（那套 UI 面向 sysntpd）；
用 `ntp-poller` 的 CLI 或直接 `uci set system.ntp.poll_interval=...` 后 restart。

### ⑥ 没动的东西

第 50 次全部保留：改 IP 不误重启 + 自动发现对端 + 下载页红字说明；
第 49 次机器狗（5 分钟 / `set-delay` / `mode=or` / `max_reboots=3`）；
管理网段 `172.10.10.241/22`、SSH/TTYD、DHCP 防护、防火墙/IPv6 关、
WAN+LAN 同桥、STP、简洁日志、第 46 次 TARGET_DEVICES 裁剪。

## 第 52 次：插件 / 服务冻结基线（只增不减）+ 详细日志（标红）（2026-11-25）

> 用户原话：「以后插件就以这版为准，不能再减少了，以后只能增加或保持，
> 并出具一版详细的日志，重要地方标红。」

### ① 冻结口径：取广义，不只锁一个 `luci-app-ttyd`

如果只锁「LuCI 插件」，这版本来就只有 `luci-app-ttyd` 一个，所谓「不能再减少」
几乎等于没约束。所以把**这版固件实际具备的全部能力**纳入冻结：

| 类别 | 数量 | 例子 |
|---|---|---|
| 编译包 | 29 | dropbear / ttyd / luci-app-ttyd / ath11k-firmware-ipq5018-qcn6122… |
| 全局开关 | 4 | 256M 低内存 profile / squashfs / 不编 initramfs / CONFIG_IPV6=n |
| init.d 服务 | 9 | ntp-poller / bridge-watchdog / l2-guard / luci-fix… |
| usr/sbin 工具 | 20 | health-fix / bridge-ap / wifi-heal / accel-check… |
| 状态页 / CGI | 4 | /bridge/ / /ap/ 两个页面 + 两个只读 CGI |
| 首启 uci-defaults | 4 | 99-bridge-ready / 99-no-firewall / 99-no-ipv6… |
| 关键 UCI 配置 | 12 | wdsdog enabled=1 / poll_interval=300 / stp=1 / 管理 IP… |
| **合计** | **82 项** | 逐项硬校验 |

### ② 单一数据源：`baseline/frozen-baseline.conf`

```
[pkg]|dropbear
[pkg]|luci-app-ttyd
[initd]|ntp-poller
[cfg]|files/etc/config/system|option poll_interval '300'
```

🔴 **铁律：只允许【追加新行】，禁止删除 / 改名 / 改值任何已有行。**
`scripts/verify.sh` 里 `FROZEN_MIN=82` 是硬编码下限 —— 就算有人把清单和代码
一起删掉一行，也会被「81 项 < 下限 82」拦住；另有锚点复核（TTYD / SSH /
l2-guard / 机器狗 / ntp-poller）硬编码再查一遍，防整个清单被替换。

### ③ 三重校验（少一项就出不了固件）

| 层 | 位置 | 少一项的结果 |
|---|---|---|
| 上传前自检 | `verify.sh` 第 52 次判据段 | `🔴 冻结基线…丢失` → `RESULT: FAIL` |
| 编译期 | `gen-config.sh` 读同一份清单的 `[pkg]` 段 | defconfig 后 `::error::🔴 冻结基线包缺失` + `exit 1` |
| 防篡改 | `FROZEN_MIN=82` + 锚点复核 | 连清单一起删行 / 整体替换也 FAIL |

`gen-config.sh` 的 `REQUIRED_PKGS` 从旧版写死 5 个（SSH / TTYD / 射频固件）
改成**读清单全量 29 个**；核对从「只警告」升级为「阻断」。
`verify.sh` 里旧判据 `luci-app 数量 == 1` 改成 `>= 1 且基线项在位` ——
以后新增 LuCI 插件不会再被自检误杀，符合「只能增加」。

实测五种场景：原样不动 → PASS（82/82）；删 `nic-guard` → FAIL；
把 `luci-app-ttyd` 从 seed 注释掉 → FAIL（自检 + 编译期双层）；
从清单删一行 → FAIL（81 < 82）；新增一个 init.d + 一个 sbin → PASS
且提示「基线外新增项（允许）」。

### ④ 以后怎么加插件（正确姿势）

1. 在 `baseline/frozen-baseline.conf` 的 `[pkg]` 段**追加**一行 `[pkg]|新包名`
2. 在 `config/plugins.seed`（或 common.seed）把对应包写成 `=y`
3. `sh scripts/verify.sh` 会显示「基线外新增项（允许）」，编译期也会自动核对
4. 若新增的是服务 / 页面，往 `[initd]` / `[sbin]` / `[www]` 段追加即可

🔴 **不要删旧行、不要把 `=y` 注释掉、不要改 `=n`。**
关闭项（防火墙 / IPv6 / 第三方 luci-app-\*）不在这份清单里，属于这版的
「行为红线」，详见详细日志第十节；要变更需单独显式确认。

### ⑤ 详细日志（重要处标红）—— 三份，覆盖三种媒介

| 文件 | 标红方式 | 用在哪 |
|---|---|---|
| `baseline/插件基线冻结报告.html` | **CSS 真红** `color:#d00` + 红底警示框 | 手机 / 浏览器直接打开，最直观（主交付） |
| `baseline/插件与服务冻结基线-详细日志.md` | 🔴 + **加粗** | GitHub / 编辑器阅读 |
| `baseline/基线摘要.log` | **ANSI `[31m` 真红** | SSH / 终端 `cat` 出来就是红的 |

内容包含：10 条标红重点、三重校验、29 个包逐个用途与定位文件、
9 个服务 / 20 个工具 / 4 个页面 / 4 个首启 / 12 项关键配置 / 4 个全局开关、
🔴 明确关闭项（红线）、访问与网络速查、五种校验场景实测、变更记录。

**编译后在固件下载页也能看到**：两份 Release NOTES 开头新增
`🔴 【插件基线已冻结】` 段；Actions 的 Organize 步骤用 ANSI 真红打印
`🔴【插件基线已冻结】…82 项只增不减…`，和上一轮「改 IP 必读」的红字一起出现。

### ⑥ 没动的东西

第 51 次（NTP 每 5 分钟循环）、第 50 次（改 IP 不误重启 / 自动发现对端）、
第 49 次（机器狗 5 分钟 / set-delay / mode=or / max_reboots=3）、
管理网段 `172.10.10.241/22`、SSH/TTYD、DHCP 防护、防火墙/IPv6 关、
WAN+LAN 同桥、STP、简洁日志、第 46 次 TARGET_DEVICES 裁剪 —— 全部原样保留。
本轮**没有删任何插件，也没有加任何插件**，纯粹把现状冻结成基线。

## 第 54 次：修复冻结基线误判导致的编译中断（2026-11-25）

> 11-25 02:28 的 WDS 编译（HEAD `a6bd8fbe`，第 52 次包已完整上传且 139/139 一致）
> 在 **make 之前**就 `exit 1`，vs010 与 rax3000q 两台同一处：
>
> ```
> ##[error]🔴 冻结基线包缺失（只增不减，禁止精简）：
>   vs010     luci-i18n-base-zh-cn nftables kmod-bridge
>   rax3000q  luci-i18n-base-zh-cn nftables kmod-bridge ipq-wifi-cucc_vs010
> ##[error]Process completed with exit code 1.
> ```
>
> Prepare 里 `verify.sh` 已 `RESULT: PASS`、`feeds install -a` 完成、board-inject 完成，
> 卡在 `gen-config.sh` 的 `make defconfig` 之后那一段——**编译一步都没开始**。

### ① 根因：第 52 次把判据放错了层

第 52 次把「冻结基线包核对」升级为：**`make defconfig` 之后，29 个包在 `.config` 里必须全部精确 `=y`，否则 `exit 1`**。
但 `make defconfig` 本来就会**合法收敛符号**：

| 包 | 为什么不是 `=y` |
|---|---|
| `kmod-bridge` | 25.12 的 `target/linux/generic/config-6.12` 里 **`CONFIG_BRIDGE=y`**（bridge 内核内建），`package/kernel/linux/modules/netsupport.mk` 已无 `KernelPackage/bridge` 定义 → 包符号被 Kconfig 隐藏，功能由内核内建提供，**更好** |
| `luci-i18n-base-zh-cn` | LuCI i18n 由 `luci.mk` 按 po 目录生成，符号在 defconfig 阶段合并/条件隐藏 |
| `nftables` | 符号合并 / 变体（内核侧 `CONFIG_NF_TABLES_BRIDGE=y` 等已内建） |
| `ipq-wifi-cucc_vs010` | `board-inject.sh` **只在 vs010** 生成这个本地 BDF 包，rax3000q 下根本没有该 Makefile |

**决定性佐证**：上一轮（11-24 15:15）**同一棵 qosmio 树、同一份 seed**，gen-config 输出
`✓ 760 个 =y 符号，设备 unicom_vs010 保住` 并顺利跑到 `make` 48 分钟。
这 4 个包从来就不在 `.config` 里 —— 是 Kconfig 行为，**不是谁把插件删了**。
第 52 次之前只核对 5 个核心包，所以从未暴露。

日志里那 6 条 `recursive dependency detected!`（dnsdist / snort3 / weechat / knot-resolver / openappid）
是 qosmio feed 自带包的 Kconfig 告警，`# configuration written to .config` 说明 defconfig 本身成功，**不是失败原因**。

### ② 修法：判据归位，红线不放松

| 层 | 新判据 | 少了会怎样 |
|---|---|---|
| 🔴 **A 层 seed 声明（硬阻断）** | `config/*.seed` 里 29 项逐条查 `CONFIG_PACKAGE_<名>=y` | 注释掉 / 改 `=n` / 删行 → `::error::` + `exit 1` |
| **B 层 defconfig 分层诊断** | 核心锚点 5 项必须精确 `=y`；其余 Kconfig 收敛只 `::warning::` 汇总；符号在 `.config`、`tmp/.config-package.in`、包源里都找不到才真阻断 | 核心锚点收敛 → 阻断；合法收敛 → 只报告 |
| **机型条件项** | `ipq-wifi-cucc_vs010` 在 rax3000q 下跳过 defconfig 核对（seed 声明仍查） | 不再误报 |
| **防篡改（不变）** | `FROZEN_MIN=82` + 锚点复核 | 连清单一起删行 / 整体替换也 FAIL |

🔴 **「只增不减」的真保障落在 A 层** —— 唯一会被人改坏的就是 seed 里的 `=y`。
第 45 次「gen-config 用 `feeds list` 误判把 `luci-app-ttyd` 从 `.config` 删掉」的坑也被 A 层挡住。
核心锚点 = `dropbear / ttyd / luci-app-ttyd / ath11k-firmware-ipq5018-qcn6122 / kmod-ath11k-ahb`，
这 5 个在失败日志里全部是 `=y`，**仍严格阻断，绝不放松**。

`gen-config.sh` 输出改为：
```
[gen-config] ✓ A 层 seed 声明 29/29 在位（只增不减，此层硬阻断）
::warning::Kconfig 合法收敛（seed 声明未变、非减少插件）： luci-i18n-base-zh-cn nftables kmod-bridge
[gen-config] ✓ B 层 defconfig 诊断：25 个精确 =y / 3 个 Kconfig 收敛 / 0 个真缺
```
收敛清单同时写进 `build.env` → 设备端 `/etc/build-info` 可追溯。

### ③ 顺带修掉的三件隐患

1. 🔴 **构建树排除 14 个包外野文件**（`prepare.sh`，**仓库文件一个不删**，`KEEP_EXTRA_FILES=1` 可逆）。
   上一轮核查发现网页上传是覆盖式，仓库比第 52 次包多出 61 个文件，其中 14 个在 `files/` 下会被
   `cp -r` 整目录带进固件：另一套自称「第 53 次」的 `ntp-sync` 三件套（又一个 5 分钟 NTP 守护，
   会和 `ntp-poller` **同时改系统时间**）、`dhcp-guard` init.d（与 `l2-guard` 重复开机自启）、
   约 1.5 MB QSDK 5.4 闭源 WiFi 固件（`Data.msc` / `regdb.bin`，第 41 次已论证禁止进 6.12 主线 ath11k 镜像）。
   现在只在**构建树**里剔除并打印 `✓ 构建树已排除包外野文件（仓库不动）：14 个`。
2. 🔴 **nft 缺失不再静默空转**：`nftables` 可能被 defconfig 收敛，`l2-guard` 原来只 quietly skip；
   现在写 `/tmp/l2guard.reason` + `logger` 红字，`health-fix` 明确报告
   「🔴 nft 命令 / bridge family 不可用 —— 无线 DHCP 防护【未生效】」。
   刷后跑 `health-fix` 或 `apk list nftables*` 即可复核；若真缺包，把编译日志贴回来补等价符号。
3. 两份 Release NOTES 开头新增 `✅ 【第 54 次】` 说明；`verify.sh` 加第 54 次判据，
   确保以后不会再有人把「全量精确 =y 阻断」加回来。

### ④ 实测（六种场景）

| 场景 | 结果 |
|---|---|
| 全部 29 项精确 `=y` | ✅ PASS（29/29） |
| **复现 02:28 失败**：4 项 Kconfig 收敛 | ✅ PASS（25 精确 =y / 4 收敛只警告 / 0 真缺） |
| rax3000q（本地 BDF 包不生成） | ✅ PASS（机型条件项跳过） |
| 删掉 seed 里 `luci-app-ttyd` 的 `=y` | ✅ 被 A 层拦 `exit 1` |
| 核心锚点被 defconfig 收敛 | ✅ 被 B 层拦 `exit 1` |
| 新增插件 / 服务 | ✅ PASS，提示「基线外新增项（允许）」 |

构建树排除段实跑：14 个野文件全清、剩余 0；仓库源文件未被改动。
`verify.sh` 普通 / 严格均 `PASS（0 警告）`。

### ⑤ 没动的东西

🔴 **82 项冻结基线一个没动、一个没删**（`baseline/frozen-baseline.conf` 保持 82 行原样）。
第 51 次 NTP 每 5 分钟循环、第 50 次改 IP 不误重启、第 49 次机器狗、
管理网段 `172.10.10.241/22`、SSH/TTYD、无线 DHCP 防护、防火墙/IPv6 关、删 wan/wan6、
WAN+LAN 同桥、STP、简洁日志、第 46 次 TARGET_DEVICES 裁剪 —— 全部原样保留。
本轮**没有删任何插件，也没有加任何插件**。
