# 新内核 WDS 网桥 / AP 固件（RAX3000Q / QY + 联通 VS010）

一个仓库、**两个独立 workflow**、两台机器、**两种固件**、**三条新内核基线**。
Actions 里点哪个入口就出哪套，push 不触发编译。

## 固件命名：模式 + 实际内核版本 + 日期 + 机型

| 入口 | 文件名 | Release tag |
|---|---|---|
| **`Build WDS Bridge (新内核)`** | **`Nwrt-WDS-<内核版本>-YYYYMMDD-<机型>-*.ubi / *.bin`** | `fw-<内核版本>-时间戳-<机型>-wds` |
| **`Build AP (新内核)`** | **`Nwrt-AP-<内核版本>-YYYYMMDD-<机型>-*.ubi / *.bin`** | `fw-<内核版本>-时间戳-<机型>-ap` |

例：`Nwrt-AP-6.12.116-20261124-vs010-openwrt-qualcommax-ipq50xx-...-sysupgrade.bin`

内核版本由编译期 `make -s kernel_version` **实际抓取**（退回 `LINUX_VERSION`，再退回 `baseline.env`），
不写死、不带任何旧 SDK 编号。日期戳、机型、原文件名后缀、滚动保留 5 次 Release 沿用老仓库格式。

两个入口都支持 `device=both`（默认）/ `rax3000q` / `vs010`。

## 三条基线（Run workflow 时选）

| baseline | 内核 | 无线 | 说明 |
|---|---|---|---|
| **`qosmio-25.12-nss`（默认，最稳）** | **6.12.116** | NSS FW **12.5**；5G 160MHz 773~833Mbps | 推荐：有硬件加速、稳定分支。**两台板级都由本仓注入**（该树整树 `rax3000q` 0 命中，旧文案「实机验证」已纠正） |
| `official-25.12.6` | 6.12.112 | 无 NSS | 官方稳定版，apk；**别拿来要无线满速**（DSA 软转 502M 就跑满双核） |
| `kuncy7-6.18-nss` | **6.18.60** | NSS FW 12.5 优先；5G 160MHz AP→STA 915Mbps、CPU 1~3% | 更高内核尝鲜；不含这两台板级，需自己移植 |

> ⚠ **刷之前确认不死 U-Boot 支持 64 位引导**。本仓三套基线全是 `aarch64`；首次备 3.3V USB-TTL。

## 参考实现：mufeng05/openwrt-cmcc-pz-l8-nss

`https://github.com/mufeng05/openwrt-cmcc-pz-l8-nss` —— 未修改的官方 25.12.5（6.12.94）
+ 高通官方 QSDK 14.0 驱动源码，qca-ssdk/swconfig 取代 DSA，两个独立 GMAC（eth0/eth1）
各自 CPU 口；**有线 + 两个射频全部在 NSS 核内转发，包不进 Linux**。实测有线 949/949 Mbps
@ +0% 主机 CPU、5G 160MHz 697 Mbps @ 2.9%、80MHz 462 Mbps。

它是 **PZ-L8 单板 overlay 仓库**，不含 VS010 / RAX3000Q 板级，所以**不设为可编译基线**
（直接切过去会编不出这两台机器）。可移植的做法已逐条落到本仓：

1. **NSS 固件 12.5 优先**（该仓自测相对 12.2 +65%；kuncy7 ipq50xx feed 亦默认 12.5、同时发 12.2 回退）。
2. **真实加速路径是 ECM→NSS + `wifili` 双射频卸载**；`shortcut_fe`/SFE 连接表为空属预期，
   不再拿 `wifi_offload=1` 当通用总开关——它只存在于 c3po 那条 UCI，无条件 `uci set` 会
   凭空造出 `/etc/config/nss`（已修）。
3. **判速看 eth0/eth1 + NSS debugfs，不看 `br-lan`**：被卸载的流量根本不经过 Linux 网桥
   （该仓实测 eth0/eth1 各 989 Mbps 时 br-lan 只有 52）。状态页已加 NSS 占用、
   加速连接数、`wifili`、NSS 固件版本与 eth0/eth1 实时速率。
4. **温度口径**：CPU 取 `/sys/class/thermal` 里 `type` 含 `cpu` 的热区；射频取
   `/sys/class/hwmon` 里 `ath11k_hwmon`，**按设备树节点标注而不是 phy 编号**
   （一次 wifi reload 就能让 2.4G 从 phy0 变 phy1）。
5. **端口归属不猜默认路由**，直接读 sysfs 桥成员 + `eth*` + 无线口动态补齐。
6. **`DEVICE_PACKAGES` 必须补**：官方 25.12.x 的 `Device/cmcc_pz-l8` 没定义它，
   ath11k 固件与 board data 不在镜像里，射频根本不 probe。本仓 `board-inject.sh` 已给
   VS010 补 `ath11k-firmware-ipq5018-qcn6122 + kmod-ath11k-ahb + 本地 ipq-wifi 包`。

## 无线满速口径（编译期 + 开机双兜底）

`NSS FW 12.5` · `ECM→NSS / wifili` · 国家码 `CN` · 5G `ch36 / HE160` · 本机 BDF + `256M LOW`。

两条必须知道的固有代价（来自参考仓实测）：

- **CN + HE160 覆盖 DFS**：开机 5G 要先做约 **60 秒 CAC**，期间 5G 不可见、2.4G 先起；
  改 HE80 可免等，吞吐少约 1/3（697→462）。
- **2.4G HE40 默认因共存扫描退 20MHz**；`uci set wireless.radio0.noscan=1` 强开 40MHz
  实测 +50%（75→112.5 Mbps），但无视邻区共存，默认不开（最稳）。
- 2.4G 是该平台唯一明确落后项，原因是邻区丢包让速率控制停在 MCS 6–7，**不是配置 bug**。

串口/SSH 跑 `wifi-fullspeed` 一键核对内核、模块、NSS 占用/连接数、eth0/eth1 计数、
射频实况、UCI、BDF 与温度。

## 最稳 / 最少系统问题

- **只编**：SSH `dropbear` + TTYD `ttyd`/`luci-app-ttyd` + LuCI 底座/中文 +
  官方 `luci-theme-bootstrap` + 状态页 + 无线/有线必要驱动。
  （`argon` / `footstrap` 是社区主题，不在官方 25.12 feed，默认不编——见下方「主题页面」）
- **不编**：任何第三方 `luci-app-*`、科学/下载/统计插件、`iperf3/htop/nano`、
  `firewall4`/`firewall`。`verify.sh` 硬校验 `luci-app` 只能有 1 个（ttyd）。
- **WAN + LAN + 2.4G + 5G 全在 `br-lan`**（纯二层）。
- **关闭防火墙**：编译期显式 n，运行期 stop+disable、清空 `/etc/config/firewall`、关软/硬 flow offload。
- **防止无线端 DHCP**：独立 nft bridge 表拦 `wlan*` / `phy*-ap*` 进来的 `67→68`、`547→546`；
  有线侧上级 DHCP 照常透传。⚠ NSS 卸载后部分报文不过 host bridge hook，属尽力防护，
  详见 `docs/DHCP与SSH防护.md`。

## 界面

`/bridge/`（WDS）、`/ap/`（AP 控制台）、AP 简版 `/bridge/` 三份页面统一显示：
CPU 温度（PZ-L8 口径）+ 射频温度、NSS 数据面/占用/连接数/固件、eth0/eth1 实时速率、
内核与基线、5G 配置与 DFS 提示、2.4G 共存、DHCP 防护、SSH/TTYD 状态，以及
**TTYD :7681 一键入口**。读不到传感器如实显示「—」。

### 主题页面为什么不再报错（老仓库那个坑）

老仓库「主题页进不去」是**两个根因叠在一起**：

1. `/etc/config/luci` 缺 `config core 'main'`（named section）。它是 `luci-base` 的
   conffile，sysupgrade 勾「保留配置」或旧 overlay 残留会盖掉编译期文件；此时任何
   `uci set luci.main=...` 都会让 UCI 造出**匿名** `config main`，LuCI 按名字找
   `main` 找不到 → `dispatcher.lua:427`，整个 `/cgi-bin/luci` 打不开。
2. `mediaurlbase` 写死 `/luci-static/argon`、主题下拉里还列 `Argon` / `Footstrap`，
   但**这两个是社区主题，官方 25.12 luci feed 里没有**。写 `=y` 会被
   `make defconfig` 静默丢掉，镜像里只有 bootstrap；配置却指向空气 → 白屏，
   在「系统 → 语言与样式」点一下幽灵主题就 500，之后再也进不去。
   老仓库 `port-overlay.sh` 还会在编译期硬塞一行 `option Footstrap`，正是元凶。

本仓四层兜住：

| 层 | 做法 |
|---|---|
| 编译期 `.config` | 只 `luci-theme-bootstrap=y`；argon/footstrap 显式 `=n`；`gen-config.sh` 发现 feed 里没有的包会**从 .config 删掉**而不是只打 warning |
| 编译期配置 | `files/etc/config/luci` 写死 named `config core 'main'` + `mediaurlbase=/luci-static/bootstrap` + themes 段只 `Bootstrap`；`port-overlay.sh` 反过来**清理**幽灵项 |
| 每次开机 | `luci-fix`(START=18) 与 `bridge-netfix`(START=21) 各跑一次：重建 named main、按 `/www/luci-static/` 实际目录生成主题下拉、修正指向空气的 mediaurlbase、清 LuCI 缓存 |
| 页面本身 | `/bridge/`、`/ap/` 是**独立静态页 + 只读 CGI**，不依赖 LuCI 主题，LuCI 万一挂了也照常能开；CGI 取不到数据时显示明确原因，不再静默留一片「—」 |

编了 argon 就自动用 argon（观感同老仓库），没编就稳稳用 bootstrap，下拉里
**永远不会出现不存在的主题**。想在 LuCI 页脚加状态页入口（默认关闭，避免改主题
模板再引入风险）：`touch /etc/luci-entry-enable && luci-entry`。

Web 若仍报 427：串口 `sh /usr/sbin/health-fix`（或单跑 `luci-fix`），刷新浏览器即可，**不用重刷**。

## 前两问合并结论（一次说清）

| 问题 | 结论 | 本包怎么落地 |
|---|---|---|
| 无线是不是按两个路由改的 | 射频参数**两台共用**（硬件同构，ART 实证差异仅 0.56% / 1.95%）；按机型分的是**校准数据**，不是 wireless 配置 | `files*/etc/config/wireless` 不拆；`board-inject.sh` 严格按机型取 BDF；**RAX3000Q 补 `DEVICE_PACKAGES`**（缺 ath11k 固件射频根本不 probe） |
| NAND 补丁加了吗 | 之前没加；现在**备好但默认关** | `patches/440-…patch` + `apply-nand-patch.sh`；workflow 勾 `nand_patch` 且 6.12 基线才应用，6.18 跳过，`git apply --check` 不过只警告不停编 |
| ART 要不要采集修复 | 已采集；但**不把 ART 校准编进固件** | `art/art-truth.conf` + `art-check` 自检；`ART_CALIBRATION=0` 默认，保留官方通用 `board-2.bin` 兜底 |

三件事同一个原则：**只补能实证的，不砸已经能工作的链路**。
完整推理见 **[docs/ART与无线校准.md](docs/ART与无线校准.md)** 与 **[patches/README.md](patches/README.md)**。

## 第 40 次：实机日志纠正了 BDF 来源（比上面两问更重要）

新上传的 `ATR文件/` 里有 **VS010 好固件实机串口日志**（`art/oem-bootlog.txt`）和
两份 **U-Boot**。dmesg 白纸黑字：

```
Downloading BDF: IPQ5018/bdwlan.b10, size: 131072
Downloading BDF: qcn6122/bdwlan.b60, size: 131072
WARN: Caldata not present ...   BDF version: 1 CAL version: 0 Status: 0
```

而 `bdwlan.b10` / `bdwlan.b60` 的 MD5 **正好等于** `vs010/bdf/` 里的模板 BDF，
**不等于 ART 切片**。→ **好固件用的是模板 BDF，ART 切片根本没被加载**。

上一版把 ART 切片当「本机产线校准的更好来源」、允许用它合成 `board-2.bin`，
**方向错了**。本版已纠正：

- 本机校准改用 `art/make-board2.py from-oem`（data 取实证模板 BDF，
  board_id `0x10=16` / `0x60=96` 有实机依据），官方 `ath11k-bdencoder` 交叉验证通过
- `slice` 降级为纯采集/存档；`board-inject.sh` 检出容器含 ART 切片 MD5 会警告
- `art-check` 新增无线 MAC 占位检测（实机 5G 是 `00:03:7F:12:EF:EF`，ART 头真 MAC 没被无线用）
- `VERIFIED` 仍为 0：`lsmod` 证实好固件是闭源 `qca_ol/umac/ipq_cnss2`，无 ath11k、无 mac80211
- **NAND 判断升级**：两份 U-Boot 名称表都含 `FM25LS01` / `FM25LS02BI3` →
  V2 批次真实存在、补丁对 V2 必需；但 EUCLEAN 风险不变，默认仍关

不改 DTS 的 `mem mode`（实机闭源栈是 `[2]`，主线 ath11k 本仓是 `1`，不能抄）。

## 第 41 次：两个闭源好固件真解包 + 仓库体检

新仓库的老固件目录（`Actions-OpenWrt-RAX3000Q-VS010-WDS / 3000Q-VS010-固件`）
里两个 27 MB `factory.bin` 已解开：**Linux 5.4.213 / QSDK 12.2 / OpenWrt 19.07 /
WLAN.HK.2.8-01492**，UBI → FIT(kernel + 真 DTB) + squashfs rootfs。无线/有线参数、
驱动清单、DTB、启动脚本、4 份 BDF 全部拿到，存档在 `art/oem-qsdk-bdf/`。

**结论：能提取文件，不能拷过去加速。** 好固件是闭源 `qca_ol/umac/ipq_cnss2`（无 ath11k、
无 mac80211），本仓是 6.12 主线 ath11k；`.ko` 跨内核必挂，WiFi FW 格式不同，
QSDK 单 BDF 不是 `board-2.bin` 容器。能迁移的工作方式（ECM→NSS、qca-ssdk 双 GMAC、
判速看 eth0/eth1、不加载 caldata、RPS 口径）**本仓早已落地**。
详见 **[docs/OEM-QSDK12.2-取证报告.md](docs/OEM-QSDK12.2-取证报告.md)**。

本次还**再纠正第 40 次一句断言**：「好固件 BDF 的 MD5 == 模板 BDF」无实证、已作废；
四套 BDF（好固件两台 / 模板 / 4.4.60 / ART 切片）互不相同。
`from-oem` 降级为实验性可选，默认不装配；「ART 切片禁止进固件」不变且更有理由。
两台真实 DTB 里确实有 `qcom,bdf-addr`（U-Boot 里没有），但那是 cnss2 的，禁止抄进 ath11k DTS。

新增 `oem-stack-check`（只读自检，挂 `health-fix` 第 7 段）、`oem-qsdk-truth.conf`、
`修复总览.md`；**DTS / workflow / config / patches / wireless 一字未动**。

**仓库体检**：2026-11-24 16:10 clone 实测，第 40 次总修复包 109 个文件里
**108 个逐字节一致、0 缺失**，只差 `.gitignore` 末尾 3 行；另有 1 字节垃圾文件
`.github/workflows/build-ap` 建议删除。本次总修复包会带上正确的 `.gitignore`。

> 以后每次修复都出 **「总修复可上传文件」**（累积全量包），不再只给增量包。

## ART 已采集，但无线设置按「不砸已验证链路」修

仓库根目录的两份完整 `0:ART`（VS010 / RAX3000Q）已离线采集完，真值在
`art/art-truth.conf`，完整报告在 **[docs/ART与无线校准.md](docs/ART与无线校准.md)**。

三个结论：

- **两台射频同构**：切片偏移、长度、`magic=01000404` 全同，差异只有 0.56% / 1.95%
  → `files/etc/config/wireless` 的 `CN` / 5G `ch36 HE160` / 2.4G `ch1 HE40`
  **继续两台共用，不拆两份**；按机型分的是校准数据，不是射频参数。
- **校准逐台不同**：两台切片互差 738 / 2552 字节 → `board-inject.sh` 严格按机型取
  `art/out/<机型>/board-2.bin`，禁止跨机回落。
- **默认不引用 ART**：`ART_CALIBRATION=0` / `CALDATA_DEFAULT=off`，固件仍用官方通用
  `board-2.bin`。实机日志证明好固件报 `Caldata not present` 且加载的是模板 BDF，
  改这条路径风险大于收益。想用本机校准，用 `make-board2.py from-oem`（**不要用 ART 切片**）
  合成容器并显式 `ART_CALIBRATION=1`，编完 TTL 验证射频再定。

实际修好的四处：**RAX3000Q 补 `DEVICE_PACKAGES`**（缺这项射频根本不 probe）、
**拒绝把单个 BDF 改名当 `board-2.bin`**（容器签名校验）、
**实机 `art-check` 自检**（`health-fix` 第 6 段顺带跑，只读、不改 flash）、
**BDF 来源纠正**（`from-oem` + ART 切片禁用警告，见上一节）。
ART 头 MAC 也实证了 VS010 DTS 的 `macaddr@0/@6` 是对的；RAX3000Q 头全 FF，
`art-check` 只提示、不擅自写 MAC。

出厂默认与排障见 **[FIRMWARE.md](FIRMWARE.md)**，基线对照见 **[MIGRATION.md](MIGRATION.md)**。

## 可以删除的文档（请你自己删，我不替你动）

本仓不再维护逐轮修订日志，下列文件/段落已无编译依赖，可按需清理：

| 路径 | 性质 | 建议 |
|---|---|---|
| `CHANGES-20261124.md` | 上一轮修订日志 | **整文件删**（结论已并入本 README 与 FIRMWARE.md） |
| `MIGRATION.md` 第 9 节 / 整文件 | 迁移对照（已改为结论，非日志） | **可选删**：不需要迁移对照就整文件删，保留也无害 |
| `oem_extract/fw_version.txt` | 老固件版本日志 | 整文件删 |
| `vs010/wifi-dump-text.sh` | 老固件文本抓取脚本 | 整文件删（BDF 已落盘，不再需要） |
| `vs010/wifi-truth.conf` 里的 `REF_*` / `LIVE_KERNEL` 行 | 旧镜像溯源记录 | **只删这些行**；`VERIFIED` / `board_id` / MAC / BDF / `ART_*` 真值行必须保留，`board-inject.sh` 与 `art-check` 要读 |
| `oem_extract/qcn6122_bdwlan.bin` | 50 字节的 `404 Not Found` 页面，不是 BDF | 整文件删（真的 BDF 是 `qcn6102_bdwlan.bin` / `vs010/bdf/`） |
| `oem_extract/fw_version.txt` | 同上，50 字节 404 | 整文件删 |
| `firmware/build.log`、`firmware/old_build.zip`、`firmware/vs010-openwrt-firmware.zip` | 老仓库的失败日志与 534B 空包 | 整个 `firmware/` 删 |
| `.github/workflows/build-ap` | 1 字节空文件（不是 workflow） | 整文件删，只保留两个 `.yml` |

`README.md` / `FIRMWARE.md` / `board/README.md` / `docs/DHCP与SSH防护.md` /
`docs/ART与无线校准.md` / `art/` / `patches/` 是常驻说明与真值，保留。

上传后本地先跑 `sh scripts/verify.sh`，输出 `RESULT: PASS` 再 Run workflow。

## 第 43 次：第一次真编译的日志复盘与编译链修复

第一次 Run workflow 的两份日志都被 **`verify.sh` 的一个纯卫生项**（`.gitignore` 缺末尾
3 行）卡死：`RESULT: FAIL (1 项)` → `set -euo pipefail` 中断 → **没有 clone、没有 feeds、
没有 make**，`build.log` 都不存在。不是内核/驱动报错。

修完之后我又在真实 `qosmio/openwrt-ipq @ 25.12-nss` 树上按 `prepare.sh` 顺序预检，
发现两道**必然停编**的关卡，一并修掉：

1. **DTS 目录布局**：25.12 的 dts 在 `target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/`，
   旧 `board-inject.sh` 只认 `qualcommax/dts/` → 会报「不是 ipq50xx 源码树」。已新增
   `qualcommax-files` 布局；`02_network` 锚点也改成兼容 `pz-l8|` 续行写法。
2. **RAX3000Q 板级缺失**：该树整树 12317 个路径里 `rax3000q` **0 命中**，`ipq50xx.mk`
   没有 `Device/cmcc_rax3000q`。`baseline.env` 旧注释「树内原生、实机验证过」是错的，
   已纠正为 `inject:pz-l8-skeleton`；新增 `board/ipq5018-rax3000q.6.12.dts` 并在编译期注入设备定义。

另外 `verify.sh` 现在**分级**：49 条纯文档/文案/卫生判据降为非阻断警告，
47 条真阻断项保留，`RESULT: PASS（N 项非阻断警告）`，`.gitignore` 这种项再也不会卡死编译。
`gen-config.sh` 加了 gawk 检测与 defconfig 失败排错提示。

⚠ **RAX3000Q 板级未在 6.12 主线实机验证**（按同芯片 PZ-L8 骨架 + 好固件 FIT 真实 DTB 的
model/compatible 融合，故意不定义 keys/leds、不引用 nvmem MAC）。首次刷务必接 TTL，
**建议 `device` 先选 `vs010` 单跑一次**，成功再 `both`。

完整复盘与本地预检记录见 **[docs/编译链预检与板级缺口.md](docs/编译链预检与板级缺口.md)**。

## 第 44 次：用你上传的 DTS / DTB 校正两台板级

老仓库 `3000Q-VS010-固件/DTS/` 新上传的 6 份资料（尤其 **`vs010.dtb`**，45 KB
原厂运行态 FDT）全部只读存档到 `docs/oem-dts/`，并额外抓到了
`openwrt/openwrt @ main` 的 `ipq5018-rax3000q.dts` **逐字节官方原文**做交叉校验。

**实证结论**：RAX3000Q/QY 确实在 2026-09-27 合入 OpenWrt **main**，但
**v25.12.6 稳定 tag 和 qosmio 25.12-nss 都没有** → 三条基线仍需本仓注入板级。

改了这些（按机型分别修，不再两台共用一套猜值）：

- **VS010**：LED 从 PZ-L8 的 GPIO35 改成实机 `mesh=GPIO33` / `pwr=GPIO31`；
  补 `4bit/512` NAND ECC；头注释纠正 fork 来源 `xiangye277` 版
  **已被作者本人否定（GPIO 与 switch port 配置有误）**。
- **RAX3000Q**：QCA8337 端口按官方映射整段改写
  （`PHY0=WAN`、`PHY1/3/4=LAN1/2/3`、`port@0` 单条 SGMII CPU 链路）；
  补 `8bit/512` ECC（GD5F1GQ5REYIG）；compatible 双写 `cmcc,rax3000q` +
  `cmcc,rax3000qy`；`02_network` 两个分支都注入。

**坚决不改的**：两台都不定义 keys/leds（恩山变砖实录：复位键 GPIO 冲突会
循环重启、TTL 失联、需编程器）；VS010 端口排序不改（正确基线 maxdarksol 全文
未取到，改错网口全灭，而 WAN+LAN 全在 `br-lan` 故 label 错位不影响桥接）；
5G `bdf-addr`、`boot-args`、官方 DTS 整份替换一律不做（跨栈/跨绑定差异）。

逐项核对表、变砖警示、刷前备份清单与刷后排查见
**[docs/板级真值-第44次.md](docs/板级真值-第44次.md)**。

## 第 44 次（配置收口）：IPv6 关闭 · DHCP 防护 · 插件精简

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

## 第 45 次：编译失败修复 + 机器狗默认停用（2026-11-24）

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

## 第 46 次：编译链已跑通，卡在上游树自带坏 DTS（2026-11-25）

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

## 第 47 次：SSH 可达性 / 内网 NTP / 删 WAN / STP / 干净系统（2026-11-25）

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

## 第 55 次：彻底移除「真缺阻断」，B 层改为纯诊断（2026-11-25）

> 第 54 次包上传后，编译**再次在 make 之前**断掉：
> `🔴 冻结基线包在当前源码树里完全找不到（Kconfig 无符号、无包源）：luci-i18n-base-zh-cn kmod-bridge`
>
> 又是判据写错了层，不是源码 / feeds / 上传问题。第 54 次仍留了
> 「符号 + 包源都找不到 → 真缺 → `exit 1`」，而这两项是**平台提供 / 模板生成**：
> `kmod-bridge` 由 25.12 内核 `CONFIG_BRIDGE=y` 内建（`netsupport.mk` 已无该 kmod 定义）；
> `luci-i18n-base-zh-cn` 由 `luci.mk` 按 `po/zh-cn` 模板生成，树里没有同名包目录。
> 🔴 **定论：「树里能不能找到包源/符号」与「插件有没有被删」没有关系**，绝不能当阻断条件。

### 最终口径

| 层 | 规则 | 停编？ |
|---|---|---|
| 🔴 A 层 seed 声明 | `config/*.seed` 里 29 项逐条 `=y` | **会** —— 这才是「只增不减」 |
| 🔴 核心锚点 5 项 | `dropbear / ttyd / luci-app-ttyd / ath11k-firmware-ipq5018-qcn6122 / kmod-ath11k-ahb` defconfig 后精确 `=y` | **会** —— 真丢功能才拦 |
| ⚪ 其余一切 | Kconfig 收敛 / 符号合并 / 平台提供 / 模板生成 / 机型条件项 | **不会** —— 只 `::warning::` + 写 `build.env` |

`REAL_MISS` / `_pkg_known_anywhere()` 整段删除；新增
`PLATFORM_PROVIDED="kmod-bridge luci-i18n-base-zh-cn"` 只计入诊断。
B 层之后仅剩 2 处代码 `exit 1`（核心锚点收敛 / 设备符号丢失），**无任何包相关阻断**。
`verify.sh` 加第 55 次判据，防止以后再把包源存在性当阻断条件加回来。

六种场景实测：复现本次报错 → PASS；全部 =y → PASS(29/29)；rax3000q → PASS；
删 seed 里 `luci-app-ttyd` → A 层精确拦（只报 1 项）；核心锚点收敛 → B 层拦；新增 → PASS。

🔴 **82 项冻结基线一个没动、一个没删**；`config/*.seed` 29 个 `=y` 一字未改。
第 54 次构建树野文件排除 / nft 报红、第 51 次 NTP 5 分钟循环、第 50 次改 IP 防护、
第 49 次机器狗、管理网段、SSH/TTYD、防火墙/IPv6 关、WAN+LAN 同桥、STP、简洁日志全部原样保留。
