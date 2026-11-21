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
conns = {}   # connection id -> [app, start time, place, already announced]
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


def announce_long():
    """Connections open for more than a minute are written down while still open."""
    while True:
        time.sleep(20)
        now = time.time()
        for cid, c in list(conns.items()):
            if not c[3] and now - c[1] > 60:
                c[3] = True
                with lock:
                    site = names.get(c[2][0])
                where = f"{site} ({c[2][0]}, port {c[2][1]})" if site else f"{c[2][0]}, port {c[2][1]}"
                syslog.syslog(f"{c[0] or 'an unknown app'} has been talking to {where} for over a minute (still open)")


def watch_devices():
    """Camera and microphone: written down when they start and stop being used (decided: truth log only)."""
    import glob
    cam_users, mic_on = set(), False
    while True:
        time.sleep(3)
        users = set()
        for dev in glob.glob("/dev/video*"):
            out = subprocess.run(["fuser", dev], capture_output=True, text=True).stdout.split()
            users |= {a for a in (app_of(p) for p in out) if a}
        for a in users - cam_users:
            syslog.syslog(f"Camera turned on by {a}")
        for a in cam_users - users:
            syslog.syslog(f"Camera turned off ({a} stopped using it)")
        cam_users = users
        on = False
        for st in glob.glob("/proc/asound/card*/pcm*c/sub*/status"):
            try:
                on = on or "RUNNING" in open(st).read()
            except OSError:
                pass
        if on != mic_on:
            syslog.syslog("Microphone in use" if on else "Microphone no longer in use")
            mic_on = on


def local(ip):
    return ip.startswith("127.") or ip == "::1" or ip.startswith("fe80")


def main():
    threading.Thread(target=follow_dns, daemon=True).start()
    threading.Thread(target=announce_long, daemon=True).start()
    threading.Thread(target=watch_devices, daemon=True).start()
    # stdbuf: hand over each event at once (otherwise they arrive in late batches)
    p = subprocess.Popen(["stdbuf", "-oL", "conntrack", "-E", "-e", "NEW,DESTROY", "-o", "id"],
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
        dst, sport = first.get("dst", ""), first.get("sport", "")
        if not cid or local(dst):
            continue
        if kind == "NEW":
            conns[cid] = [find_app(proto, sport), time.time(), (dst, first.get("dport", "?")), False]
            continue
        app, start, _, _ = conns.pop(cid, (None, None, None, None))
        sent = [int(v) for k, v in pairs if k == "bytes"]
        out_b, in_b = (sent + [0, 0])[:2]
        with lock:
            site = names.get(dst)
        where = f"{site} ({dst}, port {first.get('dport', '?')})" if site else f"{dst}, port {first.get('dport', '?')}"
        took = f" for {max(1, int(time.time() - start) - 10)} s" if start else ""   # minus the 10 s it waits after closing
        syslog.syslog(f"{app or 'an unknown app'} talked to {where}{took}: "
                      f"{size(out_b)} out, {size(in_b)} in")


if __name__ == "__main__":
    os.environ["LC_ALL"] = "C"
    main()
