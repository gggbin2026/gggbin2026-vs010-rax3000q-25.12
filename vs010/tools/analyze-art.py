#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
analyze-art.py —— 分析用户备份的 0:ART 分区（离线、只读、不猜魔数）

我能从 ART 里看出什么：
  · 分区是不是完整的（1 MB / 128 KB / 是否全 FF 空片）
  · MAC 地址在哪个偏移（VS010 常见 ART+0 / +6 / +0x1000 附近）
  · 非零块的分布 → 判断 2.4G / 5G pre-cal 切片大概落在哪
  · 候选偏移（0x1000 / 0x26800 / 0x40000 …）处的 0x20000 窗口是否有效
  · 有没有 ASCII 字符串 / 重复块（判断是不是被擦过或只是占位）

我【不能】从 ART 里看出什么（这三项在 fdt/cmdline 里，不在 ART）：
  · qcom,board_id（0x10 还是 0x24）
  · qcom,bdf-addr（cnss2 从哪个 DDR 地址取 BDF）
  · 驱动是 cnss2 还是主线 ath11k、U-Boot 传了什么 cnss2.bdf_*

用法：
    python3 analyze-art.py ART.bin
    python3 analyze-art.py ART.bin --json

不写任何文件，不改 ART。
"""
import hashlib
import json
import os
import struct
import sys

# 同平台常见候选（经验值，不是结论）。真正用哪个由本机实测 / dmesg 决定。
CANDIDATES = [0x0, 0x1000, 0x20000, 0x26800, 0x40000, 0x50000, 0x60000, 0x80000]
SLICE = 0x20000  # 128 KB，ath11k caldata 常见长度


def nz_ratio(b):
    if not b:
        return 0.0
    return round(sum(1 for x in b if x != 0 and x != 0xFF) / len(b), 4)


def hexdump(b, n=32):
    return ' '.join('%02x' % x for x in b[:n])


def find_macs(b, limit=12):
    out = []
    for o in range(0, min(len(b), 0x20000) - 6):
        m = b[o:o + 6]
        if m[0] & 0x01 or m[0] & 0x02:      # 组播 / 本地管理位 → 不是单播 OUI
            continue
        if m == b'\x00' * 6 or m == b'\xff' * 6:
            continue
        if all(x == m[0] for x in m):        # 全同字节占位
            continue
        diffs = [(m[i + 1] - m[i]) & 0xFF for i in range(5)]
        if len(set(diffs)) == 1:             # 等差数列（伪随机/计数器数据）
            continue
        if all(32 <= x < 127 for x in m):    # 纯 ASCII，不是 MAC
            continue
        if m.count(0xFF) >= 2 or m.count(0x00) >= 3:  # 擦除区边缘的伪候选
            continue
        out.append((o, ':'.join('%02x' % x for x in m).upper(),
                    'ART 头部' if o < 0x100 else ''))
        if len(out) >= limit:
            break
    return out


def find_strings(b, limit=20):
    out, cur, start = [], bytearray(), 0
    for i, x in enumerate(b[:0x20000]):
        if 32 <= x < 127:
            if not cur:
                start = i
            cur.append(x)
        else:
            if len(cur) >= 6:
                out.append((start, cur.decode('ascii', 'replace')))
                if len(out) >= limit:
                    break
            cur = bytearray()
    return out


def blockmap(b, bs=0x1000):
    """把 4KB 块压成一行字符：. 全空 / f 全FF / 0 全0 / # 有数据 / + 高熵"""
    out = []
    for o in range(0, len(b), bs):
        c = b[o:o + bs]
        r = nz_ratio(c)
        if r == 0 and c.count(0xFF) == len(c):
            out.append('f')
        elif r == 0 and c.count(0) == len(c):
            out.append('0')
        elif r < 0.02:
            out.append('.')
        elif r > 0.35:
            out.append('+')
        else:
            out.append('#')
    return ''.join(out)


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    p = sys.argv[1]
    if not os.path.isfile(p):
        raise SystemExit('文件不存在: ' + p)
    b = open(p, 'rb').read()
    size = len(b)
    md5 = hashlib.md5(b).hexdigest()
    as_json = '--json' in sys.argv[2:]

    res = {
        'file': os.path.basename(p), 'size': size,
        'size_hex': hex(size), 'md5': md5,
        'overall_nz': nz_ratio(b),
        'head': hexdump(b, 64),
        'blockmap_4k': blockmap(b),
        'macs': [{'offset': hex(o), 'mac': m, 'note': note}
                 for o, m, note in find_macs(b)],
        'strings': [{'offset': hex(o), 'text': s} for o, s in find_strings(b)],
        'candidates': [],
    }
    for off in CANDIDATES:
        if off >= size:
            continue
        w = b[off:off + SLICE]
        res['candidates'].append({
            'offset': hex(off), 'win_size': len(w),
            'nz_ratio': nz_ratio(w),
            'head_nz': nz_ratio(w[:0x1000]),   # 起点前 4KB 有没有数据
            'head': hexdump(w, 32),
        })

    if as_json:
        print(json.dumps(res, ensure_ascii=False, indent=2))
        return

    print('# ART 分析：%s  %d B (%s)  md5=%s' %
          (res['file'], size, res['size_hex'], md5))
    print('# 整体非零(非00/FF)比例: %s  —— 接近 0 说明是空片/刚擦过' %
          res['overall_nz'])
    print('\n## 头 64 字节\n  ' + res['head'])
    print('\n## 4KB 块分布（f=全FF 0=全0 .=近空 #=有数据 +=高熵）')
    bm = res['blockmap_4k']
    for i in range(0, len(bm), 64):
        print('  %06x  %s' % (i * 0x1000, bm[i:i + 64]))
    print('\n## 单播 MAC 候选（前 128KB 内）')
    if res['macs']:
        for m in res['macs']:
            print('  %-10s %s %s' % (m['offset'], m['mac'], m['note']))
    else:
        print('  （未找到，可能 MAC 在别的分区或已被覆盖）')
    print('\n## ASCII 字符串')
    if res['strings']:
        for s in res['strings'][:12]:
            print('  %-10s %s' % (s['offset'], s['text'][:70]))
    else:
        print('  （无）')
    print('\n## 候选 caldata 窗口（每个 %d KB）' % (SLICE // 1024))
    print('  偏移        窗口有效  起点4K  头 32 字节')
    for c in res['candidates']:
        print('  %-10s  %-9s %-7s %s' %
              (c['offset'], c['nz_ratio'], c['head_nz'], c['head']))
    print('\n## 判读')
    if res['overall_nz'] < 0.01:
        print('  ⚠ 这份 ART 几乎是空的 —— 备份可能读错了分区或没读全，'
              '请确认是从 0:ART 用 dd 整片 dump 的（常见 0x100000 = 1 MB）。')
    else:
        nz = [c for c in res['candidates'] if c['head_nz'] > 0.02]
        print('  起点有数据的候选偏移: ' + (', '.join(c['offset'] for c in nz) or '无'))
        print('  这些偏移里有数据的，才可能是 2.4G / 5G pre-cal 切片起点；')
        print('  但「起点对不对」必须由 dmesg 的 calibration / BDF 日志实证，不能只看比例。')
    print('\n  ⚠ ART 只解决「校准/功率/信号强弱」。让无线【能起来】还需要：')
    print('     fdt.dtb 或 /proc/device-tree（board_id / bdf-addr）')
    print('     cat /proc/cmdline（U-Boot 的 cnss2.bdf_* 地址）')
    print('     dmesg | grep -iE "cnss|BDF|bdwlan|cal"')
    print('  ⚠ ART 是每台机器独立校准，只用于你这台，别跨机刷、别外传。')


if __name__ == '__main__':
    main()
