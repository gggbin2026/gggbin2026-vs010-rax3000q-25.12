# 第 41 次 · 无线满血修复指南（**老仓库**）

> 前提：你已经把两个 NWRT QSDK12.2 官方固件放进仓库 `3000Q-VS010-固件/`。
> 本指南只解决「无线 / NSS 加速满血」，**不改你的网桥业务配置**。

## 一、先说结论（别绕弯）

我把两个 27MB 固件**真解开了**：UBI 2 卷 → `kernel` FIT **Linux-5.4.213** +
`rootfs` squashfs（2208 文件 / **159 个 .ko** / 58 个无线固件）。
里面是**完整的闭源无线 + NSS 加速栈**：`ipq_cnss2`、`qca_ol`、`umac`、
`wifi_3_0`、`qdf`、`ath_pktlog`、`mem_manager`、闭源版 `cfg80211`、
`qca-nss-drv` / `qca-ssdk` / `ecm` / `qca-mcs` / `qca-nss-dp`，
外加 `cnssdaemon` / `wifitool` / `wlanconfig` / `qca-hostapd` 和 14 个相关 init.d。
**没有 `ath11k`、没有 `mac80211`** —— 和你「无线正常」的成功态 `lsmod` 完全对上。

但有个硬边界：

| | 内核 | vermagic | 无线栈 |
|---|---|---|---|
| **官方好固件** | **5.4.213** | `5.4.213 SMP preempt mod_unload ARMv7 p2v8` | 闭源 qca-wifi + cnss2 + QMI WLFW |
| 本仓编译产物 | **5.4.164** | `5.4.164 / NHSS.11.5` | 开源 ath11k + mac80211 |

**5.4.213 的 `.ko` 在 5.4.164 内核上 `insmod` 必 `Invalid module format`**，
且两套栈共用 `cfg80211`、互斥。所以：

> ✅ **能在仓库里做到的修复**：把这两个官方固件作为可下载/可刷的底座，
> 再把本仓全部定制（管理页、三环温度仪表盘、LuCI 自修、自检工具、WDS 网桥脚本）
> 叠加到刷好官方固件的设备上。刷一次，无线 + NSS 加速立刻满血。
>
> ❌ **做不到的**：靠改 `.config` / 拷 `.ko` / 改 DTS，让本仓 `kkstone 5.4.164`
> 编译树里的 ath11k 变成闭源满血栈。别再试了。

## 二、三步走（推荐路径，零变砖风险）

### 第 1 步 · 刷对应机型的官方固件

| 机型 | 刷这个文件 |
|---|---|
| **VS010** | `3000Q-VS010-固件/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cucc_vs010-squashfs-nand-factory.bin` |
| **RAX3000Q** | `3000Q-VS010-固件/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cmcc_rax3000qy-squashfs-nand-factory.bin` |

⚠ **千万别刷错机型**：两个固件的 `bdwlan.b10` / `qcn6122/bdwlan.b60` **MD5 不同**
（VS010 `4ce1ec…` / `80badc…`，RAX `4b9aba…` / `e43c4c…`），板级表逐机型独立。

刷法任选：
- 官方 Web 升级页（上传 `.bin`）；
- 已开启 SSH 时 `sysupgrade -F -n <file>`（`-n` 会清配置，先备份）；
- TTL + U-Boot TFTP（救砖用，见仓库 `FLASHING.md` / 用户既有流程）。

刷完**先别急着配网桥**，按第 3 步验收无线是否已经正常。

### 第 2 步 · 叠加本仓定制（不重打包固件）

把 `oem54/` 整个目录传到设备（例如 `scp -r oem54 root@<设备IP>:/tmp/`），然后：

```sh
cd /tmp/oem54
sh apply-oem-overlay.sh --dry-run     # 先看清单，不改动
sh apply-oem-overlay.sh               # 安装（自动备份被覆盖文件）
sh apply-oem-overlay.sh --rollback    # 后悔了，一键还原
```

脚本会：
- 检查内核必须是 **5.4.213**（不是就拒绝，防止刷到本仓编译的 5.4.164 上）；
- 只写 `/www/**`、`/usr/sbin/**`、`/usr/lib/bridge/role.sh`、`/etc/init.d/luci-fix`
  与两个只读真值表配置；
- **绝不碰** `/etc/config/{network,wireless,dhcp,dropbear,uhttpd,firewall,luci,system}`、
  `rc.local`、`99-bridge-ready` —— 覆盖这些会断网；
- 安装前把将被覆盖的既有文件备份到 `/etc/oem-overlay-backup/<时间戳>/`。

叠加包里有什么（18 个文件）：三环温度仪表盘的 WDS 页 / AP 页 / 简版页、两个 CGI
（`bridge` / `apstatus`）、`health-fix` / `luci-fix` / `luci-entry` / `portstat` /
`accel-check` / `tty-diag` / `wifi-bdf-check` / `wifi-art-cal` / `wifi-stack-check`、
`role.sh`、`bridge.conf`、`art-truth.conf`、`oem-stack-truth.conf`。

### 第 3 步 · 验收

```sh
uname -r                                  # 必须 5.4.213
lsmod | grep -iE 'qca_ol|umac|wifi_3_0|ipq_cnss2|qca_nss_drv'   # 闭源栈应在位
dmesg | grep -iE 'BDF version|Caldata|cnss'  # 应见 BDF version: 1 CAL version: 0 Status: 0
iw dev || wlanconfig ath0 list           # 两个射频应注册
wifitool ath0 status                     # QSDK 工具可用
sh /usr/sbin/wifi-stack-check            # 应识别为【官方 5.4.213 闭源 qca-wifi 栈】
sh /usr/sbin/health-fix                  # LuCI / SSH / CGI 自检
浏览器 Ctrl+F5 打开 /bridge/ 与 /ap/      # 三环温度仪表盘
```

> 成功态日志实证：好固件 `Caldata not present` ×2、`BDF version: 1 CAL version: 0
> Status: 0`，**无线与有线都正常**。所以不要往 `/lib/firmware` 塞 ART 校准切片
> （`wifi-art-cal` 是只读工具，别用 `export` 的结果覆盖固件目录）。

## 三、WDS 网桥 / AP 业务配置（按需增量，不覆盖）

官方固件自带 `/etc/config/network` / `wireless`，**别用本仓 `files/etc/config/network`
整体覆盖**。要用网桥时按设备实际接口名增量设：

```sh
# 先看清楚官方固件的接口名，别照抄示例
uci show network | grep -E 'device|proto|ipaddr'
swconfig dev switch1 show 2>/dev/null | head -40   # 若有交换芯片
cat /proc/mtd | grep -i art

# 示例（接口名以实际为准）
uci set network.lan.type='bridge'
uci set network.lan.stp='1'          # 网桥开 STP，防环
uci set network.lan.proto='dhcp'     # 旁路由/网桥模式
uci commit network && /etc/init.d/network restart
```

本仓的 `files/etc/init.d/bridge-*`、`dhcp-guard`、`99-bridge-ready` 是**给本仓编译树
写的**，官方固件的 uci / init 序列不同，直接拷过去可能断网。要用请先在 TTL 串口下
逐条验证。**这一步不是无线修复，是业务配置，别和刷机混在一起做。**

## 四、本仓编译链这次也改了什么（对仍在用本仓编译固件的人）

1. **BDF 对齐（核心）**：发现本仓 `vs010/bdf/board-cucc_vs010.*`（`c7d897…`/`0aadbd…`）
   来自 **4.4.60 / QSDK 10.4** 的 `oem_extract`，**不是** 5.4.213 好固件实际用的板级表
   （旧登记「MD5 一致」是错的，当时只比了 131072 字节大小）。
   现新增 `vs010/bdf/board-cucc_vs010.oem54.{ipq5018,qcn6122}`（从好固件提取），
   `diy-part2.vs010.sh` 的 **cnss2 双路径**（`bdwlan.b10` / `qcn6122/bdwlan.b60`）
   改用这两份并校验新 MD5；ath11k 的 `board-2.bin` 仍用旧文件，
   **所有既有 MD5 断言 / A 段硬校验一字未动**，编译零风险。
2. **补齐 5.4 独有的 6 个固件**到 `files/lib/firmware/IPQ5018/`：
   `Data.msc` / `fw_ini_cfg.bin` / `regdb.bin` 及 `qcn6122/` 三份副本
   （第 40 次发现 4.4.60 卷没有、5.4 日志独有的那 6 个）。纯新增。
3. **归档清单**：`oem54/manifest/` 里 159 个 `.ko`、58 个固件、59 个 init.d、
   opkg 包清单、UBI 布局；`wifi-truth.conf` 追加 `FW54_*` / `BDF_54_*` 实证段。
4. **新增打包 workflow** `build-oem-bundle.yml`：手动 Run 一次，把两个官方固件 +
   叠加包 + 说明 + 清单打成一个 artifact，直接下载刷机。不编译、不碰现有两个 workflow。

**没动**：两份原 workflow、四份 `.config`、两份 slim、DTS、`patches/`、
任何 `.ko`（编译树内 `.ko` 数 = 0）、任何网络配置。

## 五、如实边界

- **本仓编译出的固件，无线仍是开源 ath11k 栈**，不会因这次改动变成满血闭源栈——
  内核版本决定了这一点。要满血就刷第 1 步的官方固件。
- 没跑真实 `make`、没实机。刷机前请备份配置、备好 TTL 串口。
- 两个官方固件是整机镜像， ART 校准在 `0:ART` 分区、每台独立，**勿跨机刷、勿外传**。
- 叠加脚本只改 `/overlay` 上的文件，`--rollback` 可还原；不重打包固件、不刷分区。
