# golem-session-apply: makes my side of the settings real in the running desktop (at login and after changes).
# Idle dim/lock, key repeat, touchpad, night light, and the face (Shadow / Negative) everywhere.
import json
import os
import subprocess

SCHEMA = json.load(open("/etc/golem/settings-schema.json"))
THEMES = json.loads(os.environ["GOLEM_THEMES"])
HOME = os.path.expanduser("~")
OUT = f"{HOME}/zones/settings"


def settings():
    c = {k: v["default"] for k, v in SCHEMA.items()}
    try:
        for line in open("/var/lib/golem/settings.conf"):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                if k in SCHEMA and v in SCHEMA[k]["values"]:
                    c[k] = v
    except OSError:
        pass
    return c


def sh(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def main():
    c = settings()
    # idle: the screen saver timer starts the dim; the lock comes after the rest of the time
    dim, lck = c["idle_dim"], c["idle_lock"]
    if lck == "never":
        sh("xset", "s", "off")
    elif dim == "never" or int(dim) >= int(lck):
        sh("xset", "s", str(int(lck) * 60), "1")
    else:
        sh("xset", "s", str(int(dim) * 60), str((int(lck) - int(dim)) * 60))
    sh("xset", "-dpms")
    # keyboard
    sh("xset", "r", "rate", c["kbd_delay"], c["kbd_rate"])
    # touchpad
    for name in sh("xinput", "list", "--name-only").splitlines():
        if "touchpad" in name.lower():
            sh("xinput", "enable" if c["touchpad"] == "on" else "disable", name)
            sh("xinput", "set-prop", name, "libinput Accel Speed", c["touchpad_speed"])
    # night light
    sh("sct", {"off": "6500", "warm": "4500", "warmer": "3500"}[c["night_light"]])
    # the face, everywhere: window lines, background, menus (terminal and lock read it when they start)
    t = THEMES[c["face"]]
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/face.i3", "w") as f:
        f.write(f"client.focused          {t['pale']} {t['void']} {t['text']} {t['pale']} {t['pale']}\n")
        f.write(f"client.focused_inactive {t['void']} {t['void']} {t['mist']} {t['void']} {t['void']}\n")
        f.write(f"client.unfocused        {t['void']} {t['void']} {t['mist']} {t['void']} {t['void']}\n")
        f.write(f"client.background       {t['void']}\n")
    with open(f"{OUT}/face.rasi", "w") as f:
        f.write("* { " + " ".join(f"{k}: {v};" for k, v in t.items()) + " }\n")
    sh("xsetroot", "-solid", t["void"])
    if os.environ.get("GOLEM_NO_RELOAD") != "1":
        sh("i3-msg", "-q", "reload")


if __name__ == "__main__":
    main()
