# golem-settings-apply: makes the system side of my settings real (runs as root, at start and after Apply).
# Drivers on/off, microphone, processor mode, battery charge limit, tracker and ad blocking.
# Part of Golem: settings and the look; MAP.md section 5.4.
import glob
import json
import os
import subprocess
import syslog

SCHEMA = json.load(open("/etc/golem/settings-schema.json"))
CONF = "/var/lib/golem/settings.conf"
FALSE = os.environ.get("GOLEM_FALSE", "/run/current-system/sw/bin/false")
BLOCKLIST = os.environ.get("GOLEM_BLOCKLIST", "")
MODULES = {
    "camera": ["uvcvideo"],
    "bluetooth_driver": ["btusb", "btintel"],
    "wifi_driver": ["iwlmvm", "iwlwifi"],
    "usb_storage": ["uas", "usb_storage"],
    "card_reader": ["rtsx_pci_sdmmc", "rtsx_usb_sdmmc", "rtsx_pci", "rtsx_usb"],
}
syslog.openlog("golem")


def load():
    conf = {k: v["default"] for k, v in SCHEMA.items()}
    if os.path.exists(CONF):
        for line in open(CONF):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                if k in SCHEMA and v in SCHEMA[k]["values"]:
                    conf[k] = v
    return conf


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def root_on_usb():
    src = sh("findmnt", "-no", "SOURCE", "/").stdout.strip()
    disk = sh("lsblk", "-no", "PKNAME", src).stdout.strip()
    return sh("lsblk", "-dno", "TRAN", f"/dev/{disk}").stdout.strip() == "usb"


def write(path, value):
    try:
        with open(path, "w") as f:
            f.write(value)
        return True
    except OSError:
        return False


def main():
    c = load()
    # Drivers: an OFF driver is never loaded ("install … false"), and is unloaded now.
    if c["usb_storage"] == "off" and root_on_usb():
        c["usb_storage"] = "on"
        syslog.syslog("USB drives stay ON: Golem itself runs from a USB drive")
    off = [m for k, mods in MODULES.items() if c[k] == "off" for m in mods]
    os.makedirs("/run/modprobe.d", exist_ok=True)
    with open("/run/modprobe.d/golem.conf", "w") as f:
        f.write("# Drivers switched off in the Control Panel (DRIVERS)\n")
        for m in off:
            f.write(f"install {m} {FALSE}\n")
    for m in off:
        sh("modprobe", "-r", m)
    for k, mods in MODULES.items():
        if c[k] == "on":
            sh("modprobe", mods[0])
    # Microphone: the recording side of every sound card.
    for card in glob.glob("/proc/asound/card[0-9]*"):
        n = card[len("/proc/asound/card"):]
        sh("amixer", "-q", "-c", n, "set", "Capture", "cap" if c["microphone"] == "on" else "nocap")
    # Processor
    mode = c["power_mode"]
    if mode == "by charger":       # the optimiser: saver on battery, balanced on the charger (udev re-runs this)
        plugged = any(open(p).read().strip() == "1" for p in glob.glob("/sys/class/power_supply/*/online"))
        mode = "balanced" if plugged else "saver"
    gov = {"saver": "powersave", "balanced": "schedutil", "full": "performance"}[mode]
    for p in glob.glob("/sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor"):
        avail = open(p.replace("scaling_governor", "scaling_available_governors")).read().split()
        write(p, gov if gov in avail else ("powersave" if mode != "full" else "performance"))
    # Battery charge limit, where the laptop allows it
    for p in glob.glob("/sys/class/power_supply/BAT*/charge_control_end_threshold"):
        write(p, c["charge_limit"])
    # Trackers and ads
    dst = "/var/lib/golem/blocklist.hosts"
    tmp = dst + ".tmp"
    if os.path.lexists(tmp):
        os.remove(tmp)
    if c["trackers"] == "on" and BLOCKLIST:
        os.symlink(BLOCKLIST, tmp)
    else:
        open(tmp, "w").close()
    os.replace(tmp, dst)
    sh("pkill", "-HUP", "-x", "dnsmasq")


if __name__ == "__main__":
    main()
