# patches/ —— 唯一一条补丁，默认不启用

| 文件 | 用途 |
|---|---|
| `440-mtd-spinand-add-support-for-FudanMicro-FM25LS01.patch` | 复旦微 FM25LS01（ID `0xA5`）SPI-NAND 支持，**仅 PZ-L8 V2 批次** |

**原文来源**（未改动一个字节）：`mufeng05/openwrt-cmcc-pz-l8-nss`
→ `openwrt/tree/target/linux/generic/pending-6.12/440-...patch`，
再往上 `CrazyBoyFeng/openwrt-pz-l8`（作者 CrazyBoyFeng），
最初出自 ImmortalWrt `400-mtd-spinand-Support-fmsh.patch` / Rockchip BSP。
许可沿用内核 GPL-2.0。

## 默认关，且有三道门

`scripts/apply-nand-patch.sh` 由 `prepare.sh` 调用，只有全部满足才应用：

1. `NAND_PATCH=1`（workflow 里勾 `nand_patch`，默认 `false`）
2. 基线是 6.12（`qosmio-25.12-nss` / `official-25.12.6`）；`kuncy7-6.18-nss` 自动跳过
3. 树里有 `drivers/mtd/nand/spi/fmsh.c`、且尚未含 `FM25LS01`、且 `git apply --check` 通过

任何一道不满足**只警告、不停编**，内核保持干净树。应用结果写进 `build.env` 的
`NAND_PATCH=` 行，Release 与 `art-check` 都能查到。

## 为什么不建议随便开

- 这是 **V2 批次**芯片（替代 V1 的 ESMT F50D1G41LB）。VS010 原厂是 ESMT，
  RAX3000Q 闪存型号未实证；V1 板子打它没有任何收益。
- 补丁声明 `NAND_ECCREQ(8, 512)`，数据手册写片上 `1-bit/512`。QPIC 控制器不用片上
  ECC，而是按声明强度配自己的硬件 ECC；**声明值必须和 U-Boot 写入时一致**，
  否则读不出 bootloader 写的 UBI（`-74 EUCLEAN`）→ 变砖。8 是补丁作者在 V2 板上
  定的经验值，不是数据手册值。
- 上游 README 明确：手上只有 V1 板，这条路径**只验证到「干净应用、能编过」**，
  没有在真 FM25LS01 硬件上跑过；chip ID / 几何 / ooblayout 都照搬上游未独立核对。
- `fmsh.c` 本身不是内核自带的，是 OpenWrt 两个 generic backport（401 / 435）加进去的；
  树里没有它时脚本会直接跳过。

## U-Boot 侧实证：V2 批次确实存在（2026-11-24 新增）

用户上传的两份 640 KB U-Boot（`ATR文件/uboot-ipq50xx-cucc_vs010-*.bin` 与
`uboot-ipq50xx-cmcc_rax3000q-*.bin`）strings 里，**名称表同时包含**
`F50D1G41LB(2M)`（ESMT，V1）与 `FM25LS01` / `FM25LS02BI3`（复旦微，V2），
还有 `board_update_caldata` / `failsafe_write_art` / `qpic_nand_read_id_serial`。

→ **U-Boot 已经认识 FM25LS01，V2 批次真实存在**，所以 Linux 侧这条补丁对 V2
板子是**必需**的，不是无关补丁。判断从「可能用不上」升级为「有据可依」；
但 ECC 声明值与 U-Boot 不一致会 EUCLEAN 变砖的风险**没有消失**，默认仍关。

**怎么判断自己是 V1 还是 V2**：TTL 看 U-Boot 启动打印的
`flash_type / flash_index / flash_density`，或 Linux 里
`dmesg | grep -iE 'qpic|spinand|flash id'`；`unknown flash ID 0xA5` 即 V2。

## 什么时候开

TTL 串口看到 `unknown flash ID 0xA5`、`qcom_snand ... EUCLEAN`、或确认板子是 V2 批次，
再在 Run workflow 时把 `nand_patch` 勾上。刷完先看 dmesg，出现 EUCLEAN 立刻关掉重编。

**回退**：不勾 `nand_patch` 重编即可（干净 clone / `git reset --hard` 会清掉工作区改动）。

> 也可把本 patch 拷进 `target/linux/generic/pending-6.12/` 让 OpenWrt 自动应用，
> 但那等于**默认启用**，与本仓「默认关」的策略冲突，不建议。
