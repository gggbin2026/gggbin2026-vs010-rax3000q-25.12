# NWRT QSDK12.2 / 5.4.213 官方好固件 · 离线解包资产清单

来源：仓库 `3000Q-VS010-固件/` 两个 27394048 B 的 factory.bin（用户上传）。
逐字节解开（手写 UBI LEB 拼卷 → `unsquashfs`），不是只列文件名。

## 镜像布局（两个机型一致）

| 卷 | LEB | 字节 | 类型 |
|---|---|---|---|
| `kernel` | 32 | 4063232 | FIT：`ARM OpenWrt Linux-5.4.213` + 机型 dtb（cucc_vs010 / cmcc_rax3000qy） |
| `rootfs` | 175 | 22220800 | squashfs4 / xz / blocksize 262144 / 22133390 B / 2699 inode / **2208 文件** |
| layout | 2 | 253952 | UBI 卷表 |

- `PEB=131072`、`LEB=126976`、`min_io=2048`、共 209 PEB
- **无独立 `wifi_fw` / `bt_fw` / `rootfs_data` 卷**（与 4.4.60 OEM 的 5 卷布局不同）
  → 58 个无线固件全在 `rootfs:/lib/firmware/IPQ5018/`；`rootfs_data` 由首启自动创建
- bootargs：`ubi.mtd=rootfs root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M console=ttyMSM0,115200,n8`
- 发行版：`OpenWrt 19.07-SNAPSHOT r0-f3013a33b / ipq50xx/ipq50xx_32 / arm_cortex-a7_neon-vfpv4`

## 内核模块（159 个，完整清单见 `manifest/ko-list.txt`）

`vermagic=5.4.213 SMP preempt mod_unload ARMv7 p2v8`

### 闭源无线栈（无 ath11k / 无 mac80211）

| 模块 | 字节 | 成功态 lsmod 对照 |
|---|---|---|
| `qca_ol.ko` | 1770192 | `qca_ol 1232896` |
| `umac.ko` | 3927032 | `umac 2736128` |
| `wifi_3_0.ko` | 992152 | — |
| `qdf.ko` | 162592 | `qdf 114688` |
| `ipq_cnss2.ko` | **375204** | `ipq_cnss2 299008` ← 第 40 次判定缺的就是它 |
| `cfg80211.ko` | 314296（闭源版） | `cfg80211 241664` |
| `ath_pktlog.ko` | 21256 | — |
| `mem_manager.ko` | 4568 | `mem_manager 24576` |

> 文件大小与运行期 `lsmod` 的 Size 不同是正常的（ELF 含符号/重定位段，加载后只算有效节）。

### NSS / 硬件加速栈

`qca-nss-drv`(251552) · `qca-ssdk`(539704) · `ecm`(398708) · `qca-nss-dp`(40612) ·
`qca-mcs`(53208) · `qca-nss-macsec`(139352) · `qca-nss-pppoe`(5740) ·
`ecm_ae_select`(3300) · `phy-qca-m31` · `phy-qca-uniphy`

## 无线固件（58 个，完整清单见 `manifest/fw-list.txt`）

`/lib/firmware/IPQ5018/`：
- `bdwlan.b10 / b20 / b21 / b22 / b23 / b24 / bin`（各 131072 B）
- `q6_fw.b00~b26` + `q6_fw.flist` / `.mdt`
- `m3_fw.b00~b02` + `.flist` / `.mdt`
- `qcn6122/{bdwlan.b50,b60,b90,bb0,bin, m3_fw.*, qdss_trace_config.bin}`
- **`Data.msc` / `fw_ini_cfg.bin` / `regdb.bin` 及 `qcn6122/` 三份副本**
  ← 第 40 次发现「5.4 日志独有、4.4.60 卷没有」的 6 个，这次全拿到了

### ★ BDF 逐机型独立（推翻旧「同一份」结论）

| 机型 | `bdwlan.b10` | `qcn6122/bdwlan.b60` |
|---|---|---|
| **cucc_vs010 好固件** | `4ce1ecfcca3aea1e9df230d192199690` | `80badcdda4502943cf89ee416cd288ca` |
| **cmcc_rax3000qy 好固件** | `4b9aba89839ca7af4b32d932e6e58df0` | `e43c4cf0d1ca1d86003992837ac5aed6` |
| 本仓旧 `vs010/bdf/`（4.4.60 OEM） | `c7d89771464322ea39ca290249295af9` | `0aadbd42dc960aefdffe09177dd275b9` |
| 两机型通用 `bdwlan.bin` | `8ab3181f131eeb51204b39821aa83f53` | `eaf73f0a090cf8e18f6d8652b9a58f1f` |

→ 三套都不同。第 26/27 次写的「MD5 与好固件一致」**是错的**（当时只比了大小）。
第 41 次起 `diy-part2.vs010.sh` 的 cnss2 路径改用 `board-cucc_vs010.oem54.*`。

## 启动链（59 个 init.d，完整清单见 `manifest/initd-list.txt`）

`load_cnss2`(START=00，`insmod ipq_cnss2` + `cnssdaemon`) →
`wifi_fw_mount`(00) / `wifi_fw_done`(96) →
`qca-ssdk`(16) → `qca-nss-ecm`(19) / `cnss_diag`(19) →
`qca-nss-drv`(70) → `qca-hostapd` / `qca-wpa-supplicant` / `qca-acfg` / `thermal`

首次启动由 `qca-wifi-scripts` 的 `/lib/preinit/81_load_wifi_board_bin` 生成无线配置
（好固件的 `/etc/config/wireless` 出厂为空，属正常）。

## 用户态与包（40+ 个 qca-* 包，完整清单见 `manifest/opkg-list.txt`）

`wifitool` / `wlanconfig` / `athstats` / `cfg80211tool` / `cnss_diag` / `wifistats` /
`thermald` / `hostapd` / `wpa_supplicant` / `cnssdaemon`；
`kmod-qca-cnss` / `kmod-qca-nss-drv` / `kmod-qca-ssdk-nohnat` /
`kmod-qca-nss-ecm-standard` / `qca-cnss-daemon` / `qca-qmi-framework` /
`qca-hostap` / `qca-wifi-fw-hw4-10.4-asic` / `qca-wifi-scripts` /
`qca-thermald` / `wififw_mount_script` 等。

## 为什么这些 `.ko` 不进本仓编译树

`vermagic 5.4.213` vs 本仓 `5.4.164 / NHSS.11.5`：内核 ABI / 导出符号 /
cfg80211 版本全不匹配，`insmod` 必 `Invalid module format`；闭源 qca-wifi 与
`ath11k + mac80211` 共用 cfg80211、互斥。**仓库里只放清单，不放 `.ko`。**
要用整套闭源栈，刷官方 factory.bin（见 `README_无线修复.md`）。

## 与第 40 次（4.4.60 OEM）的区别

| | 4.4.60 / QSDK 10.4 | **5.4.213 / QSDK 12.2（本次）** |
|---|---|---|
| 卷 | 5 个（含独立 `wifi_fw` 29 PEB） | **2 个**（固件在 rootfs） |
| 内核 | 4.4.60 / Chaos Calmer 1.0.1 | 5.4.213 / 19.07-SNAPSHOT |
| `ipq_cnss2.ko` | 无 | **有**（375204 B） |
| Q6 固件 | 52 个 | **58 个**（多 6 个 5.4 独有） |
| BDF | 与本仓旧 bdf 同源 | 逐机型另一套 MD5 |
| 可用性 | 只能当证据 | **整机可刷，无线满血** |
