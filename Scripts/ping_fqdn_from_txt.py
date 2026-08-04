#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import csv
import platform
import re
import socket
import subprocess
import time
from datetime import datetime
from pathlib import Path
import tkinter as tk
from tkinter import filedialog


def normalize_lines(lines):
    """过滤空行和注释行"""
    fqdn_list = []
    for line in lines:
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        fqdn_list.append(s)
    return fqdn_list


def resolve_ip(host: str):
    """解析 FQDN -> IPv4"""
    try:
        ip = socket.gethostbyname(host)
        return True, ip
    except Exception as e:
        return False, str(e)


def ping_once(host: str, timeout_ms: int = 1000):
    """
    执行一次 ping，跨平台并尽量避免误判“假OK”
    返回: (ok: bool, elapsed_ms: int, output: str)
    """
    system = platform.system().lower()

    if "windows" in system:
        cmd = ["ping", "-n", "1", "-w", str(timeout_ms), host]
    elif "darwin" in system:
        cmd = ["ping", "-c", "1", "-W", str(timeout_ms), host]
    else:
        timeout_s = max(1, int(round(timeout_ms / 1000.0)))
        cmd = ["ping", "-c", "1", "-W", str(timeout_s), host]

    try:
        start = time.time()
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True
        )
        elapsed_ms = int((time.time() - start) * 1000)
        out_raw = result.stdout or ""
        out = out_raw.lower()

        # 1) 初判
        success = (result.returncode == 0)

        # 2) 失败关键词兜底
        fail_keywords = [
            "request timed out",
            "destination host unreachable",
            "could not find host",
            "name or service not known",
            "temporary failure in name resolution",
            "unknown host",
            "100% packet loss",
            "100.0% packet loss",
            "transmit failed",
            "general failure"
        ]
        if any(k in out for k in fail_keywords):
            success = False

        # 3) 成功特征二次确认
        success_patterns = [
            r"ttl[=\s:]\d+",
            r"\b1 received\b",
            r"\b1 packets received\b",
            r"\b0% packet loss\b",
            r"\b0.0% packet loss\b",
            r"bytes=\d+",
            r"time[=<]\s*\d+(\.\d+)?\s*ms"
        ]
        has_success_pattern = any(re.search(p, out) for p in success_patterns)

        if success and not has_success_pattern:
            success = False

        return success, elapsed_ms, out_raw
    except Exception as e:
        return False, -1, f"ERROR: {e}"


def extract_rtt_ms(ping_output: str):
    """从 ping 输出中提取 RTT(ms)"""
    if not ping_output:
        return ""

    text = ping_output.lower()
    patterns = [
        r"time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms",
        r"time\s*=\s*([0-9]+(?:\.[0-9]+)?)\s*ms",
    ]
    for p in patterns:
        m = re.search(p, text)
        if m:
            return m.group(1)

    if "time<1ms" in text.replace(" ", ""):
        return "1"

    return ""


def pick_txt_file():
    """弹窗选择txt文件"""
    root = tk.Tk()
    root.withdraw()
    root.attributes("-topmost", True)
    file_path = filedialog.askopenfilename(
        title="请选择包含FQDN列表的TXT文件",
        filetypes=[("Text Files", "*.txt"), ("All Files", "*.*")]
    )
    root.destroy()
    return file_path


def main():
    print("请选择 TXT 文件...")
    txt_path = pick_txt_file()
    if not txt_path:
        print("[INFO] 已取消选择，程序结束。")
        return

    input_path = Path(txt_path)
    if not input_path.exists():
        print(f"[ERROR] 文件不存在: {input_path}")
        return

    fqdn_list = normalize_lines(input_path.read_text(encoding="utf-8", errors="ignore").splitlines())
    if not fqdn_list:
        print("[WARN] 文件中没有可用FQDN（可能全是空行/注释）")
        return

    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    print(f"\n# Ping started at {now}")
    print(f"# Source file: {input_path}")
    print(f"# Total hosts: {len(fqdn_list)}\n")

    csv_rows = []
    ok_count = 0
    ping_fail_count = 0
    dns_fail_count = 0

    header = f"{'No.':<6}{'FQDN':<45}{'IP':<18}{'STATUS':<10}{'RTT(ms)':<10}{'ELAPSED(ms)':<12}"
    print(header)
    print("-" * len(header))

    for idx, host in enumerate(fqdn_list, start=1):
        dns_ok, ip_or_err = resolve_ip(host)

        if not dns_ok:
            status = "DNS_FAIL"
            ip = "-"
            rtt_ms = ""
            elapsed_ms = -1
            dns_fail_count += 1
        else:
            ip = ip_or_err
            ok, elapsed_ms, raw_output = ping_once(host, timeout_ms=1000)
            status = "OK" if ok else "PING_FAIL"
            rtt_ms = extract_rtt_ms(raw_output)
            if ok:
                ok_count += 1
            else:
                ping_fail_count += 1

        line = f"{idx:<6}{host:<45}{ip:<18}{status:<10}{str(rtt_ms):<10}{elapsed_ms:<12}"
        print(line)

        csv_rows.append({
            "index": idx,
            "fqdn": host,
            "ip": ip,
            "status": status,
            "rtt_ms": rtt_ms,
            "elapsed_ms": elapsed_ms,
        })

        # 每次间隔 0.2 秒（固定）
        time.sleep(0.2)

    total = len(fqdn_list)
    fail_total = dns_fail_count + ping_fail_count
    print(
        f"\n# Summary: OK={ok_count}, PING_FAIL={ping_fail_count}, "
        f"DNS_FAIL={dns_fail_count}, FAIL_TOTAL={fail_total}, TOTAL={total}"
    )


if __name__ == "__main__":
    main()