# 新内核 WDS / AP 固件 · VS010 + RAX3000Q（仿 UBNT 界面）

一个仓库、**一个 workflow**、两台机器、**每机型 1 个固件（AP ⇄ WDS 单包双模式）**、四条可复现源码基线。
`Actions → Run workflow` 一次出 2 个固件，**push 不触发编译**。

> 本仓库 2026-11-28 拉取时 `main` 最新提交是空提交（`qqqqqqqq`），仓库内没有任何文件。
> 本包是**整套重建**：按 5.4 老仓的「配置及要求」+ 25.12 仓库历史结论 + 仿 UBNT 界面重做。

## 一、先把「xiangye277 的内核及版本」说清楚（最重要）

实测 `https://github.com/xiangye277/vs010-openwrt` 的 `.github/workflows/build.yml`：

| 项 | 原仓库实际做法 | 本仓做法 |
|---|---|---|
| 源码 | `git clone --depth=1 --single-branch https://github.com/openwrt/openwrt.git`，**不带 `-b`** | 同一棵树 `openwrt/openwrt`，但 `baseline.env` 里**锁 ref** |
| 内核版本 | **根本没有锁定**，每次编译拉官方主线当时的最新快照，随上游滚动 | 编译期 `make -s kernel_version` 实抓，写进固件名与 Release tag，**不写死、不带旧 SDK 编号** |
| `.config` | 只有 4 行（target / squashfs / `ATH11K_MEM_PROFILE_256M`） | `config/common.seed` 完整精简清单 + `gen-config.sh` 兜底 |
| 板级 | `cp ipq5018-vs010.dts target/linux/qualcommax/dts/` + 往 `ipq50xx.mk` 追加 Device + `sed` 注入 `02_network` | **不能直接抄**：25.12 的 DTS 在 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/`，且该 DTS 是 PZ-L8 改编、作者自己在 README 里警告 GPIO/switch 可能有误 |
| 插件 | 25 个科学/下载/统计包（SmartDNS + DoH + WG + adblock + SQM + iperf3/htop/nano…） | **全部不编**，只留 TTYD + dropbear + LuCI 底座 |

所以「保证要这个内核和版本」 cannot 靠照抄实现：那个仓库没有版本可锁。
本仓保留它的**本质——官方 OpenWrt 源码树**，把版本锁成可复现的 tag/commit，
并提供 `source_url` / `source_ref` 两个 workflow 输入，随时可覆盖成你想要的那个 commit。

四条基线（`baseline.env` 是唯一真值，改这里，不改 workflow）：

| baseline | 源码 / ref | 内核 | NSS | 说明 |
|---|---|---|---|---|
| `official-25.12`（**默认**） | `openwrt/openwrt` @ `v25.12.6` | 6.12.112 | 无 | **xiangye277 同源、锁定版**：官方稳定、apk、占用最低、最稳 |
| `official-main` | `openwrt/openwrt` @ `main` | 实抓 | 无 | xiangye277 原始滚动口径；建议把 `source_ref` 填成具体 commit 再编 |
| `qosmio-25.12-nss` | `qosmio/openwrt-ipq` @ `25.12-nss` | 6.12.116 | FW 12.5 | 有硬件加速，5G 160MHz 773~833Mbps；上游地址若迁移改 `baseline.env` |
| `kuncy7-6.18-nss` | 见 `baseline.env` 注释 | 6.18.60 | FW 12.5 优先 | 尝鲜；不含这两台板级，`board-inject.sh` 会警告且需自行核对 |

⚠ 刷之前确认不死 U-Boot 支持 **64 位引导（aarch64）**：四条基线全是 aarch64，
5.4 老仓是 32-bit arm。首次刷备 3.3V USB-TTL（VS010 是 1.8V 电平，注意转换）。

## 二、产物

| 入口 | 固件 | Release tag |
|---|---|---|
| `Build WDS/AP (新内核 · 单包双模式)` | `Nwrt-WDS-AP-UBNT-<内核>-YYYYMMDD-<机型>-dual-*.ubi / *.bin` | `fw-<内核>-<run_id>-<机型>-dual` |

`device=both`(默认) 一次并行出 **2 个固件**（VS010 1 个 + RAX3000Q 1 个），也可单机。
`default_mode=wds|ap` 只决定刷完首次开机的默认模式，**之后在界面里随时切，不用重刷**。
滚动保留最新 5 个 Release。日期戳、机型、原文件名后缀沿用老仓库格式。

> 🟢 **单包双模式**：一个固件内置 AP + WDS，`/cgi-bin/luci/admin/nwrt` 或
> `nwrt-apply-mode wds|ap` 切换；三界面全互访。详见 `docs/模式切换与巡检.md`。
> 🟢 **轻量巡检**：单个 `nwrt-tick` 常驻（NTP + WDS 关联只读巡检），出厂 `dryrun=1` 不自动动作。

## 三、界面：对齐 5.4 老仓 r28–r29.12，但按 6.12 升级修复

🖼 **交付里附两张真渲染预览图**（Chromium + Playwright 截本仓页面，非手绘）：
`界面预览-bridge.png`（网桥）与 `界面预览-ap.png`（AP），每张左桌面 1280px、右竖屏 390px，
用 `?demo=1` 离线演示数据，图上明确标注 DEMO、非实机读数。

对齐老仓的：三页 UBNT 深色 + 六入口互访 + 右上角「⚙ 高级设置后台」、
前 3 块严格同序（系统仪表盘 GAUGE → 常用设置 SETUP → 网络与本机 NETWORK）、
GAUGE 三环 + 时间/运行徽章 + 无线芯片温度、SETUP ①…⑧ 八分组、
内网LAN1… 6 列表（链接速率/来源）、999px 胶囊、未登录只读 + probe 锁保存、
写入只在 LuCI admin 树、维护动作固定枚举、WDS 搜索周边主端、离线 ?demo=1。

**按 6.12 升级修复的**（详见 `docs/界面与配置对齐-5.4.md`）：
QSDK 的 `HT160/HT80/HT40` → 主线 `HE160/HE80/HE40/HE20`（写 HT* 会让 radio 起不来）；
`db_rssi_thr`/`db_timeout`/MU-MIMO 字段保留但明确标注「该基线不支持，不下发」；
Argon 2.4.3 → **UBNT（仿 UniFi）主题**（官方 bootstrap 作底资源）；闭源 QSDK BDF → 官方 `board-2.bin`；
模式守卫从「2 秒踢走」改为「非强制提示条 + 三页全互访」（单包双模式下更优）。

### 主题：UBNT（仿 UniFi），不是 bootstrap 原样

🟢 **用户要的 UBNT 主题已经同时覆盖三页状态页和 LuCI 后台**：
`files/www/luci-static/ubnt/cascade.css` 是真·主题目录，第一行 `@import` 引入官方
bootstrap 的完整资源，再叠 UBNT 深色覆盖（侧栏蓝条、深色卡片、胶囊按钮/输入项）。
`common.seed` 仍编 `luci-theme-bootstrap`——它是 `@import` 的**底资源**，不是呈现主题，
删了反而会 404。`luci-fix` 每次开机校验依赖，缺失即回退，绝不指向空气。
细节见 `docs/主题与UBNT界面.md`。

### 主题页面为什么不再报错（原说明，保留）

老仓库的「主题页进不去 / dispatcher.lua:427」是两个根因叠加：
`/etc/config/luci` 缺 named `config core 'main'`，以及 `mediaurlbase` 指向
官方 25.12 luci feed 里**并不存在**的 argon / footstrap 主题。

本仓做法：

- **LuCI 后台**：呈现为 UBNT 深色主题，底层用官方 `luci-theme-bootstrap`（最新稳定、feed 里一定有）作 `@import` 资源，
  `files/etc/config/luci` 写死 named `main`；`luci-fix` 每次开机按
  `/www/luci-static/` 实际存在的目录重建主题下拉，永远不会出现幽灵主题。
- **用户真正看到的界面**：`/ubnt/` 概览、`/bridge/` 网桥状态、`/ap/` AP 控制台，
  三页同款 UBNT / UniFi 深色侧栏 + 胶囊 KPI，**独立静态页 + 只读 CGI，不依赖 LuCI 主题**。
  LuCI 万一挂了也照常能开。三页都能直接打开（全互访），非当前模式的页只显示一条提示条，不强制跳走。三页都能直接打开（全互访），非当前模式的页只显示一条提示条，不强制跳走。三页都能直接打开（全互访），非当前模式的页只显示一条提示条，不强制跳走。三页都能直接打开（全互访），非当前模式的页只显示一条提示条，不强制跳走。
- UBNT 皮肤直接移植你 5.4 老仓的 `vs010-ubnt.css` + `vs010-ubnt-skin.js`
  （零侵入：只加 `u-*` 类、外层包壳、不删原 DOM、不额外发请求、零写入端点）。
- 每页都有 6 个互访入口 + 登录/退出 + TTYD :7681 一键入口；竖屏横向滚动不隐藏。
- 想让 LuCI 页脚也出现状态页入口（默认关）：`touch /etc/luci-entry-enable && luci-entry`。

Web 若仍报 427：串口 `sh /usr/sbin/health-fix`（或单跑 `/etc/init.d/luci-fix start`），刷新即可，不用重刷。

## 四、稳定 / 低占用 / 无线（沿用 5.4 老仓 STANDARDS 硬标准）

- 只编：dropbear(SSH) + TTYD(`luci-app-ttyd`) + LuCI 底座/中文 + UBNT 主题（bootstrap 底资源） + 状态页 +
  无线/有线必要驱动 + `ethtool` / `iwinfo`。**第三方 luci-app-\*、科学/下载/统计插件、
  iperf3/htop/nano、firewall4/firewall 全部显式 n**。`verify.sh` 硬校验 luci-app 只能有 1 个。
- 关闭防火墙：编译期显式 n，运行期 `no-firewall` stop+disable、清空 `/etc/config/firewall`、
  关软/硬 flow offload。
- 关闭 IPv6：编译期 `CONFIG_IPV6=n` + 不编 odhcpd/odhcp6c/luci-proto-ipv6；
  运行期 sysctl `disable_ipv6=1` + 删 WAN6 + 关 RA/DHCPv6。
  （NSS 基线保留内核 IPv6 符号，驱动有编译期依赖，只关网络层。）
- WAN + LAN + 2.4G + 5G 全在 `br-lan`（纯二层）；上级 DHCP 照常透传，
  无线侧 DHCP 由独立 nft bridge 表 `l2-guard` 拦截（67→68 / 547→546）。
  ⚠ NSS 卸载后部分报文不过 host bridge hook，属尽力防护，见 `docs/DHCP与SSH防护.md`。
- 端口归属不猜默认路由：`bridge-netfix` 读 sysfs 桥成员 + `eth*` + 无线口动态补齐。
- 温度口径：CPU 取 `/sys/class/thermal` 里 type 含 cpu 的热区；射频取
  `/sys/class/hwmon` 里 `ath11k_hwmon`，按设备树节点标注而不是 phy 编号。读不到如实显示「—」。
- 判速看 `eth0/eth1` + NSS debugfs，**不看 br-lan**（被卸载的流量根本不经过 Linux 网桥）。
- 无线：CN / 5G ch36 HE160 / 2.4G ch1 HE40 / `noscan` 默认不开；
  HE160 开机需约 60 秒 CAC，期间 5G 不可见、2.4G 先起，改 HE80 可免等但吞吐少约 1/3。
  WDS 桥接只用 5G 4addr，2.4G 关闭；AP 模式双频都起。

## 五、板级（两台都要，编译期注入）

官方 25.12 / main / qosmio 25.12-nss 树里都**没有** VS010 / RAX3000Q 的设备定义
（RAX3000Q 2026-09-27 才合入 OpenWrt main，稳定 tag 与 qosmio 25.12-nss 都没有），
所以 `scripts/board-inject.sh` 在编译期注入：

- 自动识别两种 DTS 目录布局（25.12 `qualcommax/files/.../dts/qcom/` 与旧 `qualcommax/dts/`）；
- `board/ipq5018-vs010.6.12.dts`：基于 OpenWrt main 的 PZ-L8 官方 DTS 还原版，
  LED 改实机 mesh=GPIO33 / pwr=GPIO31，补 4bit/512 NAND ECC，**端口排序不动**；
- `board/ipq5018-rax3000q.6.12.dts`：QCA8337 按官方映射（PHY0=WAN、PHY1/3/4=LAN1/2/3、
  port@0 单条 SGMII CPU 链路），8bit/512 ECC（GD5F1GQ5REYIG），compatible 双写
  `cmcc,rax3000q` + `cmcc,rax3000qy`；
- 两台都**不定义按键**（恩山变砖实录：复位键 GPIO 冲突会循环重启、TTL 失联、需编程器）；
  不改 `qcom,bdf-addr`、不改 boot-args、不整份替换 DTS、不把 ART 切片编进固件；
- `DEVICE_PACKAGES` 只补 `ath11k-firmware-ipq5018-qcn6122` + `kmod-ath11k-ahb`
  （两者在 `v25.12.6` 实证存在；后者定义在 `package/kernel/mac80211/ath.mk:339`），
  否则射频根本不 probe。🔴 **不引用 `ipq-wifi-<机型>`**：官方 `v25.12.6` 的
  `ipq-wifi/Makefile` 的 `ALLWIFIBOARDS` 里没有 `cucc_vs010` / `cmcc_rax3000q`，
  引用不存在的包会让 make 打包阶段报缺包；本仓 `ART_CALIBRATION=0` 用官方通用
  `board-2.bin`，本来就不需要机型 BDF。官方 DTS 里 wifi 是 `disabled`，
  本仓改为 `okay` 并配 `ATH11K_MEM_PROFILE_256M`（256M LOW）。

⚠ **这两块板级未在 6.12 主线实机验证**（按同芯片 PZ-L8 骨架 + 好固件 FIT 真实 DTB 融合）。
首次刷务必接 TTL，建议 `device` 先选 `vs010` 单跑一次，成功再 `both`。

## 五之补、无线界面与配置（按真实 v25.12.6 源码实证）

**网桥页 /bridge/ 的「搜索 → 一键加入」**：② 分组 `🔍 搜索 SSID` 调
`/cgi-bin/luci/admin/nwrt/scan`（admin 树 sysauth、`iw dev <iface> scan` 只读）。
结果表格点「选用」自动带入 `peer_ssid` / `peer_bssid` / `ch5g` / `htmode`；
频宽由扫描里的 `STA/VHT channel width` 映射 `160→HE160 / 80→HE80 / 40→HE40 / 20→HE20`，
未广播频宽留空并提示手动选，**不猜**。**密码必须手填**，点选只填表单、绝不自动写配置；
② 分组同时保留手动填写上级 WDS 的 SSID / BSSID / 密码，信道与频宽在 ④ 里手动选。

**AP 页 /ap/ 的弱信号（显示 + 设置）**：状态卡片显示 `rssi_reject_assoc_rssi` /
`rssi_reject_assoc_timeout` / `disassoc_low_ack` / 主动剔除开关与生效范围；设置在 ④ 分组。
按 `openwrt/openwrt @ v25.12.6` 的 `package/network/config/wifi-scripts/files/lib/netifd/hostapd.sh:128,245`
实证，这三个 `rssi_*` 是 **wifi-device 级真实 UCI**（→ hostapd 配置），
`disassoc_low_ack` 默认 1（`:574,611`）。老仓 QSDK 私有的 `db_rssi_thr` / `db_timeout`
**不下发**；本版改用主线等价项，属于「内核升级修复」而非字段照抄。
主动剔除（踢已关联弱客户端）主线无 UCI，由唯一常驻 `nwrt-tick` 每 5 轮一次、
按 `kick_rssi` 用标准 `iw station del` deauth，**默认关**、单轮最多 3 个、不循环踢。
⚠ WDS 是 STA / wpa_supplicant 模式、hostapd 不运行 → 拒绝连接项**如实删除不下发**。

**WDS 回程实况**：`iw dev <iface> link` 实读信号 / TX·RX 速率 / BSSID，
终端表来自 `iw station dump` 并加 RX 速率与距离列。**距离是 FSPL 估算**
（假设 EIRP 20dBm / 5GHz），界面明确标「估算，非实测」，读不到一律留白「—」。

**接口 MAC 全自动**：两块 DTS 本来就用 `nvmem-cells` 从 ART 分区装配 MAC
（VS010 `hw_mac_addr`、RAX3000Q `macaddr_art_0|6`）。新增只读 `nwrt-mac` 扫
`/proc/mtd` 的 ART 分区并列出所有 `/sys/class/net/*` 的 MAC + 来源。
**面板没有任何 MAC 输入框**，不写死、不 `uci set` 覆盖内核；ART 未检出如实沿用 sysfs。

**WMM / MU-MIMO（用户写 MOMU）**：`hostapd.sh:614` 无条件写 `wmm_enabled=1`，
`mac80211.sh:464,492+` 在 HE 模式硬写 `ieee80211ax=1` + `he_mu_edca_*` 参数集。
两者在主线**没有独立 UCI 开关**，所以本版：WMM 显示「hostapd 强制开启」、
MU-MIMO 显示「随 HE160 由 ath11k 固件协商」，`mu_mimo=1` 默认；
用户若选关闭，后端明确提示「主线忽略该选择」，**绝不伪造开关生效**。

## 六、上传与编译

见 `上传说明.txt`。本地先跑：

```bash
sh scripts/verify.sh     # 必须输出 RESULT: PASS
```

然后 `Actions → Run workflow`，选 `baseline` / `device`，push 不触发编译。

## 七、边界（如实说明）

- 本包是**静态重建**：没有实机、没有在 GitHub Actions 上真跑过 `make`，
  交付的是可上传的编译文件 + 本地自检结果；板级与无线以刷完实机为准。
- 好固件是闭源 `qca_ol/umac/ipq_cnss2`（QSDK 12.2 / 5.4.213），本仓是主线 ath11k；
  `.ko` 跨内核必挂、WiFi FW 格式不同、QSDK 单 BDF 不是 `board-2.bin` 容器——
  **能提取文件，不能拷过去加速**。详见 `MIGRATION.md`、`docs/源仓库取证.md`。
- ART 已采集但不编进固件：`ART_CALIBRATION=0` / `CALDATA_DEFAULT=off`，
  默认用官方通用 `board-2.bin`。实机日志证明好固件报 `Caldata not present` 且加载模板 BDF，
  改这条路径风险大于收益。
- NAND V2 补丁（FM25LS01 / FM25LS02BI3）默认关；`nand_patch=true` 且 6.12 基线时
  workflow 已接线调用 `scripts/apply-nand-patch.sh`，`git apply --check` 不过只警告
  不停编。当前 `patches/` 下没有 `.patch`，勾了也只打 warning 跳过；EUCLEAN 风险不变。
- 🔴 **上游 4-bit ECC 补丁（`fb90296` / `0401-spi-spi-qpic-snand-default-to-4-bit-ECC`）
  不需要手动加**：`v25.12.6`、`qosmio 25.12-nss` 的 `patches-6.12/0401`、
  `main` 的 `patches-6.18/0401` 都已内置；本仓两块 DTS 还显式写了
  VS010 `nand-ecc-strength=<4>` / RAX3000Q `<8>` + `step=512`，按 412/417 backport
  直接命中合法 case，根本不走 1-bit 回退路径。详见 `patches/README.md`。
  把邮件原版 diff 放进 `patches/` 只会 `git apply --check` 失败被 warning 跳过。
- **feeds 口径**：workflow 不覆盖上游 `feeds.conf.default`。`v25.12.6` 自带四个 feed
  全部锁具体 commit，比仓库根目录那份「分支对照表」更可复现；`feeds.conf.default`
  仅作人工对照，不参与编译。

## 八、目录

```
.github/workflows/build.yml   单包双模式唯一入口
baseline.env        四条基线（唯一真值）
config/             common.seed + gen-config.sh
scripts/            verify / board-inject / prepare / health-fix / wifi-fullspeed
board/              两台 6.12 DTS + Device / 02_network 注入片段
files/              公共 rootfs（LuCI / UBNT 界面 / CGI / 开机脚本）
files.vs010/ files.rax3000q/ 机型差异
docs/               取证与边界说明（含 模式切换与巡检.md）（含 模式切换与巡检.md）（含 模式切换与巡检.md）（含 模式切换与巡检.md）
reference/          xiangye277 + 5.4 老仓的只读归档
```
