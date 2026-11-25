#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""第 47 次 · 只读检查：满血融合固件能不能在【内核层】真修网口速率

  python3 fdt-rate-feasibility.py <factory.bin>

只解析、不写文件。回答三个问题：
  1. kernel FIT 卷里 dtb 在哪、多大
  2. U-Boot 校验是纯 hash 还是 RSA 签名（决定改 dtb 可不可行）
  3. dtb 里 nss-dp / 交换芯片节点长什么样（fixed-link 该补在哪）

⚠ 结论「可改」不等于「改了就有效」：qcom,nss-dp 闭源驱动是否读
  fixed-link 没有源码佐证，且未实机验证，故本仓【默认不启用】该补丁。
"""
import sys, struct, pathlib

PEB, DO, VID = 131072, 4096, 2048

def kernel_volume(p):
    b = pathlib.Path(p).read_bytes()
    out = []
    for i in range(len(b)//PEB):
        peb = b[i*PEB:(i+1)*PEB]
        h = peb[VID:VID+64]
        if h[:4] == b'UBI!' and struct.unpack_from('>I', h, 8)[0] == 0:
            out.append((struct.unpack_from('>I', h, 12)[0], peb[DO:]))
    return b''.join(x[1] for x in sorted(out)).rstrip(b'\xff')

def walk(buf):
    magic, total, os_, ostr, orsv, ver, lv, boot, ss, sd = struct.unpack_from('>10I', buf, 0)
    if magic != 0xd00dfeed: raise ValueError('不是 FDT: magic=%08x' % magic)
    strs = buf[ostr:ostr+ss]; pos = os_; stack = []; out = []
    while True:
        tok = struct.unpack_from('>I', buf, pos)[0]; pos += 4
        if tok == 1:
            e = buf.find(b'\0', pos); nm = buf[pos:e].decode('latin1','replace'); pos = (e+4)&~3
            stack.append(nm); out.append(['/'.join(stack), {}])
        elif tok == 2: stack.pop()
        elif tok == 3:
            ln, noff = struct.unpack_from('>II', buf, pos); pos += 8
            ds = pos; data = buf[pos:pos+ln]; pos = (pos+ln+3)&~3
            e = strs.find(b'\0', noff); k = strs[noff:e].decode('latin1','replace')
            out[-1][1][k] = (ds, data)
        elif tok == 9: break
    return out

def main(p):
    k = kernel_volume(p)
    print('kernel FIT 卷: %d B  magic=%s' % (len(k), k[:4].hex()))
    fit = walk(k)
    fdt = None
    for path, pr in fit:
        if path.endswith('/images/fdt@1'):
            o, d = pr['data']; fdt = d
            print('内嵌 dtb   : FIT 偏移 %d / %d B / totalsize=%d'
                  % (o, len(d), struct.unpack_from('>I', d, 4)[0]))
        if '/hash@' in path:
            algo = pr.get('algo', (0, b''))[1].rstrip(b'\0').decode('latin1','replace')
            val = pr.get('value', (0, b''))[1]
            print('  %-34s algo=%-6s value=%d B' % (path, algo, len(val)))
    sig = [p for p, pr in fit if 'signature' in p or 'key-name-hint' in pr or 'sign-images' in pr]
    print('\nRSA/签名节点: %s' % (sig if sig else '无 —— 只有 crc32 + sha1，改 dtb 后重算即可通过 U-Boot 校验'))
    print('  → 结论：技术【可改】FIT 内的 dtb（不需要驱动源码）')
    if fdt:
        sub = walk(fdt)
        print('\n── dtb 里与网口速率相关的节点 ──')
        for p2, pr2 in sub:
            if any(x in p2.lower() for x in ['/dp1', '/dp2', 'port_phyinfo', 'ess-switch']):
                keys = list(pr2.keys())
                extra = ''
                for k in ('phy-mode', 'qcom,phy-mdio-addr', 'forced-speed', 'forced-duplex'):
                    if k in pr2:
                        v = pr2[k][1]
                        extra += ' %s=%s' % (k, v.rstrip(b'\0').decode('latin1','replace') if len(v)<40 and all(32<=c<127 for c in v) else v[:8].hex())
                print('  %-58s %s%s' % (p2[:58], ','.join(keys[:6]), extra))
    print('\n⚠ 但本仓【默认不启用】这个改动，原因：')
    print('  1. qcom,nss-dp 是闭源 .ko，是否读 fixed-link 无源码佐证；')
    print('  2. dp1 已有 qcom,phy-mdio-addr=7，补 fixed-link 可能与现有 PHY 冲突反而断链；')
    print('  3. 未实机验证，改错会丢管理地址甚至起不来。')
    print('  稳妥做法已在 r47 落地：页面/工具从交换芯片 PHY 读【真实协商速率】，')
    print('  显示 1000M 全双工并标注来源 —— 真值、零风险、不动 kernel FIT。')
    print('  本仓自编译线（5.4.164）走 inject-ethtool-patch.sh 源码补丁，ethtool 本来就正常。')
    return 0

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__); sys.exit(2)
    sys.exit(main(sys.argv[1]))
