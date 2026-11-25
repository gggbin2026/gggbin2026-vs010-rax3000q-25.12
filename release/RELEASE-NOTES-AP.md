✅ **【第 56 次】** 修复了 Release 发布步骤的 `exit 127`：旧写法把整段 Markdown 塞进 `NOTES="..."`，里面的反引号被 bash 当成命令替换执行（编译本身早已成功、固件也上传 artifact）。现改为独立 `.md` 文件 + `gh release create --notes-file`，说明文本不再经过 shell 解释。

🔴 **【插件基线已冻结】** 以第 51 次为准：82 项**只增不减**，少一项 `gen-config.sh` 直接 `::error::` 阻断；详见仓库 `baseline/插件基线冻结报告.html`。

🔴 **【改 AP 管理 IP 必读】** 出厂 `172.10.10.241` / `255.255.252.0`（/22）。AP 模式机器狗停用不会自动重启；改 IP 后 SSH / LuCI / TTYD / 管理页都换新地址，PC 需同网段。

> ⚠️ 若手动启用过机器狗，改 IP 后必须 `bridge-watchdog resync` 或 `set-peer <对端IP>`。详见随附 `CHANGE-IP-NOTICE.txt`。🔴

**命名**：`Nwrt-AP-<内核版本>-<日期>-<机型>-*.ubi / *.bin`（tag 带内核版本、后缀 `-ap`）

**模式**：普通哑 AP。WAN+LAN+2.4G+5G 全在 `br-lan`；管理 `172.10.10.241`，`NwrtAP-2G` / `NwrtAP-5G`，本机 DHCP 关；NTP 每 5 分钟循环校时（`ntp-poller`，`set-minutes` 可改）；无 WDS / 无主备 / 机器狗停用（AP 无 WDS 链路）。

**无线**：NSS FW 12.5 优先（12.2 回退）+ ECM→NSS 双射频卸载；CN / ch36 / HE160 / 本机 BDF / 256M LOW；HE160 在 CN 下覆盖 DFS，开机 5G 需约 60s CAC。

**参考**：mufeng05/openwrt-cmcc-pz-l8-nss 的 QSDK14 驱动口径（有线+双射频 949Mbps / 5G 160MHz 697Mbps / CPU 2.9%）。

⚠ 纯二层桥内被卸载的流量不经过 Linux 网桥：判速看 `eth0/eth1` + NSS debugfs，不要看 `br-lan`。

**防护**：无线端 rogue DHCP 已拦；firewall4 编译期关闭；上级 DHCP 正常透传。

**精简**：只编 SSH(`dropbear`) + TTYD + LuCI 底座/中文/官方 bootstrap 主题 + 状态页，未编任何第三方 `luci-app-*`。

**界面保障**：主题下拉只列真实存在的目录；`luci-fix` 每次开机重建 named main 并清理幽灵主题，不再出现 `dispatcher.lua:427` / 主题切换后 500。

**界面**：CPU 状态新增温度（多传感器 + 配色）、TTYD 入口、NSS 加速与防护状态。

⚠ 刷前确认不死 U-Boot 支持 64 位引导；上级不在 `172.10.8.0/22`（掩码 `255.255.252.0`）时改 lan 为 dhcp。完整说明见仓库 `MIGRATION.md` / `FIRMWARE.md`。
