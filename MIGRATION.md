# 5.4 → 6.12 迁移边界

## 能迁移（工作方式 / 视觉 / 规格）

- 官方 OpenWrt 源码树口径（xiangye277 本质），但改成锁 ref；
- WDS 4addr 纯二层桥 + AP 双频，**单包双模式**（本版在界面里切，不重刷）；
- UBNT / UniFi 深色界面（共享 CSS + 零侵入注入器，三入口 + 全互访 + 登录态）；
- 稳定 / 低内存 / 无线开启快 / SSH+串口+TTYD 必在的硬验收标准；
- ECM→NSS + wifili 的加速**思路**与判速口径（看 `eth0/eth1` 与 NSS debugfs，不看 `br-lan`）；
- 不加载 caldata、默认用官方通用 `board-2.bin`、ART 只采集不进固件；
- 精简：关防火墙 / IPv6 / 本机 DHCP 服务端 / 第三方插件 / 科学上网 / 拨号协议。

## 不能迁移（照抄必挂）

| 5.4 好固件 | 6.12 本仓 | 原因 |
|---|---|---|
| 闭源 `qca_ol` / `umac` / `ipq_cnss2` | 主线 `ath11k` + `mac80211` | `.ko` 跨内核必挂，WiFi FW 格式不同 |
| QSDK 单 BDF `bdwlan.b10/.b60` | `board-2.bin` 容器 | 不是同一种格式，不能改名当容器 |
| `qcawifi.sh` 的 `HT160` 写法 | `HE160` / `HE40`（hostapd） | 主线无线脚本不认 QSDK 约定 |
| 5.4 的 `ipq5000-*.dts` / 32-bit arm | 6.12 `ipq5018-*.dts` / aarch64 | DTS 绑定、内存档、时钟全变 |
| `vs010-tick` 单常驻 + `bridge-watchdog`（停用） | 单个 `nwrt-tick`，出厂 dryrun=1 | 合掉第二个守护，保留 NTP / 关联巡检 |
| `vs010-tick` 单常驻 + `bridge-watchdog`（停用） | 单个 `nwrt-tick`，出厂 dryrun=1 | 合掉第二个守护，保留 NTP / 关联巡检 |
| `vs010-tick` 单常驻 + `bridge-watchdog`（停用） | 单个 `nwrt-tick`，出厂 dryrun=1 | 合掉第二个守护，保留 NTP / 关联巡检 |
| `vs010-tick` 单常驻 + `bridge-watchdog`（停用） | 单个 `nwrt-tick`，出厂 dryrun=1 | 合掉第二个守护，保留 NTP / 关联巡检 |
| 真实 DTB 里的 `qcom,bdf-addr` | 不抄进 ath11k DTS | 那是 cnss2 的，跨栈/跨绑定 |
| ART 切片当本机校准 | 默认关闭 `ART_CALIBRATION` | 实机日志 `Caldata not present`，加载的是模板 BDF |
| `swconfig` / QSDK 双 GMAC | DSA（或 NSS 基线的 qca-ssdk） | 用户态与内核接口不同 |

## 结论

**能提取文件，不能拷过去加速。** 好固件（Linux 5.4.213 / QSDK 12.2 / OpenWrt 19.07 /
WLAN.HK.2.8-01492）里能拿到无线/有线参数、驱动清单、DTB、启动脚本、4 份 BDF，
但驱动栈不同，能迁移的只有「工作方式」。本仓已把这些方式逐条落地。

三条基线对照见 README 第一节；板级逐项真值见 `docs/板级真值.md`。
