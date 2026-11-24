# ART 采集报告与无线校准边界（2026-11-24 第 40 次修订）

> **这一版为什么改**：用户新上传的 `ATR文件/` 里有一份 **VS010 好固件实机串口日志**
> （`VS010文件.txt`，转 UTF-8 存档于 `art/oem-bootlog.txt`）和两份 640 KB **U-Boot**。
> 它推翻了上一版一个方向性判断，也把 NAND 补丁从「可能无关」升级为「有据可依」。
> 全程离线、只读；`sh art/collect.sh .` 可随时复核。

## 一、材料清单

| 材料 | 位置 | 性质 |
|---|---|---|
| VS010 完整 `0:ART` | `010-smem_0-ART.bin` | 1 MB，MD5 `e6799786…` |
| RAX3000Q 完整 `0:ART` | `RAX3000Q-mtd13-0ART` | 1 MB，MD5 `4f6f51ad…` |
| **VS010 好固件实机日志** | `ATR文件/VS010文件.txt` → `art/oem-bootlog.txt` | **一手**：dmesg / lsmod / iw dev / /lib/firmware / /proc/mtd / cmdline |
| **两份 U-Boot** | `ATR文件/uboot-ipq50xx-cucc_vs010-*.bin` / `uboot-ipq50xx-cmcc_rax3000q-*.bin` | 各 640 KB，strings 可提闪存表 |
| 两份 ART 副本 | `ATR文件/` 内 | MD5 与根目录两份**完全一致** |

## 二、ART 离线采集真值

| 项 | VS010 | RAX3000Q |
|---|---|---|
| 大小 | 1,048,576 B | 1,048,576 B |
| 头 24 B | 4 个连续单播 MAC `58:95:D8:13:18:EB / EA / EC / ED`（ART+0/+6/+0xC/+0x12） | **全 0xFF** |
| 2G 切片 @`0x1000` | `26b9b9adeb9aff94fbb83efa3f524dbb`，内嵌 MAC `…:EE` | `9a78b59f3a23c1f88b45925b15418850`，占位 MAC |
| 5G 切片 @`0x26800` | `dcf46e01858ac8bf59ef9053651861bc`，内嵌 MAC `…:EF` | `ef733f2c715d519661550dfb0231982a`，占位 MAC |
| BDF magic | `01000404` | `01000404` |

与模板 BDF（`vs010/bdf/board-cucc_vs010.*`）的差异：
VS010 差 1055 / 3013 B，RAX3000Q 差 703 / 3077 B，
**两台切片互差 738 B（0.56%）/ 2552 B（1.95%）** → 射频同构、产线数值逐台不同。

## 三、★ 实机日志的决定性结论：好固件加载了 bdwlan.b10 / bdwlan.b60（⚠ 第 41 次已再修正）

dmesg 原文（两条射频各出现两次，重启前后一致）：

```
Downloading BDF: IPQ5018/regdb.bin, size: 24278
Downloading BDF: IPQ5018/bdwlan.b10, size: 131072
WARN: Caldata not present. Skipping caldata download: IPQ5018/caldata.bin
BDF version: 1 CAL version: 0 Status: 0

Downloading BDF: qcn6122/regdb.bin, size: 24278
Downloading BDF: qcn6122/bdwlan.b60, size: 131072
WARN: Caldata not present. Skipping caldata download: qcn6122/caldata_1.bin
BDF version: 1 CAL version: 0 Status: 0
```

> ⛔ **这段里「MD5 正好等于模板 BDF」已被第 41 次真固件解包推翻**，保留仅为留痕。
> 当时只看了 dmesg 的文件名与大小，并**没有**拿到 5.4.213 固件的字节。

**第 41 次实证（两个 27 MB factory.bin 真解包）**：好固件的
`bdwlan.b10` / `bdwlan.b60` 与本仓模板 BDF、4.4.60 老固件 BDF、ART 切片
**四套互不相同**，且 VS010 与 RAX3000Q 之间也互不相同：

| 来源 | 2G | 5G |
|---|---|---|
| 5.4.213 VS010 | `4ce1ecfc…` | `80badcdd…` |
| 5.4.213 RAX3000Q | `4b9aba89…` | `e43c4cf0…` |
| 本仓模板 | `c7d89771…` | `0aadbd42…` |

> **仍然成立、且被加强的结论**：好固件加载 `bdwlan.b10`/`bdwlan.b60`、
> 报 `Caldata not present` / `CAL version 0`、**不加载独立 caldata**（两台真实 DTB 的
> `qcom,caldb-addr=0` / `caldb-size=0` 是 DTS 级铁证）。ART 切片没有被加载，
> 「ART 切片禁止进固件」的策略不变，而且**更有理由**（模板 BDF 的等价性也没有证据了）。
>
> **再修正**：`from-oem` 降级为**实验性可选**（用本仓模板 BDF 造容器，不宣称等价于好固件）；
> 默认 `ART_CALIBRATION=0` 完全不装配。完整取证见 **[docs/OEM-QSDK12.2-取证报告.md](OEM-QSDK12.2-取证报告.md)**。

其它一手真值（都写进 `art/art-truth.conf` / `vs010/wifi-truth.conf`）：

| 项 | 实机值 | 用得上吗 |
|---|---|---|
| `platform name` | `CUCC VS010` | 参考；本仓 DTS 的 variant 仍是 `Unicom-VS010`，容器名与 DTS 一致即可 |
| `bdwlan.b10` / `.b60` | board_id `0x10` / `0x60` → qmi-board-id **16 / 96** | ✅ `from-oem` 的默认条目名，终于有实机依据 |
| `Target capability: board_id: 0xff` | 另一个字段 | ❌ 别拿它当 qmi-board-id |
| `mem mode : [2]` | 闭源 cnss2 | ❌ **不要抄进主线 ath11k DTS**（本仓是 1） |
| `device_id` | `0xfffc` / `0xfffb` | ✅ 与 `wifi-truth.conf` 一致 |
| `bdf_dnld_method 1` | QMI WLFW 从 rootfs 下发 | ✅ 无 DDR 搬运、无 `cnss2.bdf_*` |
| `lsmod` | `qca_ol / umac / wifi_3_0 / ipq_cnss2 / qdf / qca_nss_drv / ecm / qca_ssdk`，**无 ath11k、无 mac80211** | ✅ `VERIFIED=0` 的理由被完全证实 |
| 无线 MAC | 2.4G `00:25:5C:11:62:74`；5G `00:03:7F:12:EF:EF` | ⚠ 5G 是 **BDF 占位家族**，ART 头真 MAC 没被无线用 |
| 老固件射频 | 5G ch149/80MHz/27dBm；2.4G ch13/40MHz/20dBm | 参考对照；本仓要满速用 ch36 HE160 / ch1 HE40 |
| `/proc/mtd` | `mtd13: 00100000 "0:ART"`，另有 `0:APPSBLENV` / `0:TRAINING` | ✅ 分区名再次确认 |
| cmdline | 无 `cnss2.bdf_*` | ✅ 之前结论正确 |

## 四、三个能定死的结论（更新版）

**1. 无线参数两台共用，不必按机型拆。** 两份 ART 的偏移、128 KB 长度、magic
完全一致，差异只有 0.56% / 1.95% → 射频硬件同构。`files*/etc/config/wireless`
的 `CN` / 5G `ch36 HE160` / 2.4G `ch1 HE40` 继续两台共用，**按机型分的是校准数据**。

**2. 校准按机型分开，且用实证在用的那份。** 两台切片互差 738 / 2552 字节，
绝不跨机；同时**不要拿 ART 切片当固件校准**（上面第三节）。
`board-inject.sh` 严格按 `art/out/<机型>/` 取，禁止跨机回落；容器里若检出
ART 切片 MD5 会发 `::warning::`。

**3. ART 不是 `board-2.bin`。** 单个 128 KB BDF ≠ `QCA-ATH11K-BOARD` 容器。
直接改名会让驱动解析失败、射频不 probe。这是老仓库 VS010 5G 弱的根因之一。

## 五、明确不做的事

| 不做 | 理由 |
|---|---|
| **不把 ART 切片编进固件 / 不当 caldata** | 实机日志：好固件 `Caldata not present`、`CAL version 0` 且双频正常，加载的是模板 BDF。改这条已验证能工作的链路风险大于收益。 |
| **不默认替换官方 `board-2.bin`** | 官方通用容器是射频能 probe 的兜底；本机条目匹配不到时它还能救回来。 |
| **不按机型拆 `wireless`** | 硬件同构已被 ART 证实。 |
| **不猜 `qmi-board-id` / `variant`** | 现在有实机依据：`0x10=16` / `0x60=96`；variant 必须与 DTS 一致，别凭 `platform name` 擅自改。 |
| **不自动写 MAC** | 实机 5G 用了 `00:03:7F:12:EF:EF` 占位；`art-check` 只检测并提示，不擅自 `uci set`。 |
| **不照抄闭源栈参数** | `mem mode [2]`、`qcom,board_id 0x10/0x60` 的 6 元组 bdf-addr 都属于 `ipq_cnss2`，主线 ath11k 用单值 + `ath11k-calibration-variant`。 |

## 六、实际修了什么（本轮）

1. **`art/oem-bootlog.txt`**：实机日志转 UTF-8 存档，只读、不参与编译。
2. **`art/art-truth.conf` / `vs010/wifi-truth.conf`**：补 30+ 条一手真值；
   `OEM_BDF_VERDICT` 明确「用模板 BDF，ART 切片禁止进固件」。
3. **`art/make-board2.py` 新增 `from-oem`**：用实证模板 BDF + 实机 board_id
   （16 / 96）造/追加容器，官方 `ath11k-bdencoder --info` 交叉验证通过。
   `slice` 降级为「仅采集/存档」。
4. **`scripts/board-inject.sh`**：装配前解析容器，命中 ART 切片 MD5 就警告并
   指引 `from-oem`；签名校验、跨机保护保留。
5. **`art/collect.sh`**：新增「模板 BDF vs ART 切片」实证对照段。
6. **`files/usr/sbin/art-check`**：新增无线 MAC 占位家族检测
   （`00:03:7F:12:xx:xx` / `FF:FF:FF`），结论段换成实机证据。
7. **`scripts/verify.sh`**：新增实机日志资产、BDF 来源、from-oem、占位 MAC 判据。
8. **NAND 章节**：补 U-Boot 实证（见第八节）。

## 七、想用本机校准（可选，默认关）

**前提**：TTL 串口能进、`dmesg | grep -iE 'ath11k|board_id|bdf'` 看得到实机
board_id、确认树内 DTS 的 `ath11k-calibration-variant`。缺一样就别开。

```sh
# 1) 用好固件实证在用的模板 BDF 造容器（★ 不要用 slice 的 ART 切片）
python3 art/make-board2.py from-oem \
  --base /path/to/upstream/board-2.bin \
  --out art/out/vs010/board-2.bin

# 2) 核对条目名与 data
python3 art/make-board2.py info art/out/vs010/board-2.bin
python3 art/tools/ath11k-bdencoder --info art/out/vs010/board-2.bin

# 3) 编译时显式开（不开就完全不引用）
ART_CALIBRATION=1 sh scripts/board-inject.sh vs010 openwrt
```

RAX3000Q 同理，输出到 `art/out/rax3000q/`；`--variant` 若与树内 DTS 不一致要同时改。
**回退**：删掉对应 `board-2.bin` 重编，回到官方通用容器。

## 七点五、第 41 次补正：DTB 里确实有 bdf-addr

第 40 次从 U-Boot strings 判定「无 `cnss2.bdf_*` / `4c400000` / `4d300000`」，
那**只对 U-Boot 成立**。真解包两台 5.4.213 固件的 FIT 后抽出真实 DTB：

```
/soc/wifi@c000000   qcom,board_id = <0x10>(VS010) / <0x24>(RAX3000Q)
                    qcom,bdf-addr = 0x4c400000   qcom,caldb-addr = 0
/soc/wifi1@c000000  qcom,board_id = <0x60>       qcom,bdf-addr = 0x4d300000
                    qcom,tgt-mem-mode = <2>      qcom,caldb-size = 0
```

U-Boot 不搬、由闭源 `ipq_cnss2` 自己把 BDF 放进保留内存，两者不矛盾。
**`bdf-addr` / `tgt-mem-mode=2` / `board_id` 都属于 cnss2，禁止抄进主线 ath11k DTS。**

## 八、U-Boot 与 NAND 补丁（判断升级）

两份 U-Boot 的 strings 里，**名称表同时包含**：

```
F50D1G41LB(2M)          ← ESMT，V1 批次
FM25LS01 / FM25LS02BI3  ← 复旦微，V2 批次
```

还有 `board_update_caldata` / `failsafe_write_art` / `qpic_nand_read_id_serial` /
`qpic_spi_nand_config`；**没有** `bdwlan`、`cnss2.bdf_*`、`4c400000`、`4d300000`。

→ **U-Boot 侧已认 FM25LS01，V2 批次真实存在**，所以 Linux 侧
`qcom_snand` 的 `440-…FM25LS01.patch` 对 V2 板子是**必需**的，不是无关补丁。
但补丁的 `NAND_ECCREQ(8,512)` 与数据手册 `1-bit/512` 不符、声明值必须和
U-Boot 写入时一致（否则 `-74 EUCLEAN` 读不出 UBI），风险不变 → **默认仍关**。

**怎么判断自己是 V1 还是 V2**：TTL 看 U-Boot 启动打印的
`flash_type / flash_index / flash_density`，或 Linux 里
`dmesg | grep -iE 'qpic|spinand|flash id'`；报 `unknown flash ID 0xA5` 且确认 V2
再勾 `nand_patch`。详见 `patches/README.md`。

## 九、ART 只解决「准不准」，不解决「起不起来」

让无线能 probe 靠：`DEVICE_PACKAGES` 的 ath11k 固件、`board-2.bin` 容器、
DTS 的 `qcom,ath11k-calibration-variant` / `bdf-addr`、NSS/ECM 卸载链。
ART 里没有 `board_id` / `bdf-addr` / cmdline 参数，驱动 `.ko` 也不能跨内核搬。

`wifi-truth.conf` 的 `VERIFIED=0` 现在**被一手 lsmod 完全证实**：好固件是闭源
`qca_ol / umac / wifi_3_0 / ipq_cnss2`，本仓是开源 `ath11k`。采集 ART、
补 caldata、改 DTS 数值都修不好驱动栈不兼容。

> ⚠ 产线校准逐台独立，只用于你这台机器；别跨机刷、别外传这两份 ART 与 U-Boot。
