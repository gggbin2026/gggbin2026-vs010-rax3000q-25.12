# 刷机（VS010 / RAX3000Q）

🔴 **三条硬前提**

1. 不死 U-Boot 必须支持 **64 位 aarch64 引导**。5.4 老仓是 32-bit arm，本仓四条基线全是 aarch64。
2. 首次刷 **3.3V USB-TTL 在手边**（VS010 UART 是 1.8V 电平，注意电平转换），波特率 115200n8。
3. 严格按机型对应固件：`vs010` ↔ 联通 VS010，`rax3000q` ↔ CMCC RAX3000Q/QY。
   刷完不要勾「保留配置」（旧 overlay 的 `/etc/config/luci` 会盖掉编译期 named `main`）。

建议顺序：`device=vs010` 单跑一次 → TTL 验证能起、射频 probe、`wifi-fullspeed` 通过 → 再 `both`。

## 方法一：VS010 原厂 Web API（xiangye277 仓库已验证的路径）

```bash
PASSWD_B64=$(echo -n '原厂密码' | base64)
curl -s -D - -X POST http://192.168.2.1/api \
  -d "luci_username=user&luci_password=$PASSWD_B64"     # 从 Location 头取 stok
curl -F "size=$(stat -c%s 固件.img)" -F "file=@固件.img" \
  "http://192.168.2.1/api/;stok=TOKEN/admin/advance/upgrade"
```

字段 `file` + `size`，格式 `.img`。原仓归档见 `reference/xiangye277/FLASHING.md`。

## 方法二：U-Boot TTL + TFTP（更安全）

老仓 `README` 的 U-Boot 设置：电脑 IP `192.168.1.8`，用 **LAN1** 口。
xiangye277 文档给的是 `10.1.1.1/10.1.1.2`，两种都在，按你手上 U-Boot 的实际 env 走：

```
setenv ipaddr 10.1.1.1
setenv serverip 10.1.1.2
tftpboot 0x44000000 firmware.img
flash rootfs 0x44000000 0xSIZE      # SIZE 取 tftpboot 返回值
reset
```

## 板级验证清单（刷完 TTL 逐条看）

- `uname -r` = 编译期实抓的内核版本，`/etc/nwrt/baseline` 与 workflow 选择一致；
- `lsmod | grep ath11k` 有 `ath11k` / `ath11k_ahb`，**不是** `qca_ol` / `umac` / `ipq_cnss2`；
- `iw dev` 或 `iwinfo` 能看到两个射频；`wifi-fullspeed` 输出 5G HE160 / CN / 2.4G HE40；
- `cat /sys/class/net/eth0/statistics/rx_bytes` 与 `eth1` 有计数；
- 温度读不到显示「—」，不是报错、不是假数值；
- `/bridge/`（WDS 固件）或 `/ap/`（AP 固件）能直接打开，未登录只读可见；
- `http://<IP>/cgi-bin/luci/` 能打开，主题下拉只有实际存在的主题。

## 变砖边界

- 两台 DTS **不定义按键**：复位键 GPIO 冲突会循环重启、TTL 失联、需编程器（恩山实录）。
- VS010 端口排序不改（正确基线未取到，改错网口全灭；WAN+LAN 全在 `br-lan` 故 label 错位不影响桥接）。
- 不改 `qcom,bdf-addr`、不改 boot-args、不整份替换 DTS。
- NAND V2 补丁默认关；EUCLEAN 风险不变。
