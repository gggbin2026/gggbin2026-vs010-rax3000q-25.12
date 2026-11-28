# NAND ECC 补丁口径（2026-11-28 实证更新）

## 结论先说：本仓 `patches/` **不放任何 `.patch`**

上游 `fb90296c322a`（*qualcommax: ipq50xx: spi-qpic-snand: default to 4-bit ECC*，
2025-05-15，[邮件](https://lists.infradead.org/pipermail/lede-commits/2025-May/025412.html)）
修的是：某些 SPI-NAND 芯片在 ID 表里声明最小 ECC 强度为 1/2-bit，而 QPIC-SNAND
只支持 4 或 8-bit，旧驱动会 `dev_err("only 4 or 8 bits ECC strength is supported")`
→ probe 失败、机器起不来。补丁把 1/2-bit 回退到 4-bit。

**这个补丁上游已经替我们打了**，按基线逐一实证：

| 基线 | KERNEL_PATCHVER | 0401 位置 | 判定 |
|---|---|---|---|
| `official-25.12`（`openwrt/openwrt @ v25.12.6`，**默认**） | 6.12 | `target/linux/qualcommax/patches-6.12/0401-spi-spi-qpic-snand-default-to-4-bit-ECC.patch`（1589 字节） | ✅ 已内置 |
| `qosmio-25.12-nss` | 6.12 | 同名文件，内容与官方一致（1589 字节） | ✅ 已内置 |
| `official-main` | **6.18** | `target/linux/qualcommax/patches-6.18/0401-spi-spi-qpic-snand-default-to-4-bit-ECC.patch` | ✅ 已内置（随内核目录迁移，不是被删） |
| `kuncy7-6.18-nss` | 6.18 | `REPO` 在 `baseline.env` 里留空，workflow 直接拒绝该基线 | ⚠ 无法实证，当前编不了 |

邮件里那个 `patches-6.6/0401` 在 `v25.12.6` 不存在，因为 25.12 只编 6.12 内核、
没有 `patches-6.6` 目录；不影响。

## 本仓还有第二重保险：DTS 显式写了合法 ECC

`v25.12.6` 的 6.12 内核另带两个 generic backport：

- `412-v6.16-next-spi-spi-qpic-snand-validate-user-chip-specific-ECC-properties.patch`
  → **DT 的 `user_conf` 优先于芯片 `reqs`**：`if (user->step_size && user->strength)`
  直接用 DT 值，只有 DT 没写时才回落到芯片声明的 1/2-bit。
- `417-v6.17-spi-spi-qpic-snand-add-support-for-8-bits-ECC-strength.patch`
  → 把 `if (strength != 4)` 改成 `switch case 4 / case 8`，8-bit 合法。

本仓两块板级 DTS 本来就显式写了：

| 机型 | `nand-ecc-step-size` | `nand-ecc-strength` | 命中 |
|---|---|---|---|
| VS010 | `<512>` | `<4>` | `case 4`（`ECC_MODE_4BIT`） |
| RAX3000Q（GD5F1GQ5REYIG） | `<512>` | `<8>` | `case 8`（`ECC_MODE_8BIT`，靠 417 backport） |

→ **根本不会走进 1/2-bit 回退分支**，即使上游没打 0401 也不会 probe 失败。

## 为什么不放进 `patches/`

1. `git apply --check` 必然失败：OpenWrt 仓库树里没有
   `drivers/spi/spi-qpic-snand.c`（内核源码在构建期才展开），
   且邮件原版 hunk 是 `@@ -296,6 +296,24 @@`，`v25.12.6` 内置版是
   `@@ -304,6 +304,24 @@`（前面叠了 412/417 等 backport，行号已偏移）。
2. `scripts/apply-nand-patch.sh` 遇到 check 失败只打 `::warning::` 不停编 —— 放进去
   只会多一条无意义 warning，不会有任何效果，还可能让人误以为「补丁已生效」。
3. 上游补丁由构建系统从 `target/linux/.../patches-6.12|6.18/` 自动应用，
   比在工作流里手动 `git apply` 更可靠、可复现。

## 和「NAND V2 批次 / EUCLEAN」不是一回事

`3000Q-VS010-固件/ATR文件/` 里两份 U-Boot 名称表含 `FM25LS01` / `FM25LS02BI3`
→ V2 批次真实存在；**EUCLEAN 是 UBI/UBIFS 层的 bitflip 警告，属于坏块/寿命范畴**，
不是上面这个驱动 probe 失败。0401 对「声明 1-bit ECC 的芯片」确实有用（V2 批次
很可能正是这类），但**上游已内置**，所以本仓不需要再补。

⚠ 刷前仍备份整片 flash；EUCLEAN 出现时不要反复擦写。V2 批次若实机报
`nand: WARNING: ... ECC used on your system is too weak`，先看 `dmesg` 里
`qcom_snand` 实际选中的 strength，再决定是否要调 DTS —— 那是另一个问题，
不是加 0401 能解决的。

## `nand_patch` 开关现状

- `baseline.env`：`NAND_PATCH_DEFAULT=0`；workflow 输入 `nand_patch` 默认 `false`。
- `scripts/apply-nand-patch.sh` 已接线（clone 之后、板级注入之前），
  对 `6.12* / 6.6* / 6.1*` 尝试 `git apply --check`；6.18 基线直接跳过
  （上游 `patches-6.18/0401` 已内置）。
- 当前 `patches/` 只有本 README，勾 `true` 会打一条
  「勾了 nand_patch 但 patches/ 下没有 .patch」的 warning 后跳过，**不影响编译**。
- 保持默认关即可，别勾。
