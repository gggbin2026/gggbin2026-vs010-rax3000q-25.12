# VS010 原厂 BDF（板级射频数据）

这两个 128 KB 二进制是 **CUCC VS010 本机产线板级数据**，直接从
`xiangye277/vs010-openwrt` 仓库的 `oem_extract/` 目录取得（该目录随 VS010
OpenWrt 适配项目一起发布，作者从原厂固件提取）：

| 本仓库文件 | 上游源文件 | 用途 | 大小 | MD5 |
|---|---|---|---|---|
| `board-cucc_vs010.ipq5018` | `oem_extract/bdwlan.bin` | 2.4G / IPQ5018 内置射频 | 131072 | `c7d89771464322ea39ca290249295af9` |
| `board-cucc_vs010.qcn6122` | `oem_extract/qcn6102_bdwlan.bin` | 5G / QCN6102 外挂射频 | 131072 | `0aadbd42dc960aefdffe09177dd275b9` |

来源：https://github.com/xiangye277/vs010-openwrt/tree/main/oem_extract
（上游另有 `fw_version.txt` / `qcn6122_bdwlan.bin` 两个 50 字节文件，内容实为
`<h1>Not Found</h1>` 的下载失败占位，**不是** BDF，未纳入本包。）

## 为什么需要它

RAX3000Q 与 VS010 虽同为 IPQ5018 + QCN6102，但 FEM（功放）不同：
RAX3000Q 2.4G 外挂 2×RTC66266、5G 外挂 2×RTC66568；VS010 2.4G 只有 SoC
内置 FEM、5G 是 2×KCT8539S。BDF 里写死了每路目标功率、FEM 增益补偿、
天线增益与法规功率表。VS010 若只用 `ath11k-firmware-ipq5018` /
`ath11k-firmware-qcn6122` 自带的**通用** `board-2.bin`，驱动拿不到
KCT8539S 的功率曲线，表现就是「能连上、能扫到，但覆盖和速率腰斩」。

原编译配置只给 RAX3000Q 装了 `ipq-wifi-cmcc_rax3000q`（专用 BDF 覆盖包），
VS010 没有对应包 —— 这就是「3000Q 的无线驱动用到 VS010 信号弱」的实质。
本包新增 `ipq-wifi-cucc_vs010`，把上面两个文件按 OpenWrt `ipq-wifi` 的
约定安装成 `/lib/firmware/ath11k/IPQ5018/hw1.0/board-2.bin` 与
`/lib/firmware/ath11k/qcn6122/hw1.0/board-2.bin`。

## 注意

- 这两个包**互斥**：`ipq-wifi-cmcc_rax3000q` 与 `ipq-wifi-cucc_vs010`
  都往同一路径写 `board-2.bin`，同一固件里只能装一个。两份 slim 已按机型
  强制「本机 =y、他机 =n」。
- ART 校准窗口偏移仍沿用同平台经验值（0x1000 / 0x26800，各 0x20000），
  **未经 VS010 原厂 fdt 逐字节实证**。刷完用 `wifi-bdf-check` 看 dmesg 是否
  报 `calibration data invalid`；若报，需按本机 `0:ART` 实测定偏移。
- QSDK 21.02 若走 cnss2 从 DDR 读 BDF，则 rootfs 里的 `board-2.bin` 不参与；
  `wifi-bdf-check` 会把 `BDF location` / `bdwlan.bXX` 一并打印，按结果再决定
  是否要把这两个文件写进 `wifi_fw` 分区。
