#!/usr/bin/env python3
"""切歌内存定点采样器。

用途：把「进程内存」拆成 Dart 堆与 native 两块，边切歌边记录，
      用来判断内存上涨发生在 Dart 堆还是引擎/native 侧。

用法：
    python scripts/mem_watch.py                # 自动从 run.log 抓 VM service 地址
    python scripts/mem_watch.py --url <URL>    # 手动指定
    python scripts/mem_watch.py --interval 1   # 采样间隔（秒）

前提：应用以 `flutter run -d windows --profile` 启动并保持运行。
      采样期间照常切歌即可，Ctrl+C 结束。
"""

import argparse
import ctypes
import ctypes.wintypes as wt
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request

PROCESS_QUERY_INFORMATION = 0x0400
PROCESS_VM_READ = 0x0010


class PROCESS_MEMORY_COUNTERS_EX(ctypes.Structure):
    _fields_ = [
        ("cb", wt.DWORD),
        ("PageFaultCount", wt.DWORD),
        ("PeakWorkingSetSize", ctypes.c_size_t),
        ("WorkingSetSize", ctypes.c_size_t),
        ("QuotaPeakPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPagedPoolUsage", ctypes.c_size_t),
        ("QuotaPeakNonPagedPoolUsage", ctypes.c_size_t),
        ("QuotaNonPagedPoolUsage", ctypes.c_size_t),
        ("PagefileUsage", ctypes.c_size_t),
        ("PeakPagefileUsage", ctypes.c_size_t),
        ("PrivateUsage", ctypes.c_size_t),
    ]


def find_pid(name="Vynody.exe"):
    """按映像名查找进程，返回 (pid, rss_bytes)。"""
    import subprocess

    out = subprocess.run(
        ["tasklist", "/FO", "CSV", "/NH", "/FI", f"IMAGENAME eq {name}"],
        capture_output=True,
        text=True,
        errors="ignore",
    ).stdout
    for line in out.splitlines():
        parts = [p.strip('"') for p in line.split('","')]
        if len(parts) >= 5 and parts[0].lower() == name.lower():
            mem = int(re.sub(r"[^\d]", "", parts[4]) or 0) * 1024
            return int(parts[1]), mem
    return None, 0


def read_process_memory(pid):
    """返回 (working_set, private_bytes)。"""
    kernel32 = ctypes.windll.kernel32
    psapi = ctypes.windll.psapi
    handle = kernel32.OpenProcess(PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, False, pid)
    if not handle:
        return None
    try:
        counters = PROCESS_MEMORY_COUNTERS_EX()
        counters.cb = ctypes.sizeof(counters)
        if not psapi.GetProcessMemoryInfo(handle, ctypes.byref(counters), counters.cb):
            return None
        return counters.WorkingSetSize, counters.PrivateUsage
    finally:
        kernel32.CloseHandle(handle)


def discover_url(log_path="run.log"):
    """从 flutter run 日志里抓 Dart VM Service 地址。"""
    if not os.path.exists(log_path):
        return None
    pattern = re.compile(
        r"Dart VM Service on Windows is available at:\s*(http://127\.0\.0\.1:\d+/[^\s]+/)"
    )
    with open(log_path, "r", encoding="utf-8", errors="ignore") as fh:
        matches = pattern.findall(fh.read())
    return matches[-1] if matches else None


def rpc(base, method, **params):
    query = "&".join(f"{k}={urllib.parse.quote(str(v), safe='')}" for k, v in params.items())
    url = f"{base}{method}" + (f"?{query}" if query else "")
    with urllib.request.urlopen(url, timeout=5) as resp:
        payload = json.load(resp)
    if "error" in payload:
        raise RuntimeError(payload["error"])
    return payload["result"]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", help="Dart VM Service 地址")
    parser.add_argument("--interval", type=float, default=2.0)
    parser.add_argument("--log", default="run.log")
    args = parser.parse_args()

    base = args.url or discover_url(args.log)
    if not base:
        print("未能从日志中找到 VM Service 地址，请用 --url 手动指定。", file=sys.stderr)
        return 1

    vm = rpc(base, "getVM")
    isolate_id = next(
        (i["id"] for i in vm["isolates"] if i["name"] == "main"), None
    )
    if not isolate_id:
        print("未找到 main isolate。", file=sys.stderr)
        return 1

    print(f"attached: pid={vm['pid']} isolate={isolate_id}")
    print(f"{'t':>5} {'dartHeap':>9} {'capacity':>9} {'external':>9} "
          f"{'rss':>8} {'private':>8}  {'dHeap':>7} {'dRss':>7}")
    print("-" * 78)

    start = time.time()
    prev = None
    try:
        while True:
            try:
                usage = rpc(base, "getMemoryUsage", isolateId=isolate_id)
            except Exception as exc:  # 应用退出或端口变化
                print(f"采样失败：{exc}", file=sys.stderr)
                return 1

            pid, _ = find_pid()
            mem = read_process_memory(pid) if pid else None
            if not mem:
                print("进程已退出。", file=sys.stderr)
                return 0

            heap = usage["heapUsage"]
            cap = usage["heapCapacity"]
            ext = usage["externalUsage"]
            rss, priv = mem

            cur = (heap, rss)
            d_heap = (cur[0] - prev[0]) / 1048576 if prev else 0.0
            d_rss = (cur[1] - prev[1]) / 1048576 if prev else 0.0
            prev = cur

            print(
                f"{time.time() - start:5.0f} "
                f"{heap / 1048576:9.1f} {cap / 1048576:9.1f} {ext / 1048576:9.1f} "
                f"{rss / 1048576:8.1f} {priv / 1048576:8.1f}  "
                f"{d_heap:+7.1f} {d_rss:+7.1f}"
            )
            sys.stdout.flush()
            time.sleep(args.interval)
    except KeyboardInterrupt:
        print("\nstopped")
        return 0


if __name__ == "__main__":
    sys.exit(main())
