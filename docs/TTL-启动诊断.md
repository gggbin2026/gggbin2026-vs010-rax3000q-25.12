# 🔴 VS010「Starting kernel 后无输出 + 自动重启」TTL 诊断手册（第 57 次）

> 适用现象：U-Boot 校验/解压/加载 DTB 全部 OK，最后一行停在
> `Jumping to AARCH64 kernel via monitor`，**之后一句内核日志都没有**，几秒后整板复位、循环重启。

---

## 一、先把三行「报错」排除掉 —— 它们是无害的

```
fdt_fixup_qpic: QPIC: unable to find node '/soc/qpic-nand@79b0000'
parse_fdt_fixup: unable to find node '/soc/qpic-nand@79b0000/'
Could not find PCI in device tree
```

🔴 **这不是启动失败原因，不要去"补 `/soc/qpic-nand@79b0000` 节点"。**

OpenWrt 官方 commit `3bbb4f6ce7b`（*qualcommax: ipq50xx: remove disabled partitions node*，
George Moussalem / Robert Marko，2025-11-29）原文：

> "Although the bootloader tries to 'fixup' the qpic nand node, **it actually can't find it
> as the node was renamed to spi based on the new driver architecture**."
> 该 commit 附的 Bootloader logs 与本机的三行**逐字相同**。

原因：6.12 主线把节点从 `qpic-nand@79b0000` 改名为 **`spi@79b0000`**（`qcom,ipq5018-snand`
新驱动架构），原厂 QSDK U-Boot 仍按老路径字符串找。官方 `ipq5018-pz-l8.dts` 同样打印这几行，
**实机照样启动**。内核用 `partitions { compatible = "qcom,smem-part"; }` 自己从 SMEM 读 MIBIB
分区表，不依赖 U-Boot 的 fixup。

`Could not find PCI in device tree` 同理，是 QSDK U-Boot 的常态输出（同批 U-Boot 日志里
还有 `PCI0/PCI1 is not defined in the device tree`）。

---

## 二、🔴 自动重启**不是机器狗**

`bridge-watchdog`（WDS 网桥机器狗）是 **Linux 用户态**脚本：需要完整起来、读 `/etc/config/wdsdog`、
过 6 分钟开机宽限、再连续不通 5 分钟才 `reboot -f`。内核都没起来，它根本没机会运行。

现在的重启是 **U-Boot / 硬件看门狗复位**：U-Boot 跳内核后没人喂狗，超时即复位，于是循环打印同一段日志。

---

## 三、🔴 真正要查的：`Starting kernel` 之后为什么一句内核输出都没有

正常 6.12 内核跳转后**立刻**会打印：

```
[    0.000000] Booting Linux on physical CPU 0x0000000000 [0x410fd034]
[    0.000000] Linux version 6.12.91 ...
```

零输出只有两种可能：

| | 含义 |
|---|---|
| **A. cmdline 缺 `console=`** | 内核其实在跑，但所有早期 printk 被丢进缓冲、没有输出设备；后面挂 rootfs / panic 也看不到。**最可能** |
| **B. 内核在 `start_kernel()` 之前就挂了** | U-Boot/ATF 跳转入口、内存节点、解压地址不匹配；改 DTS 救不了 |

### 为什么 A 会发生

原厂 5.4 实机 FDT 的 `/chosen` 是**两份属性**：

```
bootargs        = "console=ttyMSM0,115200n8 ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs rootwait"
bootargs-append = " ubi.mtd=rootfs root=/dev/ubiblock0_1 swiotlb=1 coherent_pool=2M"
```

第 56 次之前的 6.12 DTS 只有 `bootargs-append`，**既没有 `bootargs` 兜底、也漏了 `ubi.mtd=rootfs`**。
平时靠 U-Boot env 里的 `bootargs` 补；一旦 env 因 `bad CRC, using default environment` 回落默认环境、
或被 Web 升级流程改写，U-Boot 交给内核的 cmdline 就可能没有 `console=`/`ubi.mtd=` → A 成立。

---

## 四、🔴 不用重编，TTL 里 3 分钟就能定位（**先做这一步**）

3.3V USB-TTL 接好（115200 8N1），上电看到 `Hit any key to stop autoboot` 时**按任意键**打断。

### ① 看 U-Boot 实际给内核的参数

```bash
printenv bootargs
printenv bootcmd
printenv machid
fdt addr $fdt_addr_r   # 若提示未知变量，跳过
fdt list /chosen       # 看有没有 bootargs / bootargs-append
```

**重点看 `bootargs` 里有没有 `console=` 和 `ubi.mtd=rootfs`。**

### ② 手动补一份完整 cmdline，再引导一次

```bash
setenv bootargs 'console=ttyMSM0,115200n8 ubi.mtd=rootfs ubi.block=0,ubi_rootfs root=/dev/ubiblock0_1 rootfstype=squashfs rootwait swiotlb=1 coherent_pool=2M ignore_loglevel'
saveenv             # 可选：先不 save，验证成功再存
boot                # 或按 printenv bootcmd 里的命令手工 bootm
```

> 备用（原厂口径，走 `mtd:ubi_rootfs`）：
> `setenv bootargs 'console=ttyMSM0,115200n8 ubi.mtd=rootfs root=mtd:ubi_rootfs rootfstype=squashfs rootwait ignore_loglevel'`

### ③ 按输出判根因

| 现象 | 结论 | 下一步 |
|---|---|---|
| ✅ 出现 `Booting Linux on physical CPU` / `Linux version 6.12.91` | **A 成立**：就是 bootargs 问题 | 第 57 次 DTS 已补 `bootargs` 兜底；重编一次即可固化，`saveenv` 也能临时解决 |
| ⚠️ 有内核日志，但停在 `ubi0: attaching mtd` / `EUCLEAN` / `error -74` / `VFS: Unable to mount root fs` | **NAND ECC 不匹配**：U-Boot 写入 ECC 与 6.12 `qcom_snand` 读取 ECC 不一致 | 别反复刷。PZ-L8 NSS 项目的修法是给 `drivers/mtd/nand/spi` 打补丁把芯片 `NAND_ECCREQ` 改成与 U-Boot 一致（8,512）；把 dmesg 贴回来，按芯片型号出补丁 |
| ❌ 补了 `console=` `ignore_loglevel` 后**仍零输出** | **B 成立**：U-Boot/ATF 跳转入口与 6.12 内核不兼容，或刷入的镜像/分区布局不对 | 改 DTS 无效。需要配套 64 位 U-Boot，或先用 **initramfs** 镜像从 TTL/`tftpboot` 引导验证内核本身；这一步是硬件门槛 |

### ④ 想让 panic 停住而不是立刻重启

在 U-Boot 里尽量关掉看门狗（不同版本命令不同，可试）：

```bash
wdt list && wdt dev watchdog@xxx && wdt stop     # 新版 U-Boot
# 或把 panic 挂住：在 bootargs 里再加 panic=0（不自动重启）
setenv bootargs "$bootargs panic=0"
```

---

## 五、第 57 次仓库改了什么（低风险、与官方实机基线对齐）

核查结论：本仓 VS010 DTS 的 `chosen` / `aliases` / `&blsp1_uart1` / `&qpic_nand` 结构与
qosmio `25.12-nss` 官方 `ipq5018-pz-l8.dts`（实机验证可启动）**逐字一致**，
所以 bootargs 链路、串口 pinmux、FIT/UbiFit 配置本身不是自定义出来的问题。

唯一与官方有实质差异、且可能影响启动的三处，这次全部对齐：

| 改动 | 依据 |
|---|---|
| 🔴 `/chosen` 补 `bootargs = "console=ttyMSM0,115200n8 ubi.mtd=rootfs rootfstype=squashfs rootwait"`，`bootargs-append` 补回 `ubi.mtd=rootfs` | 与 5.4 实机 FDT 同口径；U-Boot 有 env bootargs 时会 `fdt set` 覆盖，兜底不冲突 |
| 🔴 删掉 `nand-ecc-strength = <4>` / `nand-ecc-step-size = <512>`（VS010）和 `<8>` / `<512>`（RAX3000Q） | 这两个值抄自 **32 位 5.4 闭源 QSDK FDT**；6.12 主线 `qcom_snand` 由芯片 ID 表协商 ECC，官方 pz-l8 **不写**这两行。PZ-L8 NSS 项目实证 ECC 声明与 U-Boot 写入不一致会 `ubiattach -74 EUCLEAN` |
| 🔴 VS010 `qcom,port_phyinfo` 的 `port@1`/`port@2` 改回官方的 `port@0`/`port@1` | 与能启动的 pz-l8 对齐；`port_id` 值 `<1>/<2>` 不变 |

**没动**：82 项冻结基线 / 29 个 `=y`、两份 workflow、`config/`、`patches/`、
`files/` 全部运行期脚本、机器狗、NTP、IP、SSH/TTYD、防火墙/IPv6、同桥、STP、Release 说明模板。
**没有新增或删除任何插件。**

> 🔴 如实边界：本轮改的是「U-Boot env 缺 bootargs」和「多余的闭源 ECC 声明」这两类**有实证依据**的低风险项，
> **不保证**解决「U-Boot/ATF 与 6.12 内核入口不兼容」。请务必先按第四节做一次 TTL 诊断——
> 若属于表中第 ③ 类 ❌，重编多少次都没用，需要换配套 U-Boot 或用 initramfs 验证。

---

## 六、恢复与红线

- 机器现在循环重启时，**刷回原厂固件**即可恢复（原厂 Web 恢复 / U-Boot `tftpboot` + `nand write`）。
- 🔴 **绝不刷 CMCC PZ-L8 的 U-Boot / MIBIB / 大分区表**：核查报告记录过 VS010 刷 CMCC U-Boot 因复位键 GPIO 冲突变砖。
- 🔴 刷前/恢复前备份 `0:ART`(mtd13, 0x780000) 与 `0:TRAINING`(mtd14, 0x880000)，别擦除。
- 64 位不死 U-Boot 仍是硬门槛；首次务必 TTL。
- 刷完能进系统后第一件事 `passwd` 改掉 `admin`。

参考：OpenWrt commit `3bbb4f6ce7b265b8ac13437f519fd0352bd0a3d6`（qpic fixup 无害）、
`mufeng05/openwrt-cmcc-pz-l8-nss`（U-Boot 8-bit ECC / EUCLEAN）、本仓 `docs/oem-dts/vs010.dtb`（5.4 实机 FDT）。
