# board/ —— 新内核板级适配说明

## `ipq5018-vs010.6.12.dts`

来自新仓库 `ipq5018-vs010.dts`，已经是**官方 25.12 qualcommax 风格**（`&wifi` / `&wifi1`、
`qcom,ath11k-calibration-variant`、`&dp1/&dp2` + `&mdio1` + QCA8337 DSA），
**不是**老仓库 `vs010/ipq5018-vs010.dts`（那是 QSDK 5.4 的 `wifi0/wifi1` + `qcom,board_id` 写法，
数值 phandle 与 machid 在 6.12 dtsi 下会 dtc 报错，只作为实机真值存档）。

`scripts/board-inject.sh` 会在此基础上做三件事：

1. 用 `vs010/wifi-truth.conf` 的 `VERIFIED` 值决定是否覆盖 BDF/board_id 相关节点
   （默认 `VERIFIED=0` → 不覆盖，保持官方 PZ-L8 推断值）。
2. 按老仓库实机结论校验：**VS010 只有 WPS 键 GPIO34、没有 reset 键**，若 DTS 含
   `KEY_RESTART` / `label="reset"` 直接停编（开机必进 failsafe）。
3. 把 `vs010/bdf/board-cucc_vs010.ipq5018`、`board-cucc_vs010.qcn6122`（各 128KB 原厂 BDF）
   与 `oem_extract/` 的 `bdwlan.bin` / `qcn6102_bdwlan.bin` 一起落进
   `files/lib/firmware/ath11k/IPQ5018/hw1.0/` 对应的 `board-2.bin` 包，
   **不注册联网下载的 `ipq-wifi-*` 包**（老仓库踩过 403 编译失败）。

## RAX3000Q

- 基线 A（qosmio `25.12-nss`）**树内原生** `cmcc_rax3000q`，`board-inject.sh` 检测到即跳过，
  只补 64 位引导相关的镜像命名。
- 基线 B（官方 `v25.12.6`）**没有这个设备**（官方 ipq50xx.mk 的 15 个设备里无 RAX3000Q），
  `board-inject.sh` 会明确报错并提示：从 qosmio `25.12-nss` 分支取
  `target/linux/qualcommax/dts/*rax3000q*` 与 `image/ipq50xx.mk` 的 `Device/cmcc_rax3000q`
  定义，按 6.12 dtsi 改写后再编。**不要凭空造 DTS**，GPIO/ART/NAND ID 错会变砖。
- 基线 C（kuncy7 6.18）未覆盖 RAX3000Q，同样报错。

## 关键差异（老 → 新）

| 项 | 老 5.4 QSDK | 新 6.12 qualcommax |
|---|---|---|
| 交换 | `swconfig` / `config switch` | DSA，`config device` + `list ports` |
| 无线节点 | `wifi0/wifi1` + `qcom,board_id` | `&wifi/&wifi1` + `ath11k-calibration-variant` |
| 校准 | 闭源 `qca_ol/umac/wifi_3_0` + `cnss2` | 开源 `ath11k` + `board-2.bin` / `ipq-wifi-*` |
| 驱动 | `qca-nss-dp/drv/ecm` + `qca-ssdk`（闭源） | 官方 `kmod-qca-nss-dp` 或 qosmio NSS 12.5 开源栈 |
| WDS | 私有 `ath11k-*-4addr-*-NSS-offload` 补丁 | mac80211 原生 4addr（未验证 NSS 加速） |
| 架构 | 32 位 arm_cortex-a7 | 64 位 aarch64_cortex-a53 |


## board-2.bin 正确合成途径（信号满血的关键，2026-11-24 补）

`vs010/bdf/board-cucc_vs010.ipq5018` 与 `board-cucc_vs010.qcn6122` 是从原厂 ART
切出来的**单个 BDF（各 128KB）**，不是 ath11k 需要的 `board-2.bin` 容器。
官方 `package/firmware/ipq-wifi/Makefile` 的做法是把 `board-<name>.IPQ5018`
直接 `INSTALL_DATA` 成 `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin`，
前提是那个源文件**本身已经是容器**。直接把单 BDF 改名会让两个射频读错校准，
正是老仓库「VS010 5G 弱」的根因之一。

正确做法（二选一）：

1. **用官方工具合成**（推荐，格式 100% 正确）
   - 取 `qca/qca-swiss-army-knife` 的 `ath11k-bdencoder`（与 OpenWrt `ipq-wifi`
     包注释里同一个工具）；
   - 按 `vs010/wifi-truth.conf` 里的 `BOARD_ID_2G` / `BOARD_ID_5G`、`chip_id`
     写一份 `board-2.json`，把两份 BDF 作为条目喂给编码器；
   - 输出 `board-2.bin` 放到 **`vs010/bdf/board-2.bin`**。
   - `scripts/board-inject.sh` 检测到就自动装进固件；没检测到就装空包，
     保留 `ath11k-firmware-ipq5018-qcn6122` 自带的通用 `board-2.bin`，
     两个射频照样 probe（最稳、最少系统问题）。
2. **直接用第三方已验证固件的 board-2.bin**：从「信号正常的 VS010 固件」解包
   `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin`，校验非空后放到同上位置。
   驱动 `.ko` 跨内核搬不动，但 board-2.bin 是纯数据，可以搬。

> 不提供 board-2.bin 时，无线满速五件套（`wifi_offload=1` / CN / ch36 / HE160 /
> 256M LOW）仍然生效，信号与吞吐主要靠正确固件包 + 功率表；`sh /usr/sbin/wifi-fullspeed`
> 与 `sh /usr/sbin/wifi-bdf-check` 会把当前用的是哪份 board-2.bin 打印出来。


## DEVICE_PACKAGES 必须补（PZ-L8 参考结论）

`mufeng05/openwrt-cmcc-pz-l8-nss` 查明：官方 25.12.x 的
`target/linux/qualcommax/image/ipq50xx.mk` 里 `Device/cmcc_pz-l8` **没有定义
DEVICE_PACKAGES**（同文件别的设备定义了 12 处），于是 ath11k 固件与这块板子的
board data 都不在镜像里，射频根本不会 probe；快照分支是带的，该仓用
`feed/ipq-wifi-cmcc_pz-l8` 补回来。

本仓 `scripts/board-inject.sh` 已按同样结论给 `Device/unicom_vs010` 补上：

```
DEVICE_PACKAGES := ath11k-firmware-ipq5018-qcn6122 \
	kmod-ath11k-ahb ipq-wifi-cucc_vs010
```

注意是 **`qcn6122` 变体**而不是通用 `ipq5018` 包，否则 2.4G 不 probe。
RAX3000Q 走树内原生 `cmcc_rax3000q`，若换基线后无线不注册，第一件事同样是检查
它的 `DEVICE_PACKAGES`，而不是先怀疑 BDF 或 NSS。
