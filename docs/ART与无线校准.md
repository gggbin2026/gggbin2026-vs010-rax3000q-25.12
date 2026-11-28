# ART / BDF / 无线校准口径

## 三件事同一个原则：只补能实证的，不砸已经能工作的链路

| 问题 | 结论 |
|---|---|
| 无线是不是按两个路由改的 | 两台射频同构（ART 切片偏移、长度、magic 全同，差异仅 0.56% / 1.95%）→ `wireless` 参数**两台共用**；按机型分的是校准数据，不是射频配置 |
| NAND 补丁加了吗 | 备好但默认关（V2 批次真实存在，EUCLEAN 风险不变） |
| ART 要不要采集修复 | 已采集，但**不把 ART 校准编进固件** |

## 第 40 / 41 次纠正（比上面更重要）

新上传的实机串口日志里 dmesg 白纸黑字：

```
Downloading BDF: IPQ5018/bdwlan.b10, size: 131072
Downloading BDF: qcn6122/bdwlan.b60, size: 131072
WARN: Caldata not present ... BDF version: 1 CAL version: 0 Status: 0
```

- 好固件加载的是**模板 BDF**，ART 切片根本没被加载；
- 第 41 次进一步作废「好固件 BDF 的 MD5 == 模板 BDF」这句断言：
  四套 BDF（好固件两台 / 模板 / 4.4.60 / ART 切片）**互不相同**；
- `from-oem` 降级为实验性可选，默认不装配；
- 好固件是闭源 `qca_ol/umac/ipq_cnss2`，**无 ath11k、无 mac80211**；
- 两台真实 DTB 里确实有 `qcom,bdf-addr`，但那是 cnss2 的，**禁止抄进 ath11k DTS**；
- 不改 DTS 的 mem mode（实机闭源栈是 `[2]`，主线 ath11k 本仓是 `1`）。

## 本仓落地

- `ART_CALIBRATION=0` / `CALDATA_DEFAULT=off`，固件用官方通用 `board-2.bin`；
- `board-inject.sh` 检出容器内混有 ART 切片只警告，不装配；
- `DEVICE_PACKAGES` 必补 `ath11k-firmware-ipq5018-qcn6122` + `kmod-ath11k-ahb` +
  本地 `ipq-wifi` 包，否则射频根本不 probe；
- 无线满速口径：NSS FW 12.5 · ECM→NSS / wifili · CN · 5G ch36 / HE160 ·
  本机 BDF + 256M LOW；
- 两条固有代价：CN+HE160 开机约 60 秒 CAC（5G 不可见、2.4G 先起）；
  2.4G HE40 默认因共存扫描退 20MHz（`noscan=1` 强开可 +50% 但无视邻区共存，默认不开）。
