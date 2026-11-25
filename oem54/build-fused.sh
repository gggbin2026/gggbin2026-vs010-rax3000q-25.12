#!/bin/sh
# ═══════════════════════════════════════════════════════════════════════
# 第 43 次 · 生成「满血融合固件」
#
#   官方 NWRT QSDK12.2 / 5.4.213 整机镜像（内核 + 闭源无线 + NSS 全保留）
#     + 仓库全部定制（管理页 / 三环仪表盘 / WDS / AP / SSH / LuCI /
#                     DHCP 防护 / 弱信号剔除 / 自检工具）
#   → 重新打包成一个可直接刷的 factory.bin
#
# 用法（在仓库根目录）：
#   sh oem54/build-fused.sh --mode=wds --model=VS010
#   sh oem54/build-fused.sh --mode=ap  --model=RAX3000Q
#   sh oem54/build-fused.sh --all            # 四个组合全生成
#
# 前置：仓库里必须有 3000Q-VS010-固件/ 下两个官方 factory.bin；
#       系统需 unsquashfs / mksquashfs（GitHub ubuntu-latest 自带）。
# ═══════════════════════════════════════════════════════════════════════
set -eu
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
FWDIR=3000Q-VS010-固件
VS=$FWDIR/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cucc_vs010-squashfs-nand-factory.bin
RAX=$FWDIR/Nwrt-QSDK12.2-2024-04-16-ipq50xx-ipq50xx_32-cmcc_rax3000qy-squashfs-nand-factory.bin
OUTDIR=${OUTDIR:-fused}
mkdir -p "$OUTDIR"

command -v unsquashfs >/dev/null || { echo '::error::缺 unsquashfs'; exit 1; }
command -v mksquashfs >/dev/null || { echo '::error::缺 mksquashfs'; exit 1; }
python3 -c 'import zlib' || { echo '::error::缺 python3'; exit 1; }

# ── 从 apply-full-config.sh 提取两个内嵌守护（单一数据源）──
extract_heredoc(){
  python3 - "$1" "$2" <<'PY'
import re,sys,pathlib
s=pathlib.Path('oem54/apply-full-config.sh').read_text()
name=sys.argv[1]
m=re.search(r"<<'"+name+r"'\n(.*?)\n"+name+r"\n",s,re.S)
if not m: sys.exit('::error::找不到 '+name)
pathlib.Path(sys.argv[2]).write_text(m.group(1))
PY
}

# ── 生成注入目录 ──
make_inject(){
  MODE=$1; MODEL=$2; TAG=$3; D=/tmp/fused-inject-$MODE-$MODEL
  rm -rf "$D"
  for d in www/bridge www/ap www/cgi-bin usr/sbin usr/lib/bridge usr/lib/oem54 etc/config etc/init.d; do
    mkdir -p "$D/$d"
  done

  # ── 第 44 次 · 从仓库 oem54/payload/ 装配运行期材料 ──────────────
  # 材料就在仓库里，Actions 每次自动生成固件都会一并带上，不用手动补：
  #   common/ 网口守护 + 双栈无线库 + DHCP 工具
  #   wds/    自动一主一备 + 机器狗 + wdsdog 配置
  #   ap/     AP 现场配置工具 + 弱信号剔除配置
  for L in common "$MODE"; do
    [ -d "oem54/payload/$L" ] || { echo "::error::缺 oem54/payload/$L"; exit 1; }
    ( cd "oem54/payload/$L" && tar cf - . ) | ( cd "$D" && tar xf - )
  done
  mkdir -p "$D/usr/lib/oem54/payload"
  ( cd oem54/payload && tar cf - . ) | ( cd "$D/usr/lib/oem54/payload" && tar xf - )
  find "$D/usr/sbin" "$D/etc/init.d" "$D/usr/lib/oem54" -type f -name '*.sh' -exec chmod 755 {} + 2>/dev/null || true
  find "$D/usr/sbin" "$D/etc/init.d" -type f -exec chmod 755 {} + 2>/dev/null || true
  echo "[inject] $MODE/$MODEL → $D" >&2

  # ① 管理页 + CGI（按模式）
  if [ "$MODE" = wds ]; then
    cp files/www/bridge/index.html          "$D/www/bridge/index.html"
    cp files/www/cgi-bin/bridge             "$D/www/cgi-bin/bridge"
  else
    cp files.ap/www/ap/index.html           "$D/www/ap/index.html"
    cp files.ap/www/cgi-bin/apstatus        "$D/www/cgi-bin/apstatus"
    cp files.ap/www/bridge/index.html       "$D/www/bridge/index.html"
    # 第 45 次：简版 /bridge/ 页 fetch 的是 /cgi-bin/bridge，AP 固件以前漏注入
    # 导致该页一直「CGI 未返回数据」。bridge CGI 纯只读，AP 下也安全。
    cp files/www/cgi-bin/bridge             "$D/www/cgi-bin/bridge"
  fi

  # ② 公共只读工具（官方栈用得上、不会覆盖网络配置）
  for f in health-fix luci-fix luci-entry portstat accel-check tty-diag \
           wifi-bdf-check wifi-art-cal wifi-stack-check wifi-heal; do
    [ -f "files/usr/sbin/$f" ] && cp "files/usr/sbin/$f" "$D/usr/sbin/$f"
  done
  [ -f files/usr/lib/bridge/role.sh ] && cp files/usr/lib/bridge/role.sh "$D/usr/lib/bridge/role.sh"

  # ③ 真值表配置（只读）
  for c in art-truth.conf oem-stack-truth.conf; do
    [ -f "files/etc/config/$c" ] && cp "files/etc/config/$c" "$D/etc/config/$c"
  done

  # ④ QSDK 适配版守护：从 apply-full-config.sh 提取
  extract_heredoc GUARD "$D/usr/sbin/qsdk-dhcp-guard"
  extract_heredoc RSSI  "$D/usr/sbin/qsdk-rssi-guard"
  chmod 755 "$D/usr/sbin/qsdk-dhcp-guard" "$D/usr/sbin/qsdk-rssi-guard"

  # ⑤ 独立配置 + init.d（构建期固化，运行时零生成）
  cat > "$D/etc/config/qsdk-guard" <<EOF
config qsdk-guard 'main'
	option mode '$MODE'
	option model '$MODEL'
	option rssi_reject '-90'
	option rssi_kick '-92'
	option wireless_isolated '0'
	option kernel '5.4.213'
	option stack 'qca-wifi-closed'
EOF
  cat > "$D/etc/init.d/qsdk-guard" <<'EOF'
#!/bin/sh /etc/rc.common
# 第 43 次融合固件：DHCP 防护 + AP 弱信号剔除（官方 5.4.213 闭源栈适配）
START=95
STOP=10
start(){
  /usr/sbin/qsdk-dhcp-guard on
  [ "$(uci -q get qsdk-guard.main.mode)" = ap ] && /usr/sbin/qsdk-rssi-guard on || true
  # AP 守护每 30 秒扫一次弱信号终端
  [ "$(uci -q get qsdk-guard.main.mode)" = ap ] && {
    ( while :; do sleep 60; /usr/sbin/qsdk-rssi-guard once; done ) &  # 第50次：60s 轮询，减半唤醒
  }
}
stop(){ /usr/sbin/qsdk-dhcp-guard off; }
restart(){ stop; sleep 1; start; }
EOF
  chmod 755 "$D/etc/init.d/qsdk-guard"

  # ⑥ 首启配置（init.d 而非 uci-defaults：确保 board.d 已生成 network）
  cat > "$D/etc/init.d/oem54-firstboot" <<EOF
#!/bin/sh /etc/rc.common
# 第 43 次融合固件 · 首次启动一次性业务配置（幂等，可回滚）
START=99
STAMP=/etc/oem54-firstboot.done
BK=/etc/oem54-backup/firstboot
start(){
  # ★ 第 46 次：STAMP 存【构建号】而不是日期。以前用 date，
  #   「保留配置」升级时旧 overlay 里的 done 会挡住新固件的首启配置 ——
  #   正是「刷了新版但配置一点没动」的第二个真因。
  BID=\$(cat /etc/firmware_build 2>/dev/null || echo unknown)
  [ "\$(cat "\$STAMP" 2>/dev/null)" = "\$BID" ] && return 0
  mkdir -p "\$BK"
  : > "\$BK/uci-rollback.sh"; echo '#!/bin/sh' >> "\$BK/uci-rollback.sh"
  save(){ sec=\$1; opt=\$2; val=\$3
    old=\$(uci -q get "\$sec.\$opt" 2>/dev/null || echo '__UNSET__')
    [ "\$old" = "\$val" ] && return 0
    [ "\$old" = '__UNSET__' ] && echo "uci -q delete \$sec.\$opt" >> "\$BK/uci-rollback.sh" \\
                            || echo "uci set \$sec.\$opt='\$old'" >> "\$BK/uci-rollback.sh"
    uci set "\$sec.\$opt=\$val"
  }
  # 无线：只清 disabled（含匿名 @wifi-iface[N]），绝不重建 radio/iface
  uci show wireless 2>/dev/null \\
    | sed -n 's/^wireless\\.\\(.*\\)=wifi-\\(device\\|iface\\)\$/\\1/p' \\
    | while read -r s; do [ -n "\$s" ] && uci -q set wireless."\$s".disabled=0; done
EOF
  if [ "$MODE" = wds ]; then
    cat >> "$D/etc/init.d/oem54-firstboot" <<'EOF'
  # WDS 网桥：第 46 次纠错 —— 官方是【静态 192.168.1.1】，旧版写 lan.proto=dhcp
  # 在实机根本没生效、且上级无 DHCP 时会丢掉管理地址。这里只开 STP，
  # IP / DHCP / 密码 / SSID / 防火墙统一交给 qsdk-firstboot-config（见尾部）。
  if uci -q get network.lan >/dev/null 2>&1; then
    save network lan.type bridge
    save network lan.stp 1
  else
    logger -t oem54 'network.lan 尚未生成，跳过网桥增量（避免断网）'
  fi
  # 第 44 次：WDS 专属服务开机自动启用（AP 固件里根本不写这两行）
  /etc/init.d/qsdk-bridge-role enable 2>/dev/null || true
  /etc/init.d/qsdk-watchdog enable 2>/dev/null || true
EOF
  else
    cat >> "$D/etc/init.d/oem54-firstboot" <<'EOF'
  # AP 模式：IP / DHCP 由 qsdk-firstboot-config 按约定设 .240（uci 增量，不重建段）
  logger -t oem54 'AP 模式：业务配置统一交给 qsdk-firstboot-config'
EOF
  fi
  cat >> "$D/etc/init.d/oem54-firstboot" <<'EOF'
  uci commit
  # 服务：官方 dropbear/uhttpd 配置本就正确，只 ensure enable
  /etc/init.d/dropbear enable 2>/dev/null || true
  /etc/init.d/uhttpd enable 2>/dev/null || true
  /etc/init.d/qsdk-guard enable 2>/dev/null || true
  /etc/init.d/ntp-sync enable 2>/dev/null || true   # 【第53次】NTP 每 5 分钟同步
  # 第 44 次：网口守护两模式都启用；WDS 专属的主备/机器狗已在上面分支里启用
  /etc/init.d/qsdk-nic-guard enable 2>/dev/null || true
  [ -x /usr/sbin/luci-entry ] && sh /usr/sbin/luci-entry 2>/dev/null || true

  # ★ 第 46 次：把官方残留的业务配置改成约定状态（刷完即成型，用户不用动）
  #   密码 / SSID / 防火墙 / 多余服务 / IPv6 / 管理 IP / 本机 DHCP，全部 uci 增量。
  #   参数在 /etc/qsdk-firstboot.conf，--rollback 可一键还原。
  if [ -x /usr/sbin/qsdk-firstboot-config ]; then
    # board.d 可能还没生成 wireless；等 6 秒，缺了再后台补跑一次
    sleep 6
    /usr/sbin/qsdk-firstboot-config >/tmp/qsdk-firstboot-config.log 2>&1 || true
    if ! uci -q show wireless 2>/dev/null | grep -q '\.ssid='; then
      ( sleep 30; /usr/sbin/qsdk-firstboot-config --force >>/tmp/qsdk-firstboot-config.log 2>&1 ) &
    fi
  fi

  echo 'uci commit' >> "$BK/uci-rollback.sh"
  chmod 755 "$BK/uci-rollback.sh"
  printf '%s\n' "$BID" > "$STAMP"
  logger -t oem54 "融合固件首启配置完成 mode=MODE_PLACEHOLDER model=MODEL_PLACEHOLDER build=$BID（第46次业务配置已应用）"
  # cnss2/校准需要时间，后台补一次 wifi up
  ( sleep 35; wifi up 2>/dev/null || true ) &
}
EOF
  sed -i "s/MODE_PLACEHOLDER/$MODE/g; s/MODEL_PLACEHOLDER/$MODEL/g" "$D/etc/init.d/oem54-firstboot"
  chmod 755 "$D/etc/init.d/oem54-firstboot"

  # ⑦ 模式标记 + 构建号（第 45 次：解决「43/44/45 固件同名、刷了旧文件不知道」）
  #    /etc/firmware_build 是刷完一眼判版本的依据；页面页脚与 CGI 也显示它。
  printf '%s\n' "$MODE" > "$D/etc/firmware_mode"
  printf 'r47-%s-%s-%s\n' "$(date +%Y%m%d)" "$TAG" "$MODE" > "$D/etc/firmware_build"
  cp oem54/apply-full-config.sh oem54/apply-oem-overlay.sh oem54/oem-overlay.tar.gz \
     oem54/README_无线修复.md oem54/README_怎么处理最好.md \
     oem54/OEM_5.4.213_资产清单.md "$D/usr/lib/oem54/" 2>/dev/null || true
  cp oem54/build-fused.py oem54/build-fused.sh oem54/fdt-rate-feasibility.py \
     "$D/usr/lib/oem54/" 2>/dev/null || true

  # ⑧ 安全网：注入树里绝不能出现会覆盖官方配置的路径
  for k in etc/config/network etc/config/wireless etc/config/dhcp etc/config/dropbear \
           etc/config/luci etc/config/uhttpd etc/config/firewall etc/rc.local \
           etc/uci-defaults/ lib/modules/ lib/firmware/ etc/config/system; do
    if [ -e "$D/$k" ]; then echo "::error::注入树含危险路径 $k"; exit 1; fi
  done
  echo "[inject] ✓ $(find "$D" -type f | wc -l) 个文件，安全网通过" >&2
  echo "$D"
}

build_one(){
  MODE=$1; MODEL=$2; SRC=$3; TAG=$4
  [ -s "$SRC" ] || { echo "::error::缺官方固件 $SRC"; exit 1; }
  D=$(make_inject "$MODE" "$MODEL" "$TAG")
  DATE=$(date +%Y%m%d)
  # 第 45/46 次：文件名带版本戳，避免下载目录残留旧文件刷错。
  OUT="$OUTDIR/Nwrt-FUSED-5.4.213-$DATE-r47-$TAG-$MODE-squashfs-nand-factory.bin"
  echo "[build] $MODEL/$MODE → $OUT"
  python3 oem54/build-fused.py "$SRC" "$D" "$OUT" "--mode=$MODE" "--model=$MODEL"
  sha256sum "$OUT" | tee "$OUT.sha256"
  echo "$OUT"
}

case "${1:-}" in
  --all)
    build_one wds VS010    "$VS"  cucc_vs010
    build_one ap  VS010    "$VS"  cucc_vs010
    build_one wds RAX3000Q "$RAX" cmcc_rax3000qy
    build_one ap  RAX3000Q "$RAX" cmcc_rax3000qy
    ;;
  --mode=* )
    M=${1#--mode=}; MODEL=${2#--model=}
    case "$MODEL" in VS010) S=$VS; T=cucc_vs010;; RAX3000Q) S=$RAX; T=cmcc_rax3000qy;; *) echo '::error::model'; exit 1;; esac
    build_one "$M" "$MODEL" "$S" "$T"
    ;;
  *) echo '用法: sh oem54/build-fused.sh --all  或  --mode=wds --model=VS010'; exit 1 ;;
esac
echo
echo "════════ 生成完毕 ════════"
ls -lh "$OUTDIR"/*.bin 2>/dev/null || true
