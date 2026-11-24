# 老仓库 → 新内核改造说明（`vs010-rax3000q-openwrt`）

核查日期：2026-11-24　｜　老仓库：`gggbin2026/Actions-OpenWrt-RAX3000Q-VS010-WDS@6c74d54`
新仓库：`gggbin2026/vs010-rax3000q-openwrt@7242549`（= `xiangye277/vs010-openwrt` 的副本）

---

## 0. 一句话结论

**不能把老仓库整包复制过来改个版本号。** 老仓库跑在 **32 位 / Linux 5.4 / QSDK 11.5 闭源栈**上，
新内核是 **64 位 / Linux 6.12+ / 官方 qualcommax 开源栈**，两者的 `.config`、驱动、补丁、WDS
加速补丁全部不通用。能搬的是**编排层 + 运行期 overlay + 板级真值**；驱动与内核补丁必须换血。
本包已经把能搬的搬好、不能搬的重写好，并给出三条新内核基线供选择。

---

## 1. 两个仓库的真实底细

| 项 | 老仓库（已成功出 5 个 Release） | 新仓库（待改造） |
|---|---|---|
| 源码 | `kkstone/immortalwrt-ipq50xx @ openwrt-21.02` | `openwrt/openwrt` main SNAPSHOT（无分支无 tag） |
| 内核 | **Linux 5.4 / QSDK 11.5** | **Linux 6.12.94**（上一轮 build.log 实证） |
| 架构 | **32 位** `arm_cortex-a7_neon-vfpv4`（`CONFIG_TARGET_ipq50xx_arm`） | **64 位** `aarch64_cortex-a53_musl`（`qualcommax/ipq50xx`） |
| 包管理 | opkg | **apk** |
| 交换/无线 | swconfig + `qca-nss-dp/drv/ecm` + `qca-ssdk` 闭源栈 + 私有 4addr WDS offload 补丁 | DSA + 开源 `ath11k` + `kmod-qca-nss-dp`（官方默认包） |
| 设备 | `cmcc_rax3000q`（底座原生）、`cucc_vs010`（diy 注入） | 只有 `unicom_vs010`，基于官方 CMCC PZ-L8 DTS |
| 编译状态 | 双 workflow（WDS/AP）× 双机型，成功出固件 | 单 workflow，**编译失败**（DTS 文件名错配），`firmware/` 里只有日志无镜像 |
| 运行期资产 | `files/` + `files.ap/` 共 50 个文件：网桥主备、机器狗、状态页、AP 控制台、LuCI 修复、仪表盘、主题 | 无 |
| 已知短板 | VS010 5G 弱（闭源 qca_ol 栈与 ath11k BDF 不兼容，作者已确认）；IPv6 编译期必须关（ECM BUG_ON panic） | WiFi 校准 BDF 未进固件；官方 25.12 的 PZ-L8 定义缺 `DEVICE_PACKAGES`，WiFi 根本不 probe |

> 老仓库 4 份 `.config` 各 7283 行，全是 `CONFIG_TARGET_ipq50xx_arm_*` / `CONFIG_LINUX_5_4` 符号，
> 在 6.12 树里一个都不存在；`slim.*.sh` 强制 `qca-nss-fw-ipq50xx-retail`、`kmod-qca-ssdk-nohnat`、
> `swconfig`；`diy-part2.*.sh` 全部操作 `target/linux/ipq50xx/...` 旧路径；`inject-ethtool-patch.sh`
> 与 `extend-421-nand.sh` 打的是 5.4 内核补丁；`prefetch-ath-kernel.sh` 拉的是 2021 年 kvalo ath-kernel。
> **这些文件全部不能进新内核树。**

---

## 2. 新内核基线选型（抓到的最新信息）

| 基线 | 内核 | NSS | RAX3000Q | VS010 | 适合 |
|---|---|---|---|---|---|
| **A · `qosmio/openwrt-ipq @ 25.12-nss`（推荐）** | **6.12.116**（25.12 分支 + 安全补丁，比 25.12.6 的 6.12.112 还新） | **QSDK/NSS 12.5 开源栈** | ✅ `cmcc_rax3000q` **实机验证** | 用本包注入 | 要「有线无线提升」又要新内核、两台一起编 |
| B · `openwrt/openwrt @ v25.12.6` | 6.12.112（官方唯一受支持稳定版） | ❌ 无 NSS（千兆转发约 500M 就跑满双核 CPU） | ❌ 官方 15 个 ipq50xx 设备里**没有 RAX3000Q** | 用本包注入 | 最稳、主题/插件最多、可复现；但两台设备都要自己注入 |
| C · `kuncy7/openwrt-nss-edma @ c3po-tag-8021q` | **6.18.60**（2026-11-07 社区满血 WiFi 版同步，修 WiFi↔WAN 降速 + CVE-2026-98432） | NSS FW **12.2-156**，实测有线 943Mbps / 5G WiFi 915Mbps、CPU 2~3% | ❌ 未覆盖 | ❌ 未覆盖 | 无线绝对满速尝鲜，需自己移植两台板级 |

推荐 **A**：它是「OpenWrt 25.12 + 6.12.116 + NSS 12.5 + apk」的交集，同时原生支持 RAX3000Q，
承接老仓库的 NSS 卖点，且 VS010 只需注入一个 DTS；固件命名不再带任何旧 SDK 编号。
B 作为「编译失败时的退路」，C 作为后续性能进阶，三者通过 workflow 里 `baseline` 下拉切换。

**官方 25.12.6 同期信息**：Linux 6.12.95→6.12.112 稳定分支修复、OpenSSL 3.5.9、
Mbed TLS 3.6.7、wolfSSL 5.9.4、mac80211 backports 6.18.26→**6.18.55**、wireless-regdb 2026.09.03；
社区侧有 `luci-theme-footstrap`（需自带 feed）、官方侧有 `luci-mod-dashboard`（实时图表）、`luci-app-librespeed`、
`luci-app-weechat`。24.10（6.6.144）已于 2026-09 EOL。

**本轮复查（2026-11-24）补充**：`nss.general.wifi_offload=1` 是 IPQ5018 无线满速的总开关，
Forum 253014 #392 记录 AX6000 上 =1 时 600Mbps@16% 单核、=0 时 500Mbps@90% 双核；
c3po 分支曾因「必须 `fw-memory-mode=2`」的错误检查把它自动关掉，社区已确认是 bug 并回滚默认开。
恩山 8496060（2026-11-07）的满血 WiFi 版已同步 6.18.60，首页自带 NSS 加速状态与温度显示。
社区 NSS+DSA 能力表（2026-11-18 reviewed）明确把 **Wi-Fi WDS 标为 Unvalidated（FW 12.2）**，
所以「满速 + 信号」优先 AP 模式，WDS 保留原生 4addr 但要留出回退路径。

---

## 3. 逐项移植对照表

### ✅ 直接搬（内核无关，本包已放好）

| 老仓库 | 新包位置 | 说明 |
|---|---|---|
| 两份 workflow 的**编排**（双入口、`device=both` matrix、Release 滚动保留 5、日期戳、tag 后缀 `-wds`/`-ap`） | `.github/workflows/build-wds.yml` / `build-ap.yml` | 重写了 clone/prepare 段，保留命名与发布逻辑 |
| `files/`（WDS 基底：主备、机器狗、LuCI 修复、状态页、banner、accel-check、wifi-heal…） | `files/` | 关键配置由 `scripts/port-overlay.sh` 升级语法 |
| `files.ap/`（AP 覆盖层：哑 AP、`.240`、无 DHCP、AP 控制台 `/ap/`、rssi-guard） | `files.ap/` | 同上 |
| `files.vs010/` / `files.rax3000q/`（机型 hostname/system） | 同名目录 | 不变 |
| `vs010/bdf/board-cucc_vs010.*`、`wifi-truth.conf`、采集/核对脚本、`nwrt-dump.dts`（存档） | `vs010/` | BDF 二进制与内核无关，直接复用 |
| `oem_extract/`（新仓库自带的原厂 BDF） | `oem_extract/` | 作为第二份校准来源 |
| 出厂语义：WDS 主 `.241` / 备 `.242`、5G ch36 HE160、DHCP 1h、机器狗 5 分钟；AP `.240`、`NwrtAP-2G/5G`、无 DHCP | `FIRMWARE.md` + overlay | 完整保留 |

### ❌ 不搬（绑死 5.4 QSDK，进了就编译失败）

`RAX3000Q.config` / `VS010.config` / `AP_*.config`（7283 行全量符号）、`slim.*.sh`、
`diy-part1.sh` / `diy-part2.*.sh`（旧树路径注入）、`patches/999-nss-dp-ethtool-fixed-link.patch`、
`inject-ethtool-patch.sh`、`extend-421-nand.sh`、`prefetch-ath-kernel.sh`、
`启用真DHCP_Snooping_需重编.sh`（旧树专用）、`feeds.conf.default`（pin 到 immortalwrt 21.02）、
「IPv6 编译期必须关」「`CONFIG_ATH11K_NSS_SUPPORT`」「`MAC80211_MESH`」等 5.4 专用开关。

替代方案：本包用 `scripts/gen-config.sh` 按 25.12 符号**自动探测 target 并生成差异配置**，
用 `scripts/board-inject.sh` 按 `qualcommax/image/ipq50xx.mk` 骨架注入设备定义。

### ⚠ 必须重写/升级的语法（`scripts/port-overlay.sh` 自动处理）

| 21.02 老写法 | 25.12 新写法 |
|---|---|
| `option type 'bridge'` + `option ifname 'eth0 eth1'` | `config device 'br_lan'` + `option type 'bridge'` + `list ports 'lan1' 'lan2' 'lan3' 'wan'`（DSA 端口名以实机 `ip link` 为准） |
| `option hwmode '11g' / '11a'` | `option band '2g' / '5g'` |
| `config switch` + `swconfig dev switch1` | DSA，`swconfig` 相关脚本降级为只读探测（不 set reset/apply） |
| `opkg`、`luci-lib-ipkg`、`luci-i18n-opkg-zh-cn` | `apk`、`luci-lib-*`（ucode 版）、`luci-i18n-base-zh-cn` |
| `list lua_prefix .../sgi/uhttpd.lua` | 25.12 LuCI 走 ucode，去掉旧 lua 处理器行，保留 `cgi_prefix` |
| `mediaurlbase /luci-static/argon` | 改为 `/luci-static/bootstrap`；themes 段只列真实存在的目录，由 `luci-fix` 每次开机重建（幽灵主题会白屏/500） |
| `wifi-bdf-check` 查 QSDK `board-2.bin` 路径 | 改查 ath11k `calibration-variant` + `ipq-wifi-*` 包路径 |

---

## 4. 四个硬门槛（刷之前必须确认）

1. **64 位 U-Boot**：老固件是 32 位，新基线全部是 64 位（`aarch64`）。社区 25.12-NSS 固件明确警告
   「刷之前确保不死 U-Boot 支持 64 位引导，不支持就是不开机」。**没有 64 位不死 U-Boot 先别刷。**
2. **WDS 4addr 未在新内核验证**：老仓库的「自动一主一备 + 4addr + NSS WDS offload」依赖 QSDK 私有
   `ath11k-*-4addr-*` 补丁；6.12 开源 ath11k 只有 mac80211 原生 4addr，NSS 的 WDS/WIFI-STA 加速在
   IPQ50XX 上社区矩阵仍标「需验证 / 未覆盖」。本包 WDS 模式默认**保留配置但降级为原生 4addr**，
   首次必须 TTL 串口看 `iw dev wlan1 station dump` 与桥是否通；不通就先把 WDS 当「双机 AP」用。
3. **VS010 校准数据**：官方 25.12 的 `Device/cmcc_pz-l8` 没写 `DEVICE_PACKAGES`，`ath11k` 固件与
   board data 不在镜像里，射频不 probe。本包 `board-inject.sh` 强制补
   `ath11k-firmware-ipq5018-qcn6122` + 本地 `ipq-wifi-cucc_vs010`（BDF 落盘，不联网下载，
   避开老仓库踩过的 403）。老仓库「5G 弱」是闭源栈不兼容，开源 ath11k + 正确 BDF 反而有机会更稳，
   但需实机测。
4. **首次刷机备好 3.3V USB-TTL**（VS010 UART GPIO28/29，115200 8N1；RAX3000Q 同理），
   Web API 刷写会直接覆盖 rootfs。

---

## 5. 包策略：最稳、最少系统问题（2026-11-24 修订）

| 类别 | 包名 |
|---|---|
| 官方主题（默认只编） | `luci-theme-bootstrap`（官方 25.12 luci feed 自带，零风险） |
| 社区主题（默认不编） | `luci-theme-argon`（jerrykuku）、`luci-theme-footstrap`（VizzleTF）、`luci-theme-edge`；必须额外加 feed 并核对包名，光写 `=y` 会被 defconfig 静默丢掉 |
| 官方新增界面 | `luci-mod-dashboard`（实时图表）、`luci-app-librespeed`、`luci-app-weechat` |
| 老仓库保留 | `luci-i18n-base-zh-cn`、`luci-mod-admin-full/network/status/system`、状态页 `/bridge/`、AP 控制台 `/ap/` |
| 实用插件（AP 版按需） | `luci-app-adblock`、`luci-app-sqm`、`luci-app-wireguard`、`luci-app-ttyd`、`luci-app-statistics`、`smartdns`、`https-dns-proxy`、`iperf3`、`htop`、`nano`、`curl`、`wget-ssl` |
| 注意 | apk 与 opkg 命令不同；官方 25.12 只有极少数包名变化，但**第三方 21.02 插件包名必须逐个核对**，不要照抄老 `slim` 白名单 |

**本轮按用户要求改为：两种模式都极简。** 只编 SSH `dropbear` + TTYD `ttyd`/`luci-app-ttyd` +
LuCI 底座/中文 + 官方 `luci-theme-bootstrap` + 状态页 + 必要驱动；
`firewall4`/`firewall`、所有第三方 `luci-app-*`、下载/统计/科学插件、`iperf3/htop/nano`
全部显式 `is not set`（`scripts/gen-config.sh` 的 FORCE_OFF 列表兜底）。
上表那些插件保留在 `config/plugins.seed` 作为「以后按需开启」的候选，默认全注释。
`verify.sh` 硬校验 `luci-app-*` 只能有 1 个（ttyd）。WAN+LAN 全部在 `br-lan`。

---

## 6. 操作步骤

1. 把本包内**全部文件/目录**上传/覆盖到 `gggbin2026/vs010-rax3000q-openwrt` 仓库根
   （`.github/`、`files*/`、`vs010/`、`oem_extract/`、`config/`、`scripts/`、`board/`、4 个 md、`.gitignore`）。
   旧文件可留着（`firmware/` 里的失败日志建议删掉，避免误导），两份新 workflow 与老 `build.yml` 不冲突。
2. Actions → 选 `Build WDS Bridge (新内核)` 或 `Build AP (新内核)` → `baseline=qosmio-25.12-nss`、
   `device=both` → Run。首次建议只跑 `vs010` 一台，2~4 小时。
3. 下载 Release 里 `Nwrt-WDS-<内核版本>-<日期>-<机型>-*` / `Nwrt-AP-<内核版本>-<日期>-<机型>-*` 的 `factory.ubi`（不死 U-Boot）/`factory.img`（VS010 原厂 Web API 需要 `.img`，
   `board-inject.sh` 已保留 `qsdk-ipq-factory-nand` 生成 `.img`）与 `sysupgrade.bin`。
4. **TTL 串口起机验证**：`uname -m`（应为 aarch64）、`cat /etc/openwrt_release`、
   `ip link`、`wifi status`、`cat /sys/module/ath11k/parameters/nss_offload`、
   `sh /usr/sbin/health-fix`、`sh /usr/sbin/wifi-bdf-check`。
5. WDS 两台都起来后再验 4addr 桥接；不通就按 `FIRMWARE.md` 降级方案处理。

---

## 7. 本包文件清单

```
README.md / MIGRATION.md / FIRMWARE.md / baseline.env / .gitignore
.github/workflows/build-wds.yml    WDS 网桥入口（双机型 + 三基线）
.github/workflows/build-ap.yml     AP 入口（哑 AP + 主题/插件）
config/common.seed                两模式共用差异配置
config/wds.seed / ap.seed         模式差异包
config/themes.seed / plugins.seed 主题与最新插件清单
scripts/prepare.sh               clone→feeds→board→config→overlay 一站式
scripts/board-inject.sh          VS010/RAX3000Q 设备定义 + BDF 落盘
scripts/gen-config.sh            按 target 自动探测并生成 .config
scripts/port-overlay.sh          21.02 overlay → 25.12 语法升级
scripts/verify.sh                静态自检（跑一次再 Run workflow）
board/ipq5018-vs010.6.12.dts     6.12 风格 VS010 DTS 母本
board/README.md                  DTS 融合点与 wifi-truth.conf 用法
files/ files.ap/ files.vs010/ files.rax3000q/   移植并升级的运行期 overlay
vs010/ oem_extract/              原厂 BDF / 真值 / 采集工具（内核无关）
```

---

## 8. 信息来源

- OpenWrt 官网 / 25.12.6 Changelog / Release and security announcements（6.12.112、组件升级）
- `openwrt/openwrt@openwrt-25.12` 的 `target/linux/qualcommax/image/ipq50xx.mk`（15 个设备，无 RAX3000Q）
- qosmio/openwrt-ipq `25.12-nss` 分支的社区实机固件说明（6.12.91→6.12.116、NSS 12.5、cmcc_rax3000q 实机验证、64 位 U-Boot 要求）
- kuncy7/openwrt-nss-edma `c3po-tag-8021q` / nss-packages `ipq50xx-rebase`（6.18.55、NSS FW 12.2-156、943/915Mbps 实测）
- OpenWrt Forum 253014、恩山 PZ-L8 25.12.5 全开源 QSDK NSS 帖（官方 25.12 PZ-L8 缺 DEVICE_PACKAGES）
- luci-theme-footstrap 项目页（25.12+/apk 要求）
- 两个仓库本地完整克隆：老仓 6c74d54（78 文件 / 425 commits）、新仓 7242549（16 文件 / 8 commits）


---

## 9. 本仓当前口径（结论，不是逐轮日志）

- **命名**：`Nwrt-WDS-<内核版本>-<日期>-<机型>-*` / `Nwrt-AP-<内核版本>-<日期>-<机型>-*`；
  内核版本由 `make -s kernel_version` 实际抓取；旧 SDK 编号前缀已彻底弃用。
- **参考实现**：`mufeng05/openwrt-cmcc-pz-l8-nss`（官方 25.12.5 未修改基线 + QSDK 14.0
  驱动，ECM→NSS 双射频卸载）。它是 PZ-L8 单板 overlay，不含本仓两台板级，故不设为基线；
  可移植做法已落到运行期文件：NSS FW 12.5 优先、判速读 eth0/eth1 + NSS debugfs、
  温度按 `ath11k_hwmon`/设备树节点、端口按 sysfs 动态发现、不凭空创建 `nss` UCI 配置。
- **包**：只留 SSH + TTYD + LuCI 底座/中文/官方 bootstrap + 状态页；防火墙与第三方插件全 n。
- **防护**：独立 nft bridge 表拦无线端 rogue DHCP；`firewall4` 编译期关闭。
- 逐轮修订日志不再维护，请删除 `CHANGES-20261124.md`；完整清单见 README 末节。
