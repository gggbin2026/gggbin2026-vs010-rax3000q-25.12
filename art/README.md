# art/ —— 0:ART 采集与校准资产

完整报告与边界见 **[docs/ART与无线校准.md](../docs/ART与无线校准.md)**（先看那个）。

| 文件 | 作用 |
|---|---|
| `art-truth.conf` | 两份 ART 的 MD5 / 偏移 / MAC / 切片 MD5 + **实机日志与 U-Boot 一手真值**；编译期复制为 `/etc/art-truth.conf` |
| `oem-bootlog.txt` | VS010 好固件实机串口日志（转 UTF-8 存档）：dmesg / lsmod / iw dev / /lib/firmware / /proc/mtd |
| `collect.sh` | `sh art/collect.sh .` 离线复核，只读、不联网、不改 ART |
| `make-board2.py` | **`from-oem`**（实证模板 BDF 造容器，推荐）/ `slice`（仅采集）/ `create` / `append` / `info`；格式与官方 `ath11k-bdencoder` 一致 |
| `tools/ath11k-bdencoder` | QCA 官方工具副本（BSD-3-Clause，许可见同目录 `LICENSE.*`），用于交叉验证 |
| `out/<机型>/board-2.bin` | **可选产物，默认不存在**；存在且 `ART_CALIBRATION=1` 时才会被 `board-inject.sh` 装配 |

两份原始 ART 在**仓库根目录**（`010-smem_0-ART.bin` / `RAX3000Q-mtd13-0ART`），
不放在 art/ 里，也不进固件；`art/` 只放只读真值与工具。

## 三条硬规矩

1. **默认不引用 ART**：`CALDATA_DEFAULT=off` / `ART_CALIBRATION_DEFAULT=0`。
   固件仍用官方通用 `board-2.bin`，射频照常 probe。
   **ART 切片禁止进固件**：实机日志证明好固件用的是模板 BDF（`bdwlan.b10`/`b60`），
   不是 ART 切片；本机校准请用 `from-oem`。
2. **不把 ART 切片直接改名成 `board-2.bin`**：单个 BDF ≠ 容器，改名会让驱动解析失败。
   要合成请用 `make-board2.py`，并用 `tools/ath11k-bdencoder --info` 验证。
3. **不跨机用**：VS010 与 RAX3000Q 的切片互差 738 / 2552 字节，是各自独立的产线校准。

## 快速自查（实机）

```sh
art-check          # 或 sh /usr/sbin/art-check
health-fix         # 第 6 段会顺带调用
wifi-bdf-check     # 查 board-2.bin / calibration-variant 是否装对
```
