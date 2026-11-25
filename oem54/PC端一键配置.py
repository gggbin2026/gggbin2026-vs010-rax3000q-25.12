#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
第 43 次 · PC 端一键配置（刷完 NWRT 官方 5.4.213 好固件后运行）

作用：把「刷完还要自己敲一串命令」变成「电脑上跑一次」——
    等待设备 SSH 上线 → 上传 oem54/ → 执行 apply-full-config.sh → 打印验收结果。

用法（在本文件所在目录 oem54/ 里，或把整个 oem54 目录一起拷走）：
    python3 PC端一键配置.py --ip 192.168.1.1 --mode wds
    python3 PC端一键配置.py --ip 172.10.10.231 --mode ap
    python3 PC端一键配置.py --mode wds --dry-run          # 只打印将执行的命令
    python3 PC端一键配置.py --mode wds --verify-only      # 只跑验收，不改设备

依赖：系统 `ssh` / `scp`（OpenSSH，Win10+/macOS/Linux 自带），无第三方 Python 包。
密码：默认 root；脚本不保存密码，交给 ssh 自己交互式询问。
      若装了 sshpass，可用 --password 走非交互（仅建议在自己内网用）。

⚠ 前置：设备已经刷好 3000Q-VS010-固件/ 下对应机型的 NWRT 官方 factory.bin。
   本项目编译的 5.4.164 固件不适用（脚本内的 apply-full-config.sh 会拒绝）。
"""
import argparse
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REQUIRED = ["apply-oem-overlay.sh", "apply-full-config.sh", "oem-overlay.tar.gz"]
VERIFY_CMDS = [
    "uname -r",
    "lsmod | grep -iE 'qca_ol|umac|wifi_3_0|ipq_cnss2|qca_nss_drv' || true",
    "iw dev 2>/dev/null | head -20 || wlanconfig ath0 list 2>/dev/null | head -20 || true",
    "sh /usr/sbin/wifi-stack-check 2>/dev/null | tail -12 || true",
    "/usr/sbin/qsdk-dhcp-guard status 2>/dev/null || true",
    "/usr/sbin/qsdk-rssi-guard status 2>/dev/null || true",
    "sh /usr/sbin/health-fix 2>/dev/null | head -30 || true",
]


def log(msg: str) -> None:
    print(f"[pc] {msg}", flush=True)


def have(cmd: str) -> bool:
    from shutil import which
    return which(cmd) is not None


def wait_ssh(ip: str, port: int, timeout: int) -> bool:
    log(f"等待 {ip}:{port} SSH 上线（最多 {timeout}s，刷完首次开机约需 1~3 分钟）...")
    end = time.time() + timeout
    n = 0
    while time.time() < end:
        try:
            with socket.create_connection((ip, port), timeout=3):
                log(f"✓ SSH 端口已开（第 {n + 1} 次探测）")
                return True
        except OSError:
            n += 1
            time.sleep(3)
    log(f"✗ {timeout}s 内未等到 SSH。请检查：网线、管理 IP、刷机是否完成、TTL 串口是否卡在 failsafe")
    return False


def base_ssh(user: str, ip: str, port: int) -> list:
    return ["ssh", "-p", str(port),
            "-o", "StrictHostKeyChecking=no",
            "-o", "UserKnownHostsFile=/dev/null",
            "-o", "ConnectTimeout=8",
            "-o", "LogLevel=ERROR",
            f"{user}@{ip}"]


def run_local(cmd: list, dry: bool, password: str = "") -> int:
    log("  $ " + " ".join(f"'{c}'" if " " in c else c for c in cmd))
    if dry:
        return 0
    if password and have("sshpass"):
        cmd = ["sshpass", "-p", password] + cmd
    return subprocess.call(cmd)


def run_remote(args, remote_cmd: str, dry: bool) -> int:
    cmd = base_ssh(args.user, args.ip, args.port) + [remote_cmd]
    return run_local(cmd, dry, args.password)


def main() -> int:
    ap = argparse.ArgumentParser(description="刷完 NWRT 官方固件后，PC 端一键配齐仓库定制")
    ap.add_argument("--ip", default="", help="设备管理 IP；留空则依次试常见地址")
    ap.add_argument("--user", default="root")
    ap.add_argument("--port", type=int, default=22)
    ap.add_argument("--mode", choices=["wds", "ap"], default="wds")
    ap.add_argument("--password", default="", help="配合 sshpass 非交互；留空则由 ssh 交互式询问")
    ap.add_argument("--timeout", type=int, default=240, help="等 SSH 上线的秒数")
    ap.add_argument("--dry-run", action="store_true", help="只打印命令，不改动设备")
    ap.add_argument("--verify-only", action="store_true", help="只跑验收，不上传不配置")
    ap.add_argument("--ssid2", default="", help="可选：2.4G SSID")
    ap.add_argument("--ssid5", default="", help="可选：5G SSID")
    args = ap.parse_args()

    log("═══ 第 43 次 · PC 端一键配置 ═══")
    log(f"目录: {HERE}   模式: {args.mode}")

    if not args.dry_run:
        missing = [f for f in REQUIRED if not (HERE / f).is_file()]
        if missing:
            log("✗ 当前目录缺文件: " + ", ".join(missing))
            log("  请把整个 oem54/ 目录一起拷走（含 oem-overlay.tar.gz），或先跑 sh build-oem-overlay.sh")
            return 1
        if not (args.verify_only or have("ssh") and have("scp")):
            log("✗ 系统缺 ssh / scp（Windows 请装 OpenSSH 客户端，或装 Git Bash）")
            return 1

    if not args.ip:
        for cand in ["192.168.1.1", "172.10.10.231", "192.168.2.1", "192.168.0.1"]:
            try:
                with socket.create_connection((cand, args.port), timeout=2):
                    args.ip = cand
                    log(f"自动探测到管理 IP: {cand}")
                    break
            except OSError:
                continue
        if not args.ip:
            log("✗ 没探测到管理 IP，请显式 --ip（TTL 串口里 ip a | grep inet 可看）")
            return 1

    if not args.dry_run and not wait_ssh(args.ip, args.port, args.timeout):
        return 1

    if args.verify_only:
        log("── 只验收 ──")
        for c in VERIFY_CMDS:
            run_remote(args, c, args.dry_run)
        return 0

    # ① dry-run 预演（设备端脚本自己的只读检查）
    log("── ① 设备端预演（apply-full-config.sh --dry-run，完全只读）──")
    rc = run_remote(args, "cd /tmp/oem54 && sh apply-full-config.sh --mode=%s --dry-run" % args.mode, args.dry_run)
    if rc != 0 and not args.dry_run:
        log("⚠ 预演未返回 0（通常是 /tmp/oem54 还没上传，下一步会传）")

    # ② 上传
    log("── ② 上传 oem54/ 到设备 /tmp/oem54 ──")
    scp = ["scp", "-P", str(args.port), "-r",
           "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null",
           "-o", "ConnectTimeout=8", "-o", "LogLevel=ERROR",
           str(HERE), f"{args.user}@{args.ip}:/tmp/oem54"]
    run_local(scp, args.dry_run, args.password)

    # ③ 正式配置
    ssid = ""
    if args.ssid2:
        ssid += " --ssid2=" + args.ssid2
    if args.ssid5:
        ssid += " --ssid5=" + args.ssid5
    log(f"── ③ 执行 apply-full-config.sh --mode={args.mode} ──")
    rc = run_remote(args, "cd /tmp/oem54 && sh apply-full-config.sh --mode=%s%s" % (args.mode, ssid), args.dry_run)
    if rc != 0 and not args.dry_run:
        log("✗ 配置脚本返回非 0，请把整段输出贴回来（常见：刷的不是 5.4.213 官方固件）")
        return rc

    # ④ 验收
    log("── ④ 验收 ──")
    for c in VERIFY_CMDS:
        run_remote(args, c, args.dry_run)

    log("")
    log("═══ 完成 ═══")
    log(f"  管理页 (WDS): http://{args.ip}/bridge/")
    log(f"  管理页 (AP) : http://{args.ip}/ap/")
    log(f"  LuCI        : http://{args.ip}/cgi-bin/luci/   （官方自带 argon，Ctrl+F5 强刷）")
    log(f"  SSH         : ssh root@{args.ip}")
    log("  回滚        : cd /tmp/oem54 && sh apply-full-config.sh --rollback")
    log("")
    log("⚠ 未改动内核 / 无线驱动 / NSS / ART / 分区 —— 全部来自官方原厂镜像。")
    log("⚠ 若 qsdk-dhcp-guard 显示『缓解模式』，是官方内核缺 ebtables/br_netfilter 的如实反馈；")
    log("  要 100% 阻断私设 DHCP 请在上级交换机开 Snooping，或给重要终端设静态 IP。")
    return 0


if __name__ == "__main__":
    sys.exit(main())
