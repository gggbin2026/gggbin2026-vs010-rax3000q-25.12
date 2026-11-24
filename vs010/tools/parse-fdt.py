#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
parse-fdt.py —— 不依赖 dtc，直接解析 /sys/firmware/fdt（FDT 二进制 / .dtb）

用途：从「信号正常的那份 VS010 固件」里 dump 出 fdt.dtb 后，
      本脚本把无线节点的 board_id / bdf-addr / caldb-addr / compatible
      原样打印出来，用来对齐编译侧 DTS（替代靠 NWRT 反编译稿推测）。

用法：
    python3 parse-fdt.py fdt.dtb                 # 全量
    python3 parse-fdt.py fdt.dtb wifi           # 只看路径含 wifi/cnss/q6 的节点
    python3 parse-fdt.py fdt.dtb --json wifi    # 机器可读
    python3 parse-fdt.py --tree <dir> wifi      # 只有 /proc/device-tree 解包目录时

也支持直接喂 dtc 生成的 .dts 文本（只做 grep，不解析）。
FDT 格式：header(40B, big-endian) + memrsv + structure tokens + strings block。
参考 Devicetree Specification v0.4 / libfdt fdt_ro.c。
"""
import json
import os
import struct
import sys

FDT_MAGIC = 0xD00DFEED
T_BEGIN_NODE, T_END_NODE, T_PROP, T_NOP, T_END = 1, 2, 3, 4, 9


def u32(b, o):
    return struct.unpack_from('>I', b, o)[0]


def cstr(b, o):
    e = b.find(b'\0', o)
    return b[o:e].decode('utf-8', 'replace'), e + 1


def align4(n):
    return (n + 3) & ~3


STR_NAMES = {
    'compatible', 'model', 'status', 'name', 'device_type', 'label',
    'firmware-name', 'userpd-subsys-name', 'qcom,userpd-subsys-name',
    'clock-names', 'interrupt-names', 'reg-names', 'pinctrl-names',
}


def render(name, val):
    """把属性值渲染成人看得懂的形式。"""
    if len(val) == 0:
        return ''
    # ① 字符串类：按属性名优先，其次「首字节非 0 + 含 \0 + 全可打印」。
    #    首字节必须是可打印字符，否则 caldb-addr=<0 0 0> 会被误判成字符串。
    printable = all(c in b'\0' or 32 <= c < 127 for c in val)
    is_str = (name in STR_NAMES or name.endswith('-names')
              or (b'\0' in val and val[0] != 0 and printable))
    if is_str:
        parts = [p.decode('utf-8', 'replace')
                 for p in val.split(b'\0') if p]
        return ' '.join('"%s"' % p for p in parts)
    # ② 4 字节整数：同时给 hex 与十进制（board_id）
    if len(val) == 4:
        v = u32(val, 0)
        return '<0x%08x>  # %d' % (v, v)
    # ③ 4 的倍数：cell 数组（bdf-addr / caldb-addr / reg / interrupts）
    if len(val) % 4 == 0 and len(val) <= 256:
        cells = ' '.join('0x%08x' % u32(val, i) for i in range(0, len(val), 4))
        return '<%s>' % cells
    return val[:64].hex() + ('...' if len(val) > 64 else '')


def parse(path):
    b = open(path, 'rb').read()
    if len(b) < 40 or u32(b, 0) != FDT_MAGIC:
        raise SystemExit('不是 FDT/dtb（magic != 0xd00dfeed），'
                         '如果这是 dtc 输出的 .dts 文本请直接 grep')
    total = u32(b, 4)
    off_struct, off_strings = u32(b, 8), u32(b, 12)
    off_rsv, version = u32(b, 16), u32(b, 20)
    size_struct = u32(b, 36) if total >= 40 else None
    strblk = b[off_strings:]
    b = b[:total]  # 截断尾部填充，避免把后面垃圾读进来

    o, stack, nodes = off_struct, [], []
    while o < len(b):
        tok = u32(b, o); o += 4
        if tok == T_BEGIN_NODE:
            name, o = cstr(b, o); o = align4(o)
            stack.append(name)
            cur = '/'.join(x for x in stack if x) or '/'
            nodes.append({'path': '/' + cur.lstrip('/'), 'props': {}})
        elif tok == T_END_NODE:
            if stack: stack.pop()
        elif tok == T_PROP:
            ln, no = u32(b, o), u32(b, o + 4); o += 8
            val = b[o:o + ln]; o = align4(o + ln)
            pname, _ = cstr(strblk, no)
            if nodes:
                nodes[-1]['props'][pname] = val
        elif tok == T_NOP:
            pass
        elif tok == T_END:
            break
        else:
            raise SystemExit('未知 FDT token 0x%x @0x%x' % (tok, o - 4))
    return {'version': version, 'size': total, 'nodes': nodes}


def scan_tree(root, kw, as_json=False):
    """解析已解包的 /proc/device-tree 目录（有些固件不导出 /sys/firmware/fdt）。"""
    out = []
    for dirpath, dirs, files in os.walk(root):
        rel = os.path.relpath(dirpath, root)
        p = '/' if rel == '.' else '/' + rel.replace(os.sep, '/')
        if kw and not any(k in p.lower() for k in kw):
            continue
        props = {}
        for fn in sorted(files):
            try:
                props[fn] = open(os.path.join(dirpath, fn), 'rb').read()
            except OSError:
                continue
        if props:
            out.append((p, {k: render(k, v) for k, v in props.items()}))
    if as_json:
        print(json.dumps([{'path': p, 'props': d} for p, d in out],
                         ensure_ascii=False, indent=2))
        return
    print('# /proc/device-tree (%d nodes with props)' % len(out))
    for p, props in out:
        print('\n%s' % p)
        for k, v in props.items():
            print('\t%-34s = %s' % (k, v))


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    path = sys.argv[1]
    rest = sys.argv[2:]
    as_json = '--json' in rest
    kw = [x.lower() for x in rest if not x.startswith('--')]
    if path == '--tree':
        if not rest or not os.path.isdir(rest[0]):
            raise SystemExit('用法: parse-fdt.py --tree <解包后的device-tree目录> [wifi]')
        root = rest[0]
        kw = [x.lower() for x in rest[1:] if not x.startswith('--')]
        return scan_tree(root, kw or ['wifi', 'cnss', 'q6', 'wcss'], as_json)
    if path.endswith('.dts') or path.endswith('.txt'):
        # dtc 已经出文本了，直接过滤
        txt = open(path, encoding='utf-8', errors='replace').read()
        print(txt if not kw else '\n'.join(
            l for l in txt.splitlines()
            if any(k in l.lower() for k in kw)
            or any(k in l.lower() for k in ('wifi', 'board_id', 'bdf-addr', 'caldb'))))
        return
    d = parse(path)
    sel = [n for n in d['nodes']
           if not kw or any(k in n['path'].lower() for k in kw)]
    if as_json:
        print(json.dumps({'size': d['size'], 'version': d['version'],
                          'nodes': [{'path': n['path'],
                                     'props': {k: render(k, v)
                                               for k, v in n['props'].items()}}
                                    for n in sel]},
                         ensure_ascii=False, indent=2))
        return
    print('# FDT %d B, version %d, %d nodes' %
          (d['size'], d['version'], len(d['nodes'])))
    for n in sel:
        if not n['props']:
            continue
        print('\n%s' % n['path'])
        for k, v in n['props'].items():
            print('\t%-34s = %s' % (k, render(k, v)))


if __name__ == '__main__':
    main()
