#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
make-board2.py —— ART 切片 / ath11k board-2.bin 容器工具（离线、只读源文件）

格式完全对齐 qca/qca-swiss-army-knife 的 ath11k-bdencoder：
    signature : b"QCA-ATH11K-BOARD\\0" + 0x6d 补齐到 20 字节
    主 IE     : <2i (ie_id, ie_len)，ATH11K_BD_IE_BOARD = 0
      子 IE   : <2i (id, len) + value + 0x6d padding 到 4 字节对齐
                BOARD_NAME = 0 / BOARD_DATA = 1
生成的容器可用 art/tools/ath11k-bdencoder --info 交叉验证。

★ 第 41 次（2026-11-24）真解包 5.4.213 好固件后的最终口径：
  · 实机日志确认下载 IPQ5018/bdwlan.b10 与 qcn6122/bdwlan.b60（各 131072 B），
    报 Caldata not present / CAL version 0；两台真实 DTB 的 caldb-addr=0 / size=0 印证。
  · 但【没有证据】说明这些 BDF 等于本仓模板 BDF：真解包发现好固件 BDF、模板 BDF、
    4.4.60 老固件 BDF、ART 切片四套互不相同，且 VS010 与 RAX3000Q 也互不相同。
  · 第 40 次「MD5 == 模板 BDF」的断言已作废（见 vs010/oem-qsdk-truth.conf）。
  · 因此 from-oem 只作【实验性可选】：用本仓模板 BDF 造容器，不宣称实证等价；
    默认 ART_CALIBRATION=0 完全不装配，最稳。ART 切片 / QSDK 单 BDF 一律不进固件。

五个子命令：

  # 实验性可选：用本仓模板 BDF 造容器（默认不装配；别宣称等价于好固件）
  python3 art/make-board2.py from-oem --out art/out/vs010/board-2.bin
  python3 art/make-board2.py from-oem --base /path/to/upstream/board-2.bin \
      --out art/out/vs010/board-2.bin        # 追加，保留官方兜底条目

  # 仅采集/存档：从 0:ART 切出 128 KB 单 BDF（不改名、不当容器用、不进固件）
  python3 art/make-board2.py slice --art 010-smem_0-ART.bin --radio 2g --out /tmp/vs010-2g.bdf
  python3 art/make-board2.py slice --art 010-smem_0-ART.bin --radio 5g --out /tmp/vs010-5g.bdf

  # 通用：用任意单 BDF 造 / 追加容器（⚠ 别喂 ART 切片，见上）
  python3 art/make-board2.py create --bdf X.bdf --name '...' --out board-2.bin
  python3 art/make-board2.py append --base upstream.bin --bdf X.bdf --name '...' --out board-2.bin

  python3 art/make-board2.py info /tmp/board-2.bin

⚠ qmi-board-id / variant 必须与 DTS 的 qcom,ath11k-calibration-variant 一致，
  猜错会匹配不到条目 → 射频不 probe。from-oem 的 16 / 96 对应 VS010 好固件 DTB 的
  qcom,board_id 0x10 / 0x60；★ RAX3000Q 的 2G 是 0x24(36)，但那是闭源 cnss2 的属性，
  不能想当然当成主线 ath11k 的 qmi-board-id 抄过去。
⚠ 本工具默认不参与编译；产物只有被显式放到 art/out/<机型>/board-2.bin
  （VS010 兼容老路径 vs010/bdf/board-2.bin）且 ART_CALIBRATION=1 才会被装配。
"""
import argparse
import hashlib
import os
import struct
import sys

SIG = b"QCA-ATH11K-BOARD\0"
SIG_LEN = 20
PAD = 0x6d
TYPE_LENGTH_SIZE = 8
IE_BOARD = 0
IE_BOARD_NAME = 0
IE_BOARD_DATA = 1
SLICE = 0x20000          # 128 KB，ath11k caldata / BDF 常见长度
OFFSET = {'2g': 0x1000, '5g': 0x26800}
MAGIC = bytes.fromhex('01000404')


def pad_needed(n):
    return (4 - n % 4) % 4


def add_ie(buf, ie_id, value):
    p = pad_needed(len(value))
    buf += struct.pack('<2i', ie_id, len(value)) + value + bytes([PAD]) * p
    return buf


def make_board(names, data):
    inner = b''
    for n in names:
        inner = add_ie(inner, IE_BOARD_NAME, n.encode())
    inner = add_ie(inner, IE_BOARD_DATA, data)
    return struct.pack('<2i', IE_BOARD, len(inner)) + inner


def write_container(path, boards):
    body = SIG + bytes([PAD]) * (SIG_LEN - len(SIG))
    for names, data in boards:
        body += make_board(names, data)
    open(path, 'wb').write(body)
    return body


def read_container(path):
    b = open(path, 'rb').read()
    if not b.startswith(SIG):
        raise SystemExit('不是 ath11k board-2.bin（缺 QCA-ATH11K-BOARD 签名）')
    off, out = SIG_LEN, []
    while off + TYPE_LENGTH_SIZE <= len(b):
        ie_id, ie_len = struct.unpack_from('<2i', b, off)
        off += TYPE_LENGTH_SIZE
        if ie_id != IE_BOARD or off + ie_len > len(b):
            break
        end = off + ie_len
        names, data = [], None
        while off + TYPE_LENGTH_SIZE <= end:
            sid, slen = struct.unpack_from('<2i', b, off)
            off += TYPE_LENGTH_SIZE
            val = b[off:off + slen]
            off += slen + pad_needed(slen)
            if sid == IE_BOARD_NAME:
                names.append(val.decode('utf-8', 'replace'))
            elif sid == IE_BOARD_DATA:
                data = val
        out.append((names, data))
        off = end + pad_needed(ie_len)
    return out


def cmd_slice(a):
    d = open(a.art, 'rb').read()
    off = OFFSET[a.radio]
    b = d[off:off + SLICE]
    if len(b) != SLICE or b[:4] != MAGIC:
        raise SystemExit('偏移 0x%x 不是合法 128KB BDF（magic=%s）' % (off, b[:4].hex()))
    open(a.out, 'wb').write(b)
    print('  %s @0x%x → %s' % (a.radio, off, a.out))
    print('  size=%d  md5=%s  内嵌MAC=%s' %
          (len(b), hashlib.md5(b).hexdigest(),
           ':'.join('%02X' % x for x in b[0x0e:0x14])))


def _pairs(bdfs, names):
    if len(bdfs) != len(names) or not bdfs:
        raise SystemExit('--bdf 与 --name 必须一一对应且至少一组')
    out = []
    for f, n in zip(bdfs, names):
        out.append(([n], open(f, 'rb').read()))
    return out


def cmd_create(a):
    boards = _pairs(a.bdf, a.name)
    body = write_container(a.out, boards)
    print('  已生成 %s（%d B，%d 个条目，md5=%s）' %
          (a.out, len(body), len(boards), hashlib.md5(body).hexdigest()))
    print('  ⚠ 只含本机条目，匹配不到时射频可能不 probe；推荐用 append 保留官方兜底。')


def cmd_append(a):
    base = read_container(a.base)
    add = _pairs(a.bdf, a.name)
    # 同名条目替换，其余原样保留
    idx = {}
    for i, (names, _) in enumerate(base):
        for n in names:
            idx[n] = i
    merged = list(base)
    for names, data in add:
        for n in names:
            if n in idx:
                old = merged[idx[n]]
                merged[idx[n]] = (old[0], data)
            else:
                idx[n] = len(merged)
                merged.append(([n], data))
    body = write_container(a.out, merged)
    print('  官方条目 %d 个 + 本机条目 %d 个 → %s（%d B，md5=%s）' %
          (len(base), len(add), a.out, len(body), hashlib.md5(body).hexdigest()))


def _merge(base, add):
    """同名条目替换，其余原样保留"""
    idx = {}
    for i, (names, _) in enumerate(base):
        for n in names:
            idx[n] = i
    merged = list(base)
    for names, data in add:
        for n in names:
            if n in idx:
                old = merged[idx[n]]
                merged[idx[n]] = (old[0], data)
            else:
                idx[n] = len(merged)
                merged.append(([n], data))
    return merged


def cmd_from_oem(a):
    """用好固件实证在用的模板 BDF（bdwlan.b10 / bdwlan.b60）造容器。

    绝不使用 ART 切片：实机日志证明它们没被加载（Caldata not present）。
    """
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    b2g = os.path.join(root, 'vs010/bdf/board-cucc_vs010.ipq5018')
    b5g = os.path.join(root, 'vs010/bdf/board-cucc_vs010.qcn6122')
    for p in (b2g, b5g):
        if not os.path.isfile(p):
            raise SystemExit('缺实证模板 BDF: ' + p)
    n2 = 'bus=ahb,qmi-chip-id=0,qmi-board-id=%d,variant=%s' % (a.board2g, a.variant)
    n5 = 'bus=ahb,qmi-chip-id=0,qmi-board-id=%d,variant=%s' % (a.board5g, a.variant)
    add = [([n2], open(b2g, 'rb').read()), ([n5], open(b5g, 'rb').read())]
    print('  实证来源：IPQ5018/bdwlan.b10 (board_id 0x%X) + '
          'qcn6122/bdwlan.b60 (0x%X)' % (a.board2g, a.board5g))
    for names, d in add:
        print('    %s\n      %d B  md5=%s  magic=%s' %
              (names[0], len(d), hashlib.md5(d).hexdigest(), d[:4].hex()))
    if a.base:
        base = read_container(a.base)
        merged = _merge(base, add)
        print('  官方兜底条目 %d 个 + 实证本机条目 2 个' % len(base))
    else:
        merged = add
        print('  ⚠ 未指定 --base：容器只含本机 2 个条目，匹配不到时无兜底。')
        print('    推荐加 --base <官方 board-2.bin> 用 append 语义保留通用条目。')
    body = write_container(a.out, merged)
    print('  → %s（%d B，md5=%s）' %
          (a.out, len(body), hashlib.md5(body).hexdigest()))
    print('  下一步：python3 art/tools/ath11k-bdencoder --info %s 交叉验证' % a.out)


def cmd_info(a):
    boards = read_container(a.file)
    print('=== %s ===' % a.file)
    print('  条目数: %d' % len(boards))
    for i, (names, data) in enumerate(boards):
        print('  [%d] %s' % (i, ' | '.join(names)))
        if data is not None:
            print('      data: %d B  md5=%s  magic=%s' %
                  (len(data), hashlib.md5(data).hexdigest(), data[:4].hex()))


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest='cmd', required=True)

    q = sub.add_parser('from-oem', help='★ 用好固件实证在用的模板 BDF 造 board-2.bin')
    q.add_argument('--out', required=True)
    q.add_argument('--base', help='官方 board-2.bin；给定时用追加语义保留兜底条目')
    q.add_argument('--variant', default='Unicom-VS010',
                   help='必须与 DTS 的 ath11k-calibration-variant 一致（默认 Unicom-VS010）')
    q.add_argument('--board2g', type=int, default=16, help='2G qmi-board-id（实证 0x10=16）')
    q.add_argument('--board5g', type=int, default=96, help='5G qmi-board-id（实证 0x60=96）')
    q.set_defaults(fn=cmd_from_oem)

    s = sub.add_parser('slice', help='仅采集/存档：从 ART 切出 128KB 单 BDF（不进固件）')
    s.add_argument('--art', required=True)
    s.add_argument('--radio', choices=['2g', '5g'], required=True)
    s.add_argument('--out', required=True)
    s.set_defaults(fn=cmd_slice)

    for name, helptext, fn in [('create', '造只含本机条目的容器', cmd_create),
                               ('append', '把本机条目追加到官方容器', cmd_append)]:
        q = sub.add_parser(name, help=helptext)
        q.add_argument('--bdf', action='append', required=True, help='单 BDF 文件，可重复')
        q.add_argument('--name', action='append', required=True, help='条目名，可重复')
        q.add_argument('--out', required=True)
        if name == 'append':
            q.add_argument('--base', required=True, help='官方 board-2.bin')
        q.set_defaults(fn=fn)

    q = sub.add_parser('info', help='解析容器')
    q.add_argument('file')
    q.set_defaults(fn=cmd_info)

    a = p.parse_args()
    a.fn(a)


if __name__ == '__main__':
    main()
