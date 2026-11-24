# VS010 / CMCC 相近机型 DTS 获取清单与来源

> 抓取日期：2026-11-24
> 结论先说：**「CMCC VS010」是误称**。VS010 是**中国联通（CUCC）** AX3000 路由器；
> CMCC（中国移动）IPQ5018/IPQ5000 相近机型是 PZ-L8、RAX3000Q/QY、MR3000D-CI。
> 本包把两类都收了，但**VS010 三份 DTS 全文没能从网上抓下来**，只拿到 OpenWrt 主线里
> 两份 CMCC 机型的 DTS 全文。下面给出所有可点击原始链接与本地取法。

---

## 一、本包里有什么

| 文件 | 内容 | 可信度 |
|---|---|---|
| `VS010与CMCC机型DTS资料核查报告.md` | 完整核查报告：命名辨析、三份 VS010 DTS 可信度链条、五份设备树字段对比、mtd 分区表、变砖案例、全部引用来源 | 报告主体；VS010 字段多为交叉推定，已标注「未核实」 |
| `ipq5018-pz-l8.dts` | OpenWrt 主线 **CMCC PZ-L8** DTS 全文 | ⚠ 见下方警告 |
| `ipq5018-rax3000q.dts` | OpenWrt 主线 **CMCC RAX3000Q/QY** DTS 全文 | ⚠ 见下方警告 |
| `VS010_原厂MTD分区表.txt` | 论坛帖 mtd0..mtd23 逐字抄录 | 来自 OpenWrt 论坛原帖 |
| `VS010_DTS获取清单与来源.md` | 本文件 | — |

### ⚠ 关于两份 .dts 的重要限制

两份 DTS 是从 OpenWrt **源码镜像的网页树页面**（git.lede-project.org / git.openwrt.org
cgit blob 页）抓取的。网页渲染把 `<...>` 里的 phandle 和宏做了 HTML 转义剥离，
抓取时按同树语义补齐（例如 `<&tlmm 33 GPIO_ACTIVE_LOW>`、`<KEY_RESTART>`），
缩进也按内核编码规范还原，RAX3000Q 的 `boot-args` 数值与 `color` 宏属**未逐字节核实**字段。
**它们可以作为字段对照和结构参考，但不要直接拿去编译。**

要拿逐字节一致的官方原文，在任意一台能联网的机器上：

```bash
git clone --filter=blob:none https://git.openwrt.org/openwrt/openwrt.git
cd openwrt
git show origin/main:target/linux/qualcommax/dts/ipq5018-pz-l8.dts      > ipq5018-pz-l8.dts
git show origin/main:target/linux/qualcommax/dts/ipq5018-rax3000q.dts    > ipq5018-rax3000q.dts
```

---

## 二、VS010（联通）三份 DTS —— 本包未取到全文

抓取时对下列地址逐一尝试了 GitHub blob、raw.githubusercontent.com、jsDelivr、
ghproxy.net / gh-proxy.com / mirror.ghproxy.com、raw.gitmirror.com、kkgithub、
gh.api.99988866.xyz、GitHub API、ghfast.top 等通道，**全部被拒绝**，故不编造内容，
只给可点击原始链接与已交叉确认的特征。

| # | 来源 | 状态 | 已确认特征 |
|---|---|---|---|
| 1 | `maxdarksol/vs010-openwrt` → `vs010.dts` | **最可信，推荐基线** | 从闭源 Nwrt 运行态 `/sys/firmware/fdt` 用 `dtc` 反编译，并经三方 U-Boot 打印交叉核对；**把 WAN 与 LAN3 对调**，用直连 CPU 的 LAN3 作 WAN |
| 2 | `xiangye277/vs010-openwrt` → `ipq5018-vs010.dts` | 已被否定 | 作者本人在 issue #1 及论坛帖确认 **GPIO 与 switch port 配置不正确** |
| 3 | `whmzsu/vs010-openwrt` → `ipq5018-vs010.dts` | 有砖风险 | README 自述「基于 CMCC PZ-L8 设备树改编，GPIO 可能与实际 VS010 有差异，首次刷入有砖风险，建议准备 TTL」 |

**原始链接（复制即可下载）**

```text
# 1) maxdarksol（推荐）
https://github.com/maxdarksol/vs010-openwrt/blob/main/vs010.dts
https://raw.githubusercontent.com/maxdarksol/vs010-openwrt/main/vs010.dts

# 2) xiangye277（GPIO/端口有误）
https://github.com/xiangye277/vs010-openwrt/blob/main/ipq5018-vs010.dts
https://raw.githubusercontent.com/xiangye277/vs010-openwrt/main/ipq5018-vs010.dts
https://github.com/xiangye277/vs010-openwrt/issues/1

# 3) whmzsu（PZ-L8 改编）
https://github.com/whmzsu/vs010-openwrt/blob/main/ipq5018-vs010.dts
https://raw.githubusercontent.com/whmzsu/vs010-openwrt/main/ipq5018-vs010.dts
https://github.com/whmzsu/vs010-openwrt
```

**一条命令本地拿全（最可靠）**

```bash
git clone https://github.com/maxdarksol/vs010-openwrt.git
git clone https://github.com/xiangye277/vs010-openwrt.git
git clone https://github.com/whmzsu/vs010-openwrt.git
```

换电脑、换网络、或用手机开热点再试；GitHub 网页能打开时直接点 `Raw` / `Download raw file` 即可。

**从自己机器反编译（可复现 maxdarksol 那份的素材）**

```bash
# 在仍运行 Nwrt 的 VS010 上
dtc -I fs -O dts /sys/firmware/fdt  >  /tmp/vs010-from-nwrt.dts
cat /proc/mtd
```

关联三方 U-Boot（提供 GPIO、网口、分区的实机打印）：
`https://github.com/1980490718/u-boot-2016`

---

## 三、其它平台 / 转载 / 固件资源

| 平台 | 地址 | 说明 |
|---|---|---|
| OpenWrt 论坛 | https://forum.openwrt.org/t/china-unicom-vs010-support/255171 | 三份 DTS 的可信度讨论、完整 mtd 分区表、作者自述 |
| Nwrt 官网 | https://nwrt.kuroneko.host/ | VS010 闭源固件发布方，也是反编译素材来源 |
| 恩山·阿三资源站全备份 | https://www.right.com.cn/forum/thread-8448219-1-25.html | 百度网盘 `https://pan.baidu.com/s/1UWUXmZro0XFKmP-UHnbc1A?pwd=Nwrt`；覆盖 CUCC VS010、CMCC PZL8、rax3000q(y)、CR880X、Redmi AX3000、RG-MA3063 等；另列出 VS010 换壳机型：电信爱飞迅 CMLYQ706X、岭雁 LYW-30M |
| 刷机教程（TTL/网盘） | https://tigress.cc/posts/vs010-openwrt/ | VS010 TTL 接法、1.8V 串口注意、Dropbox「VS010等25个文件.rar」、NWRT 刷机流程 |
| 恩山·互刷变砖实录 | https://www.right.com.cn/forum/thread-8471174-1-87.html | 2026-04-25：VS010 刷 CMCC RAX3000Q 的 U-Boot/大分区后，复位键 GPIO 不一致导致开机循环判定「复位键按下」，TTL 失联，最终需编程器 |
| 恩山·PZ-L8 主线编译帖 | https://www.right.com.cn/forum/thread-8489716-1-21.html | OpenWrt 25.12 / 内核 6.12 / NSS 硬件加速；V1、V2 批次闪存不同 |
| OpenWrt 主线 PZ-L8 PR | https://github.com/openwrt/openwrt/pull/20928 | `qualcommax: ipq50xx: Add support for CMCC PZ-L8` |
| OpenWrt 主线 RAX3000Q commit | https://github.com/openwrt/openwrt/commit/94a80e5 | 另有 2026-09-27 主线合入 `qualcommax: ipq50xx: add support for CMCC RAX3000Q/QY` |
| OpenWrt 主线 MR3000D-CI DTS | https://git.lede-project.org/openwrt/openwrt/tree/target/linux/qualcommax/dts/ipq5018-mr3000d-ci.dts | 本次**未取到全文**；MAC 布局：ART 0x0/0x6/0xc/0x12 |
| QSDK 线（内核 5.4） | `target/linux/ipq50xx/dts/ipq5000-rax3000q.dts` | 第三方 QSDK fork 的 558 行 DTS，本次**未取到全文**；与主线 6.x 的 DSA 绑定不同，不可跨内核复制 |

> 网盘/Dropbox 里的 `.rar` 多为固件、U-Boot、大分区与刷机工具，**不一定含 DTS 源文件**；
> 是否含 `vs010.dts` 标注为「未核实」。

---

## 四、用哪一份、哪些字段必须实机复核

1. **基线**：以 `maxdarksol/vs010-openwrt/vs010.dts` 为准。它来自实机 FDT，不是照抄别机型。
2. **不要**拿 `whmzsu` 版或本包里的 `ipq5018-pz-l8.dts` 直接改名当 VS010 用：
   PZ-L8 的 reset=GPIO33 / WPS=GPIO34、PHY3 作 WAN、WiFi 节点默认 `disabled` 等，
   与原厂 VS010 不一致。
3. 必须上机核对：reset / mesh 键 GPIO、LED GPIO、QCA8337 端口映射（哪个口直连 CPU）、
   `0:ART` 里 MAC 与校准数据偏移、SPI-NAND 型号（批次差异）、`0:TRAINING` 用途。
4. **刷机前必备份**：`0:ART`（校准）、`0:TRAINING`、`0:MIBIB`、`0:APPSBL`/
   `0:APPSBL_1`、整份 `rootfs`。mtd 表见同包 `VS010_原厂MTD分区表.txt`。
   前 18 个分区累加正好 128 MiB；mtd18–23 是 rootfs 里的 UBI 卷，不要重复累加。
5. **互刷 CMCC 固件有实锤变砖案例**（见上表）。VS010 与 RAX3000Q 虽同为 IPQ5018
   + QCA8337，但复位键 GPIO 不同，U-Boot 会一直判定「按键按下」。

---

## 五、一句话

**能抓到的两份 DTS 全文是 CMCC 官方主线机型（PZ-L8 / RAX3000Q），不是 VS010。**
VS010 的三份请按上面 `git clone` 或 raw 直链自行下载；编译以 maxdarksol 版为基线，
并按实机 GPIO/分区复核。网页渲染还原的两份 .dts 仅供字段对照，编译前用 `git show` 核对。
