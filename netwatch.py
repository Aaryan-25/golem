# golem-netwatch: writes every internet connection into the truth log, in plain words:
# which app (and its zone), which site, when, how long, and how much data in and out.
# It runs as a small system service and only reads; it never blocks or changes anything.
import os
import re
import subprocess
import syslog
import threading
import time

names = {}   # IP address -> site name, learned from the DNS answers the laptop gets
conns = {}   # connection id -> (app, start time)
lock = threading.Lock()
syslog.openlog("golem-net")


def follow_dns():
    p = subprocess.Popen(["journalctl", "-f", "-n", "0", "-o", "cat", "-t", "dnsmasq"],
                         stdout=subprocess.PIPE, text=True)
    for line in p.stdout:
        m = re.search(r"(?:reply|cached) (\S+) is ([0-9a-fA-F.:]+)$", line.strip())
        if m:
            with lock:
                names[m.group(2)] = m.group(1)


def app_of(pid):
    """'firefox (YELLOW)' for an app in a zone, otherwise the program or service name."""
    try:
        cg = open(f"/proc/{pid}/cgroup").read()
        comm = open(f"/proc/{pid}/comm").read().strip()
    except OSError:
        return None
    m = re.search(r"zone-(red|offline|yellow|green)-([^/]+?)-\d+\.scope", cg)
    if m:
        return f"{m.group(2)} ({m.group(1).upper()})"
    m = re.search(r"system\.slice/([^/]+?)\.service", cg)
    if m:
        return f"{comm} (system service {m.group(1)})"
    return f"{comm} (not in a zone)"


def find_app(proto, sport):
    out = subprocess.run(["ss", "-Hanp", "-t" if proto == "tcp" else "-u"],
                         capture_output=True, text=True).stdout
    for line in out.splitlines():
        cols = line.split()
        if len(cols) < 5 or not cols[3].endswith(f":{sport}"):
            continue
        m = re.search(r"pid=(\d+)", line)
        if m:
            return app_of(m.group(1))
    return None


def size(n):
    for unit in ["bytes", "KB", "MB", "GB"]:
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "bytes" else f"{n:.1f} {unit}"
        n /= 1024


def local(ip):
    return ip.startswith("127.") or ip == "::1" or ip.startswith("fe80")


def main():
    t = threading.Thread(target=follow_dns, daemon=True)
    t.start()
    p = subprocess.Popen(["conntrack", "-E", "-e", "NEW,DESTROY", "-o", "id"],
                         stdout=subprocess.PIPE, text=True)
    for line in p.stdout:
        kind = "NEW" if "[NEW]" in line else "DESTROY" if "[DESTROY]" in line else None
        proto = line.split()[1] if kind else ""
        if proto not in ("tcp", "udp"):
            continue
        pairs = re.findall(r"(\w+)=(\S+)", line)
        first = {}
        for k, v in pairs:
            if k in first:
                break
            first[k] = v
        cid = dict(pairs).get("id")
        src, dst, sport = first.get("src", ""), first.get("dst", ""), first.get("sport", "")
        if not cid or local(dst):
            continue
        if kind == "NEW":
            conns[cid] = (find_app(proto, sport), time.time())
            continue
        app, start = conns.pop(cid, (None, None))
        sent = [int(v) for k, v in pairs if k == "bytes"]
        out_b, in_b = (sent + [0, 0])[:2]
        with lock:
            site = names.get(dst)
        where = f"{site} ({dst}, port {first.get('dport', '?')})" if site else f"{dst}, port {first.get('dport', '?')}"
        took = f" for {int(time.time() - start)} s" if start else ""
        syslog.syslog(f"{app or 'an unknown app'} talked to {where}{took}: "
                      f"{size(out_b)} out, {size(in_b)} in")


if __name__ == "__main__":
    os.environ["LC_ALL"] = "C"
    main()
