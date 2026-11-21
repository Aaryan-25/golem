# golem-truth: what the system did, in plain words, newest at the bottom (kept 30 days).
#   golem-truth          the whole log, in a scrollable view
#   golem-truth --text   print it (for the Control Panel)
#   --kind apps|internet|devices|passwords|settings|system   only that kind
import json
import re
import subprocess
import sys
import time

SOURCES = ["zone", "golem", "golem-net", "golem-usb", "sudo", "i3lock", "login", "su", "NetworkManager", "systemd-coredump"]


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
        m = re.match(r"SETTINGS (.+?): (.*)$", msg)
        if m:
            return f"Settings: {m.group(1)}: {m.group(2)}"
        m = re.match(r"KEY (\S+) now: (.*)$", msg)
        if m:
            return f"Keys: {m.group(1)} now does: {m.group(2)}"
        return {"LOCK": "Screen locked", "UNLOCK": "Screen unlocked",
                "LOCK failed": "The lock screen failed to start"}.get(msg, msg)
    if ident == "golem-net":
        if msg.startswith(("Camera", "Microphone")):
            return msg
        return "Internet: " + msg
    if ident == "systemd-coredump":
        m = re.search(r"Process \d+ \((.+?)\) of user", msg)
        return f"{m.group(1)} crashed (the crash report is kept 7 days, never sent anywhere)" if m else None
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


def kind(ident, text):
    if ident == "golem-net" and not text.startswith(("Camera", "Microphone")):
        return "internet"
    if ident == "zone" and text.startswith(("Opened", "Closed")):
        return "apps"
    if "password" in text.lower():
        return "passwords"
    if text.startswith(("Settings", "Keys", "Startup", "Backup", "Save slot", "Storage", "Clock", "Golem updated")):
        return "settings"
    if ident == "golem-usb" or text.startswith(("Camera", "Microphone", "Wi-Fi", "Bluetooth", "Connected to")):
        return "devices"
    return "system"


def lines(only=None):
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
        if text and (only is None or kind(e.get("SYSLOG_IDENTIFIER", ""), text) == only):
            t = time.localtime(int(e["__REALTIME_TIMESTAMP"]) / 1e6)
            yield time.strftime("%a %d %b %H:%M:%S", t) + "  " + text


def main():
    only = sys.argv[sys.argv.index("--kind") + 1] if "--kind" in sys.argv else None
    text = "\n".join(lines(only)) or "Nothing yet."
    if "--text" in sys.argv or not sys.stdout.isatty():
        print(text)
    else:
        subprocess.run(["less", "-S", "+G"], input=text + "\n", text=True)


if __name__ == "__main__":
    main()
