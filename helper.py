# golem-helper: the guard in front of Golem's settings. Runs as root, one request at a time,
# only for lilgolemwitch. It does only the things in its fixed list, and every change goes to
# the truth log. Changing settings needs the password; a first zone for a new app does not.
import json
import os
import re
import socket
import struct
import subprocess
import sys
import syslog

import pam

USER = os.environ["GOLEM_USER"]
UID = int(os.environ["GOLEM_UID"])
APPS = "/var/lib/golem/apps"
KEYS = "/var/lib/golem/keys.conf"
ZONES = ("red", "offline", "yellow", "green")
syslog.openlog("golem")

FIELDS = {
    "zone": lambda v: v in ZONES,
    "ram": lambda v: re.fullmatch(r"[0-9]{2,5}[MG]", v),
    "cpu": lambda v: re.fullmatch(r"[0-9]{1,3}%", v) and 10 <= int(v[:-1]) <= 200,
    "internet": lambda v: v in ("allowed", "never"),
    "camera": lambda v: v in ("allowed", "never"),
    "usb": lambda v: v in ("allowed", "never"),
    "sound": lambda v: v in ("on", "off"),
    "folder": lambda v: v == "" or re.fullmatch(r"~/[A-Za-z0-9._/ -]+", v) and ".." not in v,
}
NAME = re.compile(r"[A-Za-z0-9._+-]{1,64}")
COMBO = re.compile(r"((Super|Alt|Ctrl|Shift)\+){0,3}[A-Za-z0-9_]{1,30}")


def read_conf(path):
    out = {}
    try:
        for line in open(path):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                out[k] = v
    except OSError:
        pass
    return out


def write_conf(name, conf):
    path = f"{APPS}/{name}.conf"
    with open(path + ".tmp", "w") as f:
        for k in FIELDS:
            f.write(f"{k}={conf.get(k, '')}\n")
    os.chmod(path + ".tmp", 0o644)
    os.replace(path + ".tmp", path)


def defaults(zone):
    r = subprocess.run(["zone", "defaults", zone], capture_output=True, text=True).stdout
    return dict(line.split("=", 1) for line in r.splitlines() if "=" in line)


def apply(req):
    apps, keys = req.get("apps", {}), req.get("keys", [])
    for name, conf in apps.items():
        if not NAME.fullmatch(name) or set(conf) - set(FIELDS):
            return f"ERROR bad settings for {name}"
        for k, v in conf.items():
            if not FIELDS[k](v):
                return f"ERROR bad value for {name}: {k}={v}"
    for k in keys:
        if len(k) != 3 or not COMBO.fullmatch(k[0]) or "|" in k[1] + k[2] or "\n" in k[1] + k[2]:
            return "ERROR bad key"
    old_keys = {k[2]: k[0] for k in read_keys()}
    if keys and {k[2] for k in keys} != set(old_keys):
        return "ERROR keys can only be moved, not added or removed"
    # apps
    have = {f[:-5] for f in os.listdir(APPS) if f.endswith(".conf")}
    for name, conf in apps.items():
        old = read_conf(f"{APPS}/{name}.conf")
        if old != conf:
            write_conf(name, conf)
            diff = ", ".join(f"{k} {conf.get(k) or 'default'}" for k in FIELDS if old.get(k) != conf.get(k))
            syslog.syslog(f"SETTINGS {name}: {diff}")
    for name in have - set(apps):
        os.remove(f"{APPS}/{name}.conf")
        syslog.syslog(f"SETTINGS {name}: removed (asks its zone again next time)")
    # keys
    if keys:
        for combo, label, cmd in keys:
            if old_keys.get(cmd) != combo:
                syslog.syslog(f"KEY {combo} now: {label}")
        with open(KEYS + ".tmp", "w") as f:
            for combo, label, cmd in keys:
                f.write(f"{combo} | {label} | {cmd}\n")
        os.chmod(KEYS + ".tmp", 0o644)
        os.replace(KEYS + ".tmp", KEYS)
        subprocess.run(["golem-keys-gen"], check=True)
    return "OK"


def read_keys():
    out = []
    try:
        for line in open(KEYS):
            parts = [p.strip() for p in line.split("|", 2)]
            if len(parts) == 3 and not line.startswith("#"):
                out.append(parts)
    except OSError:
        pass
    return out


def handle(req):
    do = req.get("do")
    if do == "first-zone":          # a new app's zone, chosen once at its first start
        name, zone = req.get("app", ""), req.get("zone", "")
        if not NAME.fullmatch(name) or zone not in ZONES:
            return "ERROR bad request"
        if os.path.exists(f"{APPS}/{name}.conf"):
            return "ERROR this app already has settings; change them in the Control Panel"
        write_conf(name, defaults(zone))
        syslog.syslog(f"SETTINGS {name}: zone {zone.upper()} (first start)")
        return "OK"
    if do == "wifi":
        on = bool(req.get("on"))
        subprocess.run(["nmcli", "radio", "wifi", "on" if on else "off"], check=False)
        syslog.syslog(f"Wi-Fi turned {'ON' if on else 'OFF'}")
        return "OK"
    if do == "apply":
        if not pam.authenticate(USER, req.get("password", ""), service="golem-panel"):
            syslog.syslog("Wrong password in the Control Panel; nothing was changed")
            return "ERROR wrong password, nothing was changed"
        return apply(req)
    return "ERROR unknown request"


def main():
    conn = socket.socket(fileno=sys.stdin.fileno())
    pid, uid, gid = struct.unpack("3i", conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
    data = b""
    while not data.endswith(b"\n") and len(data) < 1_000_000:
        chunk = conn.recv(65536)
        if not chunk:
            break
        data += chunk
    if uid != UID:
        answer = "ERROR not allowed"
    else:
        try:
            answer = handle(json.loads(data))
        except (ValueError, OSError, subprocess.CalledProcessError) as e:
            answer = f"ERROR {e}"
    conn.sendall((answer + "\n").encode())


if __name__ == "__main__":
    main()
