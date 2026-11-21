# golem-truth: what the system did, in plain words, newest at the bottom (kept 30 days).
#   golem-truth          the whole log, in a scrollable view
#   golem-truth --text   print it (for the Control Panel)
import json
import re
import subprocess
import sys
import time

SOURCES = ["zone", "golem", "golem-net", "golem-usb", "sudo", "i3lock", "login", "su", "NetworkManager"]


def sentence(ident, msg):
    if ident == "zone":
        m = re.match(r"START (\w+) (\S+) \| internet:(\w+) camera:(\w+) sound:(\w+) usb:(\w+)", msg)
        if m:
            z, app, net, cam, snd, usb = m.groups()
            return f"Opened {app} in {z}  (internet {net}, camera {cam}, sound {snd}, USB {usb})"
        m = re.match(r"END\s+(\w+) (\S+)", msg)
        if m:
            return f"Closed {m.group(2)} ({m.group(1)})"
        m = re.match(r"SETTINGS (\S+): zone (\w+)", msg)
        if m:
            return f"Settings: {m.group(1)} now opens in {m.group(2)}"
        return msg
    if ident == "golem":
        return {"LOCK": "Screen locked", "UNLOCK": "Screen unlocked",
                "LOCK failed": "The lock screen failed to start"}.get(msg, msg)
    if ident == "golem-net":
        return "Internet: " + msg
    if ident == "golem-usb":
        return msg
    if ident == "sudo":
        m = re.search(r"COMMAND=(.*)$", msg)
        if m:
            return "Admin rights used for: " + m.group(1)
        if "incorrect password" in msg or "authentication failure" in msg:
            return "Wrong password when asking for admin rights"
        return None
    if ident in ("i3lock", "login", "su"):
        if "authentication failure" in msg:
            return {"i3lock": "Wrong password at the lock screen",
                    "login": "Wrong password at login",
                    "su": "Wrong password when switching user"}[ident]
        return None
    if ident == "NetworkManager":
        m = re.search(r"policy: set '(.+?)' \(\S+\) as default for IPv4", msg)
        if m:
            return f"Connected to the network '{m.group(1)}'"
        return None
    return None


def lines():
    args = ["journalctl", "--no-pager", "-o", "json", "--since", "-30 days"]
    for s in SOURCES:
        args += ["-t", s]
    out = subprocess.run(args, capture_output=True, text=True).stdout
    for raw in out.splitlines():
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        msg = e.get("MESSAGE")
        if not isinstance(msg, str):
            continue
        text = sentence(e.get("SYSLOG_IDENTIFIER", ""), msg)
        if text:
            t = time.localtime(int(e["__REALTIME_TIMESTAMP"]) / 1e6)
            yield time.strftime("%a %d %b %H:%M:%S", t) + "  " + text


def main():
    text = "\n".join(lines()) or "Nothing yet."
    if "--text" in sys.argv or not sys.stdout.isatty():
        print(text)
    else:
        subprocess.run(["less", "-S", "+G"], input=text + "\n", text=True)


if __name__ == "__main__":
    main()
