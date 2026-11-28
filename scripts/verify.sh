#!/bin/sh
# 本地/Actions 自检。分级：真阻断项 FAIL 即停；文档/文案类降为非阻断警告。
set -u
W=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
cd "$W"
BLOCK=0; WARN=0
ok(){   printf '  OK   %s\n' "$1"; }
blk(){  printf '  FAIL %s\n' "$1" >&2; BLOCK=$((BLOCK+1)); }
wrn(){  printf '  WARN %s\n' "$1"; WARN=$((WARN+1)); }
has(){ [ -f "$1" ] && ok "$2" || blk "缺文件: $1"; }

echo "=== [1/9] 顶层文件 / 单包回归护栏 ==="
for f in README.md baseline.env feeds.conf.default .gitignore files.manifest \
         .github/workflows/build.yml config/common.seed config/gen-config.sh \
         scripts/board-inject.sh scripts/prepare.sh scripts/resolve-baseline.sh \
         scripts/health-fix scripts/wifi-fullspeed scripts/oem-stack-check \
         scripts/luacheck.py files/usr/sbin/nwrt-apply-mode files/usr/sbin/nwrt-tick \
         files/etc/nwrt/tick.conf files/etc/init.d/nwrt-tick \
         files/usr/lib/lua/luci/controller/admin/nwrt.lua \
         files/usr/lib/lua/luci/view/admin_nwrt/switch.htm; do
  has "$f" "$f"
done
for old in .github/workflows/build-wds.yml .github/workflows/build-ap.yml; do
  [ -f "$old" ] && blk "旧按模式拆包 workflow 还在: $old" || ok "已移除 $old"
done
for d in files.wds files.ap; do
  [ -d "$d" ] && blk "按模式拆包目录还在: $d（单包回归）" || ok "无 $d（单包双模式）"
done
grep -q 'default_mode' .github/workflows/build.yml && ok "workflow 有 default_mode 输入" || blk "缺 default_mode"
grep -q 'Nwrt-WDS-AP-UBNT' .github/workflows/build.yml && grep -q -- '-dual-' .github/workflows/build.yml && ok "产物名是单包 dual" || blk "产物名不是单包 dual"
grep -q '25:nwrt-tick' .github/workflows/build.yml && ok "开机链接含 nwrt-tick" || blk "缺 nwrt-tick 自启链接"

echo "=== [2/9] shell / python / JS 语法 + Lua 词法 ==="
for f in $(find . -type f \( -name '*.sh' -o -path './files/etc/init.d/*' \
            -o -path './files/usr/sbin/*' -o -path './files/www/cgi-bin/*' \) 2>/dev/null); do
  sh -n "$f" 2>/dev/null || blk "shell 语法错误: $f"
done
for f in $(find scripts config -type f -name '*.py' 2>/dev/null); do
  python3 -m py_compile "$f" 2>/dev/null || blk "python 语法错误: $f"
done
python3 scripts/luacheck.py files/usr/lib/lua/luci/controller/admin/nwrt.lua >/dev/null 2>&1 \
  && ok "Lua controller 词法" || blk "Lua controller 词法不通过（后台会 500）"
command -v node >/dev/null 2>&1 && {
  node --check files/www/app.js 2>/dev/null && ok "app.js 语法" || blk "app.js 语法"
  node --check files/www/vs010-ubnt-skin.js 2>/dev/null && ok "skin.js 语法" || blk "skin.js 语法"
} || wrn "node 不可用，跳过 JS 检查"
ok "shell / python 语法"

echo "=== [3/9] files.manifest 逐文件存在 + 无遗漏 ==="
while IFS= read -r p; do
  case "$p" in ''|'#'*) continue ;; esac
  [ -f "files/$p" ] || blk "manifest 指向不存在: files/$p"
done < files.manifest
ACTUAL=$(find files -type f | sed 's|^files/||' | sort)
MF=$(sort files.manifest)
[ "$ACTUAL" = "$MF" ] && ok "manifest 与 files/ 逐一对齐" || blk "manifest 与 files/ 不一致（有文件不会进固件）"
for p in www/vs010-ubnt.css www/vs010-ubnt-skin.js usr/sbin/health-fix \
         usr/sbin/wifi-fullspeed usr/sbin/oem-stack-check usr/sbin/nwrt-apply-mode \
         usr/sbin/nwrt-tick etc/nwrt/tick.conf etc/init.d/nwrt-tick \
         usr/lib/lua/luci/controller/admin/nwrt.lua usr/lib/lua/luci/view/admin_nwrt/switch.htm; do
  grep -qxF "$p" files.manifest && ok "manifest 已注册 $p" || blk "manifest 未注册 $p（编译后固件里不会有）"
done

echo "=== [4/9] LuCI 防 427 + 模式切换写入鉴权 ==="
grep -q "config core 'main'" files/etc/config/luci && ok "named core main" || blk "缺 named config core 'main'"
grep -q 'mediaurlbase.*bootstrap' files/etc/config/luci && ok "mediaurlbase=bootstrap" || blk "mediaurlbase 没指向 bootstrap"
grep -q 'luci-theme-argon' files/etc/config/luci && blk "luci 配置里出现幽灵 argon 主题" || ok "无幽灵主题"
# 🔴 零裸 CGI 写入端点：状态 CGI 只能读
FOUND=0
for c in files/www/cgi-bin/*; do
  [ -f "$c" ] || continue
  grep -v '^[[:space:]]*#' "$c" | grep -qiE 'uci (set|commit)|nwrt-apply-mode (wds|ap)|> */etc/nwrt/mode' && FOUND=1
done
if [ "$FOUND" = 1 ]; then
  blk "www/cgi-bin 里出现写入动作（必须只在 LuCI admin 树 / 串口）"
else
  ok "CGI 全只读，无裸写入端点"
fi
grep -q 'entry({"admin", "nwrt"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "切换端点在 admin 树（sysauth）" || blk "切换端点不在 admin 树"
grep -q 'mode == "wds" or mode == "ap"' files/usr/lib/lua/luci/controller/admin/nwrt.lua && ok "mode 白名单校验" || blk "缺 mode 白名单"
grep -q 'case "$ACT" in' files/usr/sbin/nwrt-apply-mode && grep -q 'boot) MODE=' files/usr/sbin/nwrt-apply-mode && ok "apply-mode 固定枚举" || blk "apply-mode 缺固定枚举"
grep -q 'wifi reload' files/usr/sbin/nwrt-apply-mode && \
  ! (grep -v '^[[:space:]]*#' files/usr/sbin/nwrt-apply-mode | grep -q 'wifi down') && \
  ok "一次 reload / 无射频下线" || blk "apply-mode 违反不做射频下线"

echo "=== [5/9] 轻量巡检：单常驻、dryrun 默认、红线 ==="
N=$(grep -rl 'USE_PROCD=1' files/etc/init.d/ 2>/dev/null | wc -l | tr -d ' ')
[ "$N" = 1 ] && ok "procd 常驻只有 1 个（nwrt-tick）" || blk "procd 常驻 $N 个（应为 1）"
grep -q '^DRYRUN=1' files/etc/nwrt/tick.conf && ok "出厂 dryrun=1（只记录不动作）" || blk "DRYRUN 不是 1"
grep -q 'RELOAD_COOLDOWN' files/usr/sbin/nwrt-tick && grep -q 'wifi reload' files/usr/sbin/nwrt-tick && ok "限频 reload 冷却" || blk "缺 reload 冷却"
! (grep -v '^[[:space:]]*#' files/usr/sbin/nwrt-tick | grep -qE 'reboot|wifi down') && \
  ok "无重启 / 无射频下线" || blk "tick 里有重启或射频下线动作"
grep -q '/etc/nwrt/ipaddr' files/etc/init.d/bridge-netfix && ok "WDS 客户端 IP 可覆盖" || blk "缺 IP 覆盖机制（两台桥接会 .241 冲突）"

echo "=== [6/9] 插件精简 ==="
N=$(grep -cE '^(OPTIONAL:)?CONFIG_PACKAGE_luci-app-' config/common.seed 2>/dev/null || true)
[ "${N:-0}" -le 1 ] && ok "luci-app 数量 ${N:-0}（含 OPTIONAL 行）" || blk "seed 里 luci-app-* 出现 ${N:-0} 个"
grep -q 'dropbear=y' config/common.seed && ok "SSH 在" || blk "SSH 丢失"
grep -q '^# CONFIG_PACKAGE_firewall4 is not set' config/common.seed && ok "防火墙显式关" || blk "防火墙未显式关"

echo "=== [7/9] 板级 ==="
for d in board/ipq5018-vs010.6.12.dts board/ipq5018-rax3000q.6.12.dts; do
  [ -f "$d" ] || { blk "缺 $d"; continue; }
  o=$(tr -cd '{' < "$d" | wc -c); c=$(tr -cd '}' < "$d" | wc -c)
  [ "$o" = "$c" ] && ok "$(basename "$d") 花括号 $o/$c" || blk "$(basename "$d") 花括号 $o/$c 不配对"
  DIS=$(grep -c 'status = "disabled"' "$d" 2>/dev/null || true)
  [ "${DIS:-0}" -eq 0 ] && ok "$(basename "$d") 无残留 disabled" || blk "$(basename "$d") 仍有 ${DIS:-0} 处 disabled"
done
grep -q 'Device/unicom_vs010' board/ipq50xx.device.inc && ok "VS010 Device" || blk "缺 VS010 Device"
grep -q 'Device/cmcc_rax3000q' board/ipq50xx.device.inc && ok "RAX3000Q Device" || blk "缺 RAX3000Q Device"

echo "=== [8/9] 界面：三页 + 六入口 + mode 提示 + 命令兜底 ==="
for p in www/index.html www/ubnt/index.html www/bridge/index.html www/ap/index.html \
         www/vs010-ubnt.css www/vs010-ubnt-skin.js www/app.js \
         www/cgi-bin/state www/cgi-bin/bridge www/cgi-bin/apstatus; do
  has "files/$p" "$p"
done
grep -q 'u-jump' files/www/vs010-ubnt-skin.js && ok "UBNT 全互访注入器" || blk "UBNT 注入器缺失"
grep -q 'apstatus|state' files/www/vs010-ubnt-skin.js && ok "注入器接本仓 state CGI" || wrn "注入器未识别 state"
grep -q '/cgi-bin/luci/admin/nwrt' files/www/vs010-ubnt-skin.js && ok "六入口指向模式切换页" || blk "六入口仍指向旧 vs010_setup"
! grep -q 'vs010_setup' files/www/vs010-ubnt-skin.js && ok "无旧仓路径残留" || blk "残留 vs010_setup 路径"
grep -q 'data-page' files/www/app.js && grep -q 'mismatch' files/www/app.js && ok "非当前模式提示条（不强制跳）" || blk "缺 mode 提示条"
grep -q 'nwrt-apply-mode' files/www/app.js && ok "TTYD/SSH 命令兜底" || blk "缺命令兜底"
grep -q 'nwrt-tick\|TICK' files/www/app.js && ok "巡检卡片" || blk "缺巡检卡片"

echo "=== [9/9] 非阻断文档 / 参考 ==="
for f in FIRMWARE.md FLASHING.md MIGRATION.md 上传说明.txt 修复总览.md \
         docs/模式切换与巡检.md docs/源仓库取证.md docs/板级真值.md \
         docs/主题与UBNT界面.md docs/ART与无线校准.md docs/DHCP与SSH防护.md \
         reference/xiangye277/build.yml reference/old54/ipq5018-rax3000q.dts; do
  [ -f "$f" ] || wrn "可选文档缺失: $f"
done

echo "================================================"
if [ "$BLOCK" -gt 0 ]; then
  echo "RESULT: FAIL ($BLOCK 项阻断, $WARN 项非阻断警告)"
  exit 1
fi
echo "RESULT: PASS ($WARN 项非阻断警告)"
