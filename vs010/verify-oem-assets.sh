#!/bin/sh
# verify-oem-assets.sh —— VS010 无线真值三方交叉核对（第 27 次校准）
#
# 纯只读：不写任何文件、不改配置、不联网、不依赖 jq/python。
# 用途：上传/合并整包后、编译前，先在串口或 CI 里跑一遍，确认
#   ① 两个 128KB 原厂 BDF 没被换/没被截断（MD5 硬校验）
#   ② 实物 fdt 反编译稿里的 board_id / bdf-addr / caldb 仍是那组真值
#   ③ 本仓 QSDK 改写版 DTS 仍用【3 元组】写法，没被误改成 NWRT 的 6 元组
#      —— 三套 DTS 语法对应三套驱动，改错反而炸无线。
#
# 用法：
#   sh vs010/verify-oem-assets.sh            # 人读报告
#   sh vs010/verify-oem-assets.sh --json     # CI 用的 JSON
#   sh vs010/verify-oem-assets.sh --root /path/to/repo
#
# 退出码：0=全部通过；1=有硬错误（BDF 损坏 / 真值失配 / 语法被改坏）

PATH=/usr/sbin:/usr/bin:/sbin:/bin:$PATH
export PATH

ROOT=''
JSON=0
while [ $# -gt 0 ]; do
    case "$1" in
        --json) JSON=1 ;;
        --root) shift; ROOT="${1:-}" ;;
        --root=*) ROOT=${1#--root=} ;;
    esac
    shift
done
[ -n "$ROOT" ] || ROOT=$(cd "$(dirname "$0")/.." && pwd)

D="$ROOT/vs010"
FDT="$D/ipq5018-vs010-nwrt-dump.dts"
DTS="$D/ipq5018-vs010.dts"
B2="$D/bdf/board-cucc_vs010.ipq5018"
B5="$D/bdf/board-cucc_vs010.qcn6122"
MD5_2G='c7d89771464322ea39ca290249295af9'
MD5_5G='0aadbd42dc960aefdffe09177dd275b9'

md5of() { [ -r "$1" ] && md5sum "$1" 2>/dev/null | awk '{print $1}' || echo 'MISSING'; }
szof()  { [ -r "$1" ] && wc -c < "$1" 2>/dev/null | tr -d ' ' || echo 0; }
has()   { grep -qE "$2" "$1" 2>/dev/null; }

ERR=0
add() { # add <key> <ok=0/1> <detail>
    eval "K_$1=$2"
    eval "D_$1=\$3"
    [ "$2" = '0' ] && ERR=1
}

# ── ① BDF 原厂字节 ──
m2=$(md5of "$B2"); s2=$(szof "$B2")
m5=$(md5of "$B5"); s5=$(szof "$B5")
[ "$m2" = "$MD5_2G" ] && [ "$s2" = '131072' ] && ok2=1 || ok2=0
[ "$m5" = "$MD5_5G" ] && [ "$s5" = '131072' ] && ok5=1 || ok5=0
add bdf_2g "$ok2" "2.4G BDF: ${s2}B md5=${m2}（期望 131072B / ${MD5_2G}）"
add bdf_5g "$ok5" "5G   BDF: ${s5}B md5=${m5}（期望 131072B / ${MD5_5G}）"

# ── ② 实物 fdt 反编译稿真值 ──
f_ok=1
[ -r "$FDT" ] || f_ok=0
for pat in 'qcom,board_id = <0x60>' 'qcom,board_id = <0x10>' \
           'qcom,bdf-addr = <0x00 0x00 0x4d300000' \
           'qcom,bdf-addr = <0x00 0x00 0x4c400000' \
           'qcom,caldb-size = <0x00>'; do
    has "$FDT" "$pat" || f_ok=0
done
add fdt_truth "$f_ok" "实物 fdt 真值（board_id 0x10/0x60、bdf 0x4c400000/0x4d300000、caldb-size 0）"

# ── ③ 本仓 QSDK DTS 写法 ──
d_ok=1
[ -r "$DTS" ] || d_ok=0
for pat in 'qcom,board_id = <0x10>' 'qcom,board_id = <0x60>' \
           'qcom,bdf-addr = <0x4c400000 0x4c400000 0x4c400000>' \
           'qcom,bdf-addr = <0x4d300000 0x4d300000 0x4d300000>' \
           'qcom,caldb-size = <0>'; do
    has "$DTS" "$pat" || d_ok=0
done
# 防「好心改坏」：NWRT 闭源 cnss2 的 6 元组 / mem-region 绝不能进 QSDK 改写版
if has "$DTS" 'qcom,bdf-addr = <0x00 0x00 0x4[cCdD]' || has "$DTS" 'mem-region ='; then
    d_ok=0
    BAD_SYNTAX=1
else
    BAD_SYNTAX=0
fi
# 防复位键：VS010 实物只有 WPS 键 GPIO34
if has "$DTS" 'KEY_RESTART|label[[:space:]]*=[[:space:]]*"reset"'; then
    d_ok=0
    BAD_KEY=1
else
    BAD_KEY=0
fi
add dts_qsdk "$d_ok" "QSDK 21.02 写法（3 元组 / 无 mem-region / 无 KEY_RESTART）"

# ── ④ 第 27 次：BDF 双路径 + caldata 永久锁（读注入脚本，不执行）──
DIY="$ROOT/diy-part2.vs010.sh"
b_ok=1
[ -r "$DIY" ] || b_ok=0
for pat in 'files/lib/firmware/IPQ5018' 'bdwlan.b10' 'bdwlan.b60' \
           'VS010_CALDATA 已永久禁用'; do
    has "$DIY" "$pat" || b_ok=0
done
add live_fix "$b_ok" "BDF cnss2 双路径安装 + caldata 永久硬锁（第 27 次实证）"

# ── 输出 ──
if [ "$JSON" = '1' ]; then
    printf '{"ok":%d,"bdf_2g":%d,"bdf_5g":%d,"fdt_truth":%d,"dts_qsdk":%d,"live_fix":%d,"bad_syntax":%d,"bad_key":%d,"root":"%s"}\n' \
      "$([ "$ERR" = '0' ] && echo 1 || echo 0)" "$K_bdf_2g" "$K_bdf_5g" "$K_fdt_truth" "$K_dts_qsdk" "$K_live_fix" \
      "$BAD_SYNTAX" "$BAD_KEY" "$ROOT"
    exit "$ERR"
fi

echo '═══ VS010 无线真值三方核对 · verify-oem-assets ═══'
echo "仓库根: $ROOT"
echo
[ "$K_bdf_2g" = '1' ] && s='✓' || s='✗'; echo "  $s $D_bdf_2g"
[ "$K_bdf_5g" = '1' ] && s='✓' || s='✗'; echo "  $s $D_bdf_5g"
[ "$K_fdt_truth" = '1' ] && s='✓' || s='✗'; echo "  $s $D_fdt_truth"
[ "$K_dts_qsdk" = '1' ] && s='✓' || s='✗'; echo "  $s $D_dts_qsdk"
[ "$K_live_fix" = '1' ] && s='✓' || s='✗'; echo "  $s $D_live_fix"
echo
echo '  三套 DTS 语法（别混用）：'
echo '    QSDK 21.02 kkstone（本仓）  → bdf-addr 3 元组  ← 当前正确'
echo '    NWRT 实物 闭源 cnss2        → bdf-addr 6 元组 + mem-region'
echo '    OpenWrt 25.12 qualcommax    → bdf-addr 单值'
if [ "$BAD_SYNTAX" = '1' ]; then
    echo '  ✗ 检测到 6 元组 / mem-region 混入 QSDK 改写版：会炸无线，请改回 3 元组'
fi
if [ "$BAD_KEY" = '1' ]; then
    echo '  ✗ 检测到 KEY_RESTART / reset 键：VS010 实物只有 WPS 键 GPIO34，会开机进 failsafe'
fi
echo
if [ "$ERR" = '0' ]; then
    echo '  ✓ 全部通过：原厂 BDF 完好，数值与实物 fdt 一致，DTS 写法匹配底座驱动，BDF 双路径与 caldata 硬锁就位。'
    echo '    ⚠ 注意：这只证明【板级资产与注入脚本对】，不等于【无线已能起来】。'
    echo '    第 27 次成功态日志实证：好固件是闭源 qca-wifi/cnss2，本仓是开源 ath11k，'
    echo '    两套驱动栈不兼容 —— 这才是 VS010 无线不注册的根因，改数值修不好。'
else
    echo '  ✗ 有硬错误，先修上面标 ✗ 的项再编译。'
fi
echo
echo '  详见 vs010/wifi-truth.conf 的 ROOT_CAUSE / EVIDENCE_LIVE_* 段 / FIRMWARE.md 第三十五节。'
exit "$ERR"
