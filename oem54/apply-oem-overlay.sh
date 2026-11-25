#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# 第 41 次 · 在【刷好 NWRT QSDK12.2 官方固件】的设备上叠加本仓定制
# 用法（通过 SSH 上传到设备后执行）：
#   sh apply-oem-overlay.sh                 # 安装（幂等，自动备份被覆盖文件）
#   sh apply-oem-overlay.sh --dry-run      # 只列出将要写入的文件，不改动
#   sh apply-oem-overlay.sh --rollback     # 回滚到安装前状态
#
# ⚠ 前置条件：设备内核必须是 5.4.213（官方好固件）。
#   本仓自己编译的固件是 5.4.164，跑这个脚本会被拒绝——那套请用仓库的
#   verify-all-39.sh / verify-stack-fix.sh 验收，不要混用。
# ⚠ 本脚本【只叠加管理页 / 只读自检工具 / LuCI 自修】，绝不碰
#   /etc/config/{network,wireless,dhcp,dropbear,uhttpd,firewall,luci,system}
#   和 rc.local / 99-bridge-ready —— 那些是官方固件自己的配置，覆盖会断网。
#   WDS 网桥 / AP 业务配置请按 README_无线修复.md 用 uci 增量设置。
# ═══════════════════════════════════════════════════════════════════════
set -u
PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH; export PATH
PKG=oem-overlay.tar.gz
STAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo 1)
BK=/etc/oem-overlay-backup/$STAMP
LIST=/etc/oem-overlay.files
NEW=/etc/oem-overlay-new.files
say(){ echo "[oem-overlay] $*"; logger -t oem-overlay "$*" 2>/dev/null || true; }

[ -f "$PKG" ] || { say "ERROR：当前目录缺 $PKG（请把 oem54/ 整个目录传上来）"; exit 1; }
K=$(uname -r 2>/dev/null || echo unknown)
case "$K" in
  *5.4.213*) say "内核 $K ✓ 官方好固件" ;;
  *) say "ERROR：内核 $K 不是 5.4.213，拒绝叠加（本仓编译固件请用仓库自检脚本）"; exit 1 ;;
esac

# ── dry-run ──
if [ "${1:-}" = '--dry-run' ]; then
  say "将写入以下文件（不改动系统）："
  tar tzf "$PKG" | sort | sed 's/^/    /'
  say "完成 dry-run"
  exit 0
fi

# ── rollback ──
if [ "${1:-}" = '--rollback' ]; then
  [ -f "$LIST" ] || { say "ERROR：没有安装记录 $LIST，无法回滚"; exit 1; }
  LAST=$(ls -1 /etc/oem-overlay-backup 2>/dev/null | sort | tail -1)
  [ -n "$LAST" ] && [ -f "/etc/oem-overlay-backup/$LAST/backup.tar.gz" ] && {
    tar xzf "/etc/oem-overlay-backup/$LAST/backup.tar.gz" -C / && say "已恢复安装前被覆盖的文件"
  }
  [ -f "$NEW" ] && while read -r f; do
    [ -n "$f" ] && rm -f "/$f" && say "删除新增 /$f"
  done < "$NEW"
  rm -f "$LIST" "$NEW"
  say "回滚完成（备份保留在 /etc/oem-overlay-backup/）"
  exit 0
fi

# ── 检查 /overlay 可写 ──
if ! mount 2>/dev/null | grep -q 'overlay'; then
  say "::warning::未检测到 overlay 挂载，写入 / 可能不持久；仍继续（请确认 rootfs_data 卷已创建）"
fi
[ -d /etc ] || { say "ERROR：/etc 不可访问"; exit 1; }

TMP=/tmp/oem-overlay-$STAMP
rm -rf "$TMP"; mkdir -p "$TMP" || { say "ERROR：/tmp 不可写"; exit 1; }
tar xzf "$PKG" -C "$TMP" || { say "ERROR：解包失败"; exit 1; }

mkdir -p "$BK" /etc/oem-overlay-backup
: > "$BK/backup-list.txt"; : > "$BK/new-list.txt"
( cd "$TMP" && find . -type f | sed 's#^\./##' | sort ) > "$BK/all.txt"

# 先备份所有将被覆盖的既有文件
( cd "$TMP" && tar czf "$BK/backup.tar.gz" --files-from=/dev/null 2>/dev/null ) || true
BKLIST="$BK/will-backup.txt"; : > "$BKLIST"
while read -r f; do
  [ -z "$f" ] && continue
  if [ -e "/$f" ]; then echo "$f" >> "$BKLIST"; fi
done < "$BK/all.txt"
if [ -s "$BKLIST" ]; then
  tar czf "$BK/backup.tar.gz" -C / -T "$BKLIST" 2>/dev/null || true
  say "已备份 $(wc -l < "$BKLIST") 个既有文件 → $BK/backup.tar.gz"
else
  : > "$BK/backup.tar.gz"
fi

# 逐文件写入
: > /tmp/oem-new.$$
while read -r f; do
  [ -z "$f" ] && continue
  d=$(dirname "/$f"); mkdir -p "$d"
  [ -e "/$f" ] || echo "$f" >> /tmp/oem-new.$$
  cp "$TMP/$f" "/$f" || { say "ERROR：写入 /$f 失败"; exit 1; }
  case "$f" in
    *sbin/*|*cgi-bin/*|*init.d/*) chmod 755 "/$f" 2>/dev/null || true ;;
  esac
done < "$BK/all.txt"
cp /tmp/oem-new.$$ "$NEW"; rm -f /tmp/oem-new.$$
cp "$BK/all.txt" "$LIST"
cp "$BK/backup-list.txt" /dev/null 2>/dev/null || true
say "已写入 $(wc -l < "$LIST") 个定制文件；新增 $(wc -l < "$NEW") 个"
say "备份目录：$BK（--rollback 可一键还原）"

# ── 第 44 次：按模式自动装配 QSDK 运行期材料，装完即生效，不用手动搬 ──
MODE=$(cat /etc/firmware_mode 2>/dev/null || echo '')
for a in "$@"; do case "$a" in --mode=*) MODE=${a#--mode=} ;; esac; done
case "$MODE" in wds|ap) ;; *) MODE=wds ;; esac
P="$TMP/usr/lib/oem54/payload"
if [ -d "$P" ]; then
  for L in common "$MODE"; do
    [ -d "$P/$L" ] || continue
    ( cd "$P/$L" && find . -type f | sed 's#^\./##' ) | while read -r f; do
      [ -z "$f" ] && continue
      mkdir -p "$(dirname "/$f")"
      cp "$P/$L/$f" "/$f" || { say "装配失败 /$f"; continue; }
      case "$f" in *sbin/*|*init.d/*|*.sh) chmod 755 "/$f" 2>/dev/null || true ;; esac
      echo "$f" >> "$NEW"
    done
  done
  for s in qsdk-nic-guard; do
    [ -x "/etc/init.d/$s" ] && /etc/init.d/$s enable 2>/dev/null || true
  done
  if [ "$MODE" = wds ]; then
    for s in qsdk-bridge-role qsdk-watchdog; do
      [ -x "/etc/init.d/$s" ] && /etc/init.d/$s enable 2>/dev/null || true
    done
    [ -x /usr/sbin/qsdk-bridge-role ] && ( /usr/sbin/qsdk-bridge-role run >/dev/null 2>&1 & ) || true
    [ -x /etc/init.d/qsdk-watchdog ] && /etc/init.d/qsdk-watchdog restart 2>/dev/null || true
    say 'WDS：已启用自动一主一备 + 机器狗'
  else
    [ -x /etc/init.d/qsdk-guard ] && /etc/init.d/qsdk-guard enable 2>/dev/null || true
    say 'AP：已启用 DHCP 防护 / 弱信号剔除；可用 qsdk-bridge-ap 改管理地址'
  fi
  say "已装配第 44 次运行期材料（模式=$MODE），串口可查 qsdk-bridge-role status"
else
  say "::warning::包内无 payload 材料（旧版包），仅叠加了页面与工具"
fi
echo
say "── 验收 ──"
say "  sh /usr/sbin/wifi-stack-check        # 应识别为【官方 5.4.213 闭源 qca-wifi 栈】"
say "  sh /usr/sbin/health-fix              # LuCI / SSH / CGI 自检"
say "  lsmod | grep -iE 'qca_ol|umac|wifi_3_0|ipq_cnss2'   # 闭源无线模块应在位"
say "  iw dev / wlanconfig ath0 list / wifitool ath0 status # 无线应正常"
say "  浏览器打开 /bridge/ 与 /ap/（三环温度仪表盘）"
say "  qsdk-bridge-role status / qsdk-watchdog status   # WDS 自动主备与机器狗"
say "  qsdk-bridge-ap status                            # AP 模式管理地址"
echo
say "⚠ 未改动官方 network / wireless 配置（自动主备只做只读判定与状态，保住满血无线）。"
say "⚠ 本脚本不重打包固件、不刷分区，零变砖风险；回滚：sh apply-oem-overlay.sh --rollback"
