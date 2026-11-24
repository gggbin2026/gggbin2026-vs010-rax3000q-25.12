# QSDK 12.2 好固件取证报告（第 41 次 · 2026-11-24）

> **一句话结论**：两个 27 MB 闭源固件**真的解开了**，无线/有线的参数、驱动清单、拓扑、启动顺序全部拿到，
> 也成功提取出 4 份 BDF、regdb、FW 版本等文件；但**没有一份二进制能直接搬进新仓库让有线无线加速**——
> 好固件是 **Linux 5.4.213 + 闭源 qca_ol/umac/ipq_cnss2**，新仓库是 **Linux 6.12 + 主线 ath11k/mac80211**，
> 内核 ABI 与无线栈都互斥。能迁移的是**工作方式与参数口径**，而这些口径本仓早就按 PZ-L8 参考仓落地了。
> 本次还**纠正了第 40 次一句没有实证依据的断言**（详见第五节）。

---

## 一、材料与解包方法

来源：`gggbin2026/Actions-OpenWrt-RAX3000Q-VS010-WDS` → `3000Q-VS010-固件/`

| 文件 | 大小 | 身份 |
|---|---|---|
| `Nwrt-QSDK12.2-2024-04-16-...-cucc_vs010-squashfs-nand-factory.bin` | 27,394,048 B | VS010 好固件 |
| `Nwrt-QSDK12.2-2024-04-16-...-cmcc_rax3000qy-squashfs-nand-factory.bin` | 27,394,048 B | RAX3000Q 好固件 |
| `VS010-smem_0-ART.bin` / `RAX3000Q-mtd13-0ART` | 各 1 MB | 与仓库根目录两份 MD5 完全一致 |
| `VS010文件.txt` | 14 KB | 好固件实机串口日志（第 40 次已存档） |
| 两份 `uboot-*.bin` | 各 640 KB | 第 40 次已取证 |

两个 bin 都是 **UBI image version 1**：

```
PEB 0x20000 / VID @0x800 / DATA @0x1000 / LEB 0x1F000 / 209 PEB
卷表：kernel(vol0) / rootfs(vol1) / rootfs_data(vol2，空)
vol0 = FIT：/images/kernel@1 = "ARM OpenWrt Linux-5.4.213"（gzip）
            /images/fdt@1   = 未压缩 dtb（VS010 43140 B / RAX3000Q 43778 B）
vol1 = squashfs rootfs（2695 / 2699 条目），hsqs 魔数 @0x441000
```

手写 UBI 重组（QSDK 的 VID header 字段偏移与标准 differed，`vol_id@8 / lnum@12`），
`unsquashfs` 解出 rootfs，再从 FIT 抽出真实 dtb 用 `vs010/tools/parse-fdt.py` 解析。
**全程离线，没碰设备，没联网取闭源源码。**

> 老仓库 `README_FIX40.md` 当时说「5.4 / QSDK 12.2 闭源驱动拉不到，网盘全 403」——
> **你现在把它们直接传到 GitHub，这一步就通了。** 本次相当于补上了第 40 次缺的那块材料。

---

## 二、无线：源码/参数/工作方式（首次从好固件直接取证）

### 2.1 驱动栈与内核

| 项 | 值 |
|---|---|
| 内核 | **5.4.213**（FIT description 实证） |
| 发行版 | OpenWrt 19.07-SNAPSHOT, r0-f3013a33b |
| WiFi FW | **`WLAN.HK.2.8-01492-QCAHKSWPL_SILICONZ-1 v1`**（`fw_version.txt`，42 B） |
| 无线 .ko | `qca_ol` / `umac` / `wifi_3_0` / `qdf` / `ath_pktlog` / `monitor` / `mem_manager` / `ipq_cnss2` / `cfg80211` |
| **没有** | **无 `ath11k.ko`、无 `mac80211.ko`**（`/lib/modules` 与实机 `lsmod` 双证） |
| 模块总数 | 160 个 `.ko`（vs010） |

### 2.2 真实 DTB 里的无线节点（★ 比反编译 DTS 稿更硬）

```
/soc/wifi@c000000   qcom,cnss-qca5018 / qcom,ipq5018-wifi
    qcom,board_id      = <0x10>   ← VS010 2G；RAX3000Q 是 <0x24>
    qcom,bdf-addr      = <0 0 0x4c400000 0 0 0>
    qcom,caldb-addr    = <0 0 0 0 0 0>
    qcom,caldb-size    = <0>
    qcom,tgt-mem-mode  = <2>
    qcom,multipd_arch  （q6v5_wcss_userpd1）
/soc/wifi1@c000000  qcom,cnss-qcn6122 / qcom,cnss-qcn9100
    qcom,board_id      = <0x60>   ← 两台相同
    qcom,bdf-addr      = <0 0 0x4d300000 0 0 0>
    qcom,caldb-addr    = 0 / caldb-size = 0
    qcom,tgt-mem-mode  = <2>
```

对应的保留内存节点：`/reserved-memory/q6_ipq5018_data@4C400000`、
`q6_qcn6122_data1@4D300000`、`nss@40000000`、`q6_code_data@4B000000` 等。

**两台的 2G `board_id` 不一样**（VS010 `0x10`=16 / RAX3000Q `0x24`=36），5G 都是 `0x60`=96。
这与「按机型分校准」完全一致，也说明**不能把一套 board_id 两台通吃**。

`caldb-addr=0 / caldb-size=0` 是 DTS 级铁证，和实机日志的
`WARN: Caldata not present` / `BDF version: 1 CAL version: 0 Status: 0` 互相印证：
**好固件不加载独立 caldata，校准信息在 BDF 里，通过 QMI WLFW (`bdf_dnld_method 1`) 下发。**

> ⚠ `qcom,tgt-mem-mode = 2`、`qcom,bdf-addr` 这套 6 元组是 **闭源 cnss2 的 DDR 搬运机制**。
> 主线 ath11k 用 rootfs 里的 `board-2.bin` 容器 + `qmi-board-id`，**照抄会直接 probe 失败**。
> 第 40 次从 U-Boot strings 判定「无 `cnss2.bdf_*` / 4c400000 参数」只对 U-Boot 成立；
> **DTB 里确实有这些地址**，本次把它补正了。

### 2.3 BDF：四套互不相同（★ 这里纠正了上一版）

从 factory.bin 里真解出的 `bdwlan.b10` / `bdwlan.b60`：

| 来源 | 2G (131072 B) | 5G (131072 B) |
|---|---|---|
| **5.4.213 VS010 好固件** | `4ce1ecfc…` | `80badcdd…` |
| **5.4.213 RAX3000Q 好固件** | `4b9aba89…` | `e43c4cf0…` |
| 4.4.60 老固件（`oem_extract/rootfs.ubi`） | `12f3d732…` | `6b97dd3d…` |
| 本仓模板 `vs010/bdf/board-cucc_vs010.*` | `c7d89771…` | `0aadbd42…` |
| ART 切片（VS010 / RAX3000Q） | `26b9b9ad…` / `9a78b59f…` | `dcf46e01…` / `ef733f2c…` |

实机 dmesg 只给了**文件名与大小**，没有 MD5。

> **第 40 次断言「bdwlan.b10/b60 的 MD5 == 模板 BDF」是错的**——当时没拿到 5.4 固件，
> 把别处的判断套了过来。本次实证：**好固件 BDF ≠ 模板 BDF ≠ 4.4.60 BDF ≠ ART 切片，且两台互不相同**。
> 模板 BDF 的等价性没有证据，**默认不进固件反而更安全**；`from-oem` 已降级为「实验性可选」，不再宣称实证等价。

4 份 BDF + `regdb.bin` + `fw_version.txt` 已提取到 `art/oem-qsdk-bdf/`（含 MD5 清单），
**只读存档、不参与编译、不跨机使用**。

### 2.4 WiFi FW 与启动顺序

`/lib/firmware/IPQ5018/` 下：`Data.msc`(719950 B)、`q6_fw.b00…b26` + `flist`/`mdt`、
`m3_fw.b00…b02`、`bdwlan.b10/.b20/.b21/.b22/.b23/.b24/.bin`、`regdb.bin`(24278)、
`fw_ini_cfg.bin`(203)、`firmware_rdp_feature*.ini`；`qcn6122/` 子目录另有一套。
`regdb.bin` 两台/两目录共 4 份逐字节相同。

运行期工作方式（`wifi_fw_mount` 19872 B + hotplug）：

```
wifi_fw_mount(00)  → 挂 WIFI_FW squashfs 分区，软链出 /lib/firmware/{IPQ5018,qcn6122}/*
qca-ssdk(16) / qca-nss-ecm(19/26) / cnss_diag(19)
qca-nss-drv(70) / wifi_fw_done(96)
load_cnss2(00) → insmod ipq_cnss2 + cnssdaemon
11-wifi-fw hotplug → mount_wifi_fw "IPQ5018" → load_bin 经 /sys/class/firmware 下发
rc.local: sleep 10; wifi up
```

---

## 三、有线：拓扑与加速工作方式

### 3.1 真实 DTB

```
/soc/ess-instance/ess-switch@0x39c00000   qcom,ess-switch-ipq50xx
/soc/ess-instance/ess-switch1@1           qcom,ess-switch-qca83xx   ← QCA8337 外置交换
/soc/dp1  qcom,nss-dp  → ethernet0 别名
/soc/dp2  qcom,nss-dp  → ethernet1 别名
/soc/nss@40000000          qcom,nss
/soc/nss-common            qcom,nss-common
/soc/nss-dp-common         qcom,nss-dp-common
/soc/qcom,nss_crypto       qcom,nss-crypto
clock-names 里 gmac0/gmac1 两套独立 cfg/sys/ptp clk + nss_port1/port2 rx/tx clk
```

→ **两个独立 GMAC 各自 CPU 口，qca-ssdk + swconfig（非 DSA）；被 NSS 卸载的流量不经过 Linux 网桥。**
这正是 `baseline.env` 里 `REF_PZL8_TOPOLOGY` 写过的口径，本次从两台好固件的 DTB 直接坐实。

`board.d/02_network`（两台文件逐字节相同，靠 `board_name` 分支）：

| 机型 | 生成方式 |
|---|---|
| `cucc,vs010` | `ucidef_set_interfaces_lan_wan "eth1" "eth0"`（两个独立接口，无 switch） |
| `cmcc,rax3000qy` | `ucidef_add_switch "switch1" "5u@eth0" "6u@eth1" "2:lan:1" "3:lan:2" "4:lan:3" "1:wan"` |

**两台有线接法本来就不同**，这点对以后排错有用，但不能照搬进本仓的 DSA/br-lan 全桥模式。

### 3.2 加速参数（运行期，可迁移的是口径）

| 文件 | 内容 |
|---|---|
| `/etc/config/ecm` | `option acceleration_engine 'auto'` |
| `init.d/qca-nss-ecm` | `auto=0 / nss=1 / sfe=2 / ppe=3 / nss-sfe=4 / ppe-sfe=5`；桥加速检查 `debugfs/ecm/ecm_{nss,sfe,ppe}_ipv4` |
| `/etc/config/nss` | `qca_nss_0` / `qca_nss_1` + `option enable_rps '1'` |
| `init.d/qca-nss-drv` | `nss_queue1→CPU mask 2`、`queue2→4`、`queue3→8`；`sysctl dev.nss.rps.enable=1` |
| `/etc/config/qcacfg80211` | `option enable '1'` |
| `modules.d` | `30-qca-ssdk-nohnat` / `31-qca-nss-dp` / `32-qca-nss-drv` / `51-qca-nss-drv-pppoe` / `52-qca-mcs` |
| `.ko` | `qca-nss-drv` / `qca-nss-dp` / `qca-ssdk` / `ecm` / `ecm_ae_select` / `qca-mcs` / `qca-nss-macsec` / `hyfi-bridging` |
| `firewall.d/qca-nss-ecm` | `-A FORWARD -m physdev --physdev-is-bridged -j ACCEPT`；`zone_wan_forward` 前插 `RATE-LIMIT 1000/sec burst 1000` |

---

## 四、能不能提取有用文件用到新仓库来加速？

### 能提取（本次实际拿到了）

| 类别 | 文件 | 数量 |
|---|---|---|
| 参数/配置 | `ecm` / `nss` / `qcacfg80211` / `cnss_diag` / `board.d/02_network` / `rc.local` / `sysctl.conf` | 全部 |
| 启动脚本 | `qca-nss-drv` / `qca-nss-ecm` / `qca-ssdk` / `load_cnss2` / `wifi_fw_mount` / `wifi_fw_done` / `hotplug.d/*` / `firewall.d/*` | 全部 |
| 真实 DTB | 两台的 `/images/fdt@1` | 2 份 |
| 固件 | `q6_fw.*` / `m3_fw.*` / `Data.msc` / `bdwlan.bXX` / `regdb.bin` / `fw_version.txt` | 全套 |
| 驱动 | `/lib/modules/5.4.213/*.ko` | 160 个 |

其中 4 份 BDF + regdb + fw_version 已存进 `art/oem-qsdk-bdf/`。

### 不能搬（这是关键，别白费功夫）

| 想搬的东西 | 为什么不行 |
|---|---|
| **`.ko`（qca_ol / ipq_cnss2 / qca_nss_drv / ecm / qca_ssdk）** | 好固件 **5.4.213**，本仓 **6.12.x**。vermagic、导出符号、cfg80211 ABI 全不匹配，`insmod` 必 `Invalid module format`；且闭源 qca-wifi 与 `ath11k + mac80211` 互斥。老仓库第 40 次在「4.4.60 vs 5.4.164」之间就验证过，跨到 6.12 更不可能。 |
| **`q6_fw.*` / `m3_fw.*` / `Data.msc`（WLAN.HK.2.8）** | 主线 ath11k 用 `ath11k-firmware` 的 `amss.bin` / `m3.bin` / `board-2.bin`，文件布局与 FW 分支都不同；本仓口径是 NSS FW 12.5 + `WLAN.HK.2.7.0.1`，混用会起不来。 |
| **`bdwlan.b10` / `bdwlan.b60` 单 BDF** | QSDK cnss2 吃「单 128 KB BDF + DTS bdf-addr」；主线 ath11k 吃 `QCA-ATH11K-BOARD` 容器。单个 BDF 直接改名会让两个射频解析失败（老仓库 VS010 5G 弱的根因之一）。而且**四套 BDF 互不相同**，没有一份被证明等价于本仓模板。 |
| **`regdb.bin`（24278 B）** | 主线用 `regulatory.db` + CRDA/regdb 机制，格式不同。 |
| **DTB 的 `bdf-addr` / `tgt-mem-mode=2` / `board_id`** | 属于闭源 cnss2 节点属性，主线 ath11k 不认；照抄会 probe 失败。 |

> 一句话：**「提取文件」做到了，「拷过去就加速」做不到**。固件不是瓶颈，
> 瓶颈是**驱动栈 + 内核版本**（老仓库 `README_FIX40.md` 也是这个结论，本次用 5.4 真固件再次坐实）。

### 能迁移、而且本仓已经落地的

| 口径 | 本仓位置 |
|---|---|
| ECM→NSS 是唯一真实加速路径，SFE 不干活 | `baseline.env` `WIFI_OFFLOAD_PATH=ecm-nss`、`wifi-fullspeed.sh` |
| 两个独立 GMAC / qca-ssdk / 被卸载流量不进 Linux 网桥 | `baseline.env` `REF_PZL8_TOPOLOGY` + 两份 workflow 的 Release 说明 |
| 判速看 `eth0/eth1 + NSS debugfs`，不看 `br-lan` | 两份 workflow 的「⚠ 纯二层桥」提示 + 新增 `oem-stack-check` |
| NSS FW 12.5 优先、12.2 回退 | `baseline.env` / `wifi-fullspeed.sh` |
| 不加载独立 caldata、不引用 ART 切片 | `CALDATA_DEFAULT=off` / `ART_CALIBRATION=0` / `board-inject.sh` 警告 |
| CN / ch36 / HE160 / 本机 BDF / 256M LOW | `wifi-fullspeed.sh` |
| 无线端 rogue DHCP 拦、firewall4 编译期关 | `l2-guard` / `99-no-firewall` |

### 想要「好固件那种满速」，现实只有三条

1. **直接用 NWRT 官方固件**（最省事，用户手上这两个 27 MB 就是）。
2. **取得 QSDK 12.2 OEM 授权 + `qca/src/linux-5.4` 整套源码 + 闭源 feed，换 target 重编**——不是改 `.config`，是换编译树。
3. **在 6.12 主线上继续按 NSS/ECM 口径调**（本仓在做的事），但不要塞 5.4 闭源件；先跑 `oem-stack-check` 确认没有残留，再看 `eth0/eth1` 与 NSS debugfs 判速。

---

## 五、本次修正了什么（第 41 次，两处方向纠正）

1. **纠正第 40 次的 BDF 断言**：`wifi-truth.conf` 的 `OEM_BDF_VERDICT`、
   `art/art-truth.conf` 的 `OEM_BDF_IN_USE=template`、`make-board2.py` 的 docstring
   里「MD5 == 模板 BDF」全部改成准确表述；`from-oem` 降级为**实验性可选**，
   不再宣称「好固件实证在用」。ART 切片禁用、容器签名校验、默认不进固件**保持不变且更有理由**。
2. **补正 U-Boot/DDDR 判断**：U-Boot 里确实没有 `cnss2.bdf_*` / `4c400000`，
   但**两台真实 DTB 里都有 `qcom,bdf-addr`**；两者不矛盾（U-Boot 不搬，cnss2 自己搬）。
   文档改为分别陈述，避免误读成「好固件没有 DDR 搬运」。
   `qcom,bdf-addr` / `qcom,board_id` / `qcom,tgt-mem-mode=2` 是 cnss2 专用属性，
   **禁止抄进主线 ath11k DTS**（主线用 rootfs 的 `board-2.bin` + `qmi-board-id`）。

新增资产：`docs/OEM-QSDK12.2-取证报告.md`（本文件）、`vs010/oem-qsdk-truth.conf`、
`files/etc/config/oem-qsdk-truth.conf`、`files/usr/sbin/oem-stack-check`（只读自检，挂进
`health-fix` 第 7 段）、`art/oem-qsdk-bdf/`（取证存档）、`修复总览.md`；
`verify.sh` 新增 12 条判据。**DTS、两份 workflow、`config/`、`patches/`、`wireless` 配置一个字节没动。**

---

## 六、新仓库体检（2026-11-24 16:10 clone 实测）

对照「第 40 次总修复包」（109 个文件）：

| 项 | 结果 |
|---|---|
| 包内文件 | 109 |
| 仓库中**逐字节一致** | **108** |
| 不一致 | **1**：`.gitignore`（仓库里少了末尾 3 行 `openwrt/`、`firmware_out/`、`build.log`） |
| 缺失 | **0** |
| 仓库额外文件 | `ATR文件/`、两份 ART、`oem_extract/rootfs.ubi`、`firmware/*`、`flash.py`、`poll_build.py`、`ipq5018-vs010.dts`、`FLASHING.md` 等（预期保留，**不要删**） |
| 最新提交 | `b76f128 2026-11-24 15:00:25 +0800 Add files via upload` |

**结论：是，仓库已经是第 40 次全部修复后的文件，只差 `.gitignore` 三行。**
另发现一个 **1 字节垃圾文件 `.github/workflows/build-ap`**（无扩展名，内容是 1 字节），
不影响编译，建议顺手删掉。本次总修复包会带上正确的 `.gitignore` 覆盖掉差异。

---

## 七、交付方式

`VS010-RAX3000Q-总修复可上传文件-第41次.zip` 是**累积全量包**：包含此前所有轮次 +
本次第 41 次修复，附 `修复总览.md` 与 `上传说明.txt`。**只传这一个，之前所有包作废。**

> 以后每次修复都按这个规矩：出**总修复可上传文件**，不再只给增量包。
