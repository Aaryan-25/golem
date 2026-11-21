# golem-keys-gen: turns my key list (/var/lib/golem/keys.conf) into the window manager's key lines
# and the list Super+H shows. Keys that a new Golem version adds are appended; keys I moved stay moved.
import os

DEFAULT = "/etc/golem/keys.default"
KEYS = "/var/lib/golem/keys.conf"
OUT_I3 = "/var/lib/golem/keys.i3"
OUT_TXT = "/var/lib/golem/keys.txt"


def read(path):
    out = []
    if not os.path.exists(path):
        return out
    for line in open(path):
        parts = [p.strip() for p in line.split("|", 2)]
        if len(parts) == 3 and not line.startswith("#"):
            out.append(parts)
    return out


def i3(combo):
    return combo.replace("Super+", "Mod4+").replace("Alt+", "Mod1+").replace("Ctrl+", "Control+")


def main():
    os.makedirs("/var/lib/golem/apps", exist_ok=True)
    mine = read(KEYS)
    have = {cmd for _, _, cmd in mine}
    added = [k for k in read(DEFAULT) if k[2] not in have]
    keys = mine + added
    if added or not os.path.exists(KEYS):
        with open(KEYS + ".tmp", "w") as f:
            f.write("# My keys: key | what it does | command. Change them in the Control Panel (Super+Z).\n")
            for k in keys:
                f.write(" | ".join(k) + "\n")
        os.chmod(KEYS + ".tmp", 0o644)
        os.replace(KEYS + ".tmp", KEYS)
    with open(OUT_I3 + ".tmp", "w") as f:
        for combo, _, cmd in keys:
            f.write(f"bindsym {i3(combo)} {cmd}\n")
    with open(OUT_TXT + ".tmp", "w") as f:
        for combo, label, _ in keys:
            f.write(f"{combo} | {label}\n")
    for p in (OUT_I3, OUT_TXT):
        os.chmod(p + ".tmp", 0o644)
        os.replace(p + ".tmp", p)


if __name__ == "__main__":
    main()
