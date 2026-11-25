#!/bin/sh
# 第 41 次 · 从仓库 files/ 与 files.ap/ 重新生成 oem54/oem-overlay.tar.gz
# 用法：在仓库根目录执行  sh oem54/build-oem-overlay.sh
# 只挑【安全】的页面 / 只读自检工具 / LuCI 自修；绝不把网络配置打进包。
set -eu
cd "$(dirname "$0")/.."
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
pick(){ s=$1; d=$2; [ -f "$s" ] || { echo "::error::缺 $s"; exit 1; }; mkdir -p "$T/$(dirname "$d")"; cp "$s" "$T/$d"; }
pick files/www/bridge/index.html        www/bridge/index.html
pick files/www/cgi-bin/bridge           www/cgi-bin/bridge
pick files.ap/www/ap/index.html         www/ap/index.html
pick files.ap/www/cgi-bin/apstatus      www/cgi-bin/apstatus
pick files/usr/sbin/portstat            usr/sbin/portstat
pick files/usr/sbin/health-fix          usr/sbin/health-fix
pick files/usr/sbin/luci-fix            usr/sbin/luci-fix
pick files/usr/sbin/luci-entry          usr/sbin/luci-entry
pick files/usr/sbin/wifi-bdf-check      usr/sbin/wifi-bdf-check
pick files/usr/sbin/wifi-art-cal        usr/sbin/wifi-art-cal
pick files/usr/sbin/wifi-stack-check    usr/sbin/wifi-stack-check
pick files/usr/sbin/accel-check         usr/sbin/accel-check
pick files/usr/sbin/tty-diag            usr/sbin/tty-diag
pick files/usr/lib/bridge/role.sh       usr/lib/bridge/role.sh
pick files/etc/config/art-truth.conf    etc/config/art-truth.conf
pick files/etc/config/oem-stack-truth.conf etc/config/oem-stack-truth.conf
pick files/etc/bridge.conf              etc/bridge.conf
pick files/etc/init.d/luci-fix          etc/init.d/luci-fix

# 第 44 次：把 QSDK 适配运行期材料（自动一主一备 / 机器狗 / 网口守护 / AP 工具）
# 原样收进包内 usr/lib/oem54/payload/，由 apply-oem-overlay.sh 按模式自动装配。
# 这样「刷官方原版固件后现场叠加」也能一次带上全套，不用手动搬脚本。
if [ -d oem54/payload ]; then
  mkdir -p "$T/usr/lib/oem54/payload"
  ( cd oem54/payload && tar cf - . ) | ( cd "$T/usr/lib/oem54/payload" && tar xf - )
fi
find "$T" -type f \( -path '*/sbin/*' -o -path '*cgi-bin*' -o -path '*init.d*' \) -exec chmod 755 {} +
tar czf oem54/oem-overlay.tar.gz -C "$T" .
echo "✓ 生成 oem54/oem-overlay.tar.gz：$(tar tzf oem54/oem-overlay.tar.gz | wc -l) 文件 / $(stat -c %s oem54/oem-overlay.tar.gz) 字节"
# 安全网：确认危险路径一个都没进包
for k in etc/config/network etc/config/wireless etc/config/dhcp etc/config/dropbear etc/config/uhttpd etc/uci-defaults/99-bridge-ready etc/rc.local usr/sbin/dhcp-guard etc/init.d/bridge-; do
  if tar tzf oem54/oem-overlay.tar.gz | grep -q "$k"; then echo "::error::危险路径进包：$k"; exit 1; fi
done
echo "✓ 安全网通过：网络配置 / 首启脚本 / rc.local / dhcp-guard 均未进包"
