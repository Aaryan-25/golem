# golem-keylight: the keyboard's lights, from a simple file or a command, so Echo's extensions can use them too.
#   golem-keylight what              what this keyboard can show
#   golem-keylight all COLOUR        every key one colour (#ff8800, white, off ...)
#   golem-keylight key KEY COLOUR    one key (kept in the pattern; shown as well as the keyboard allows)
#   golem-keylight level 0-3         brightness
#   golem-keylight load FILE         a pattern file: lines "ALL #101010", "W #ff0000", "LEVEL 2", "# notes"
#   golem-keylight off
# The pattern is always kept per key (~/.config/golem-keylight/now.lights), even on a keyboard with one colour,
# so the same patterns work on a keyboard with a light per key. It says plainly what it could not show.
# Part of Golem: the keyboard's lights; MAP.md section 5.9.
import glob
import os
import subprocess
import sys

LEDS = "/sys/class/leds"
NOW = os.path.expanduser("~/.config/golem-keylight/now.lights")
NAMES = {"off": "#000000", "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#00ff00",
         "blue": "#0000ff", "yellow": "#ffff00", "orange": "#ff8800", "purple": "#8800ff", "pink": "#ff44aa",
         "cyan": "#00ffff", "grey": "#808080", "gray": "#808080"}


def colour(c):
    c = NAMES.get(c.lower(), c)
    c = c.lstrip("#")
    if len(c) == 3:
        c = "".join(x * 2 for x in c)
    if len(c) != 6 or any(x not in "0123456789abcdefABCDEF" for x in c):
        sys.exit(f"'{c}' is not a colour: use a name (red, white, off) or #rrggbb")
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def keyboard():
    """(folder, kind): kind is 'rgb' (one colour for the whole keyboard), 'mono' (brightness only) or None."""
    for d in sorted(glob.glob(os.path.join(LEDS, "*kbd_backlight*"))):
        if os.path.exists(os.path.join(d, "kbd_rgb_mode")):          # Asus TUF (asus-wmi)
            return d, "rgb"
        if os.path.exists(os.path.join(d, "multi_intensity")):        # other single-colour RGB keyboards
            return d, "multi"
        return d, "mono"
    return None, None


def read(d, f, default="0"):
    try:
        with open(os.path.join(d, f)) as h:
            return h.read().strip()
    except OSError:
        return default


def put(d, f, v):
    try:
        with open(os.path.join(d, f), "w") as h:
            h.write(str(v))
        return True
    except OSError as e:
        print(f"Could not change {f}: {e.strerror}")
        return False


def load(path):
    pat = {"LEVEL": "3"}
    try:
        with open(path) as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 2 and not line.lstrip().startswith("#"):    # "# ..." lines are notes
                    pat[parts[0].upper()] = parts[1]
    except OSError:
        pass
    return pat


def save(pat):
    os.makedirs(os.path.dirname(NOW), exist_ok=True)
    with open(NOW, "w") as f:
        for k, v in pat.items():
            f.write(f"{k} {v}\n")


def show(pat):
    d, kind = keyboard()
    if not d:
        print("This computer has no keyboard light that Golem can reach.")
        return 1
    level = max(0, min(3, int(pat.get("LEVEL", "3"))))
    keys = {k: colour(v) for k, v in pat.items() if k != "LEVEL"}
    rgb = keys.get("ALL") or (next(iter(keys.values())) if keys else (255, 255, 255))
    if len(set(keys.values())) > 1:
        print(f"This keyboard shows one colour for all keys, so it shows {'#%02x%02x%02x' % rgb}; "
              "the pattern per key is kept for a keyboard that can show it.")
    mx = int(read(d, "max_brightness", "3") or 3)
    on = rgb != (0, 0, 0) and level > 0
    ok = True
    if kind == "rgb":     # mode 0 = still light; "1" = keep it after restart
        ok = put(d, "kbd_rgb_mode", f"1 0 {rgb[0]} {rgb[1]} {rgb[2]} 0")
    elif kind == "multi":
        ok = put(d, "multi_intensity", f"{rgb[0]} {rgb[1]} {rgb[2]}")
    elif on:
        print("This keyboard has white light only: colours become brightness.")
        level = max(1, round(level * max(rgb) / 255))
    ok = put(d, "brightness", round(mx * level / 3) if on else 0) and ok
    subprocess.run(["logger", "-t", "golem", f"Keyboard light: {'#%02x%02x%02x' % rgb if on else 'off'}"], check=False)
    return 0 if ok else 1


def main(a):
    pat = load(NOW)
    if not a or a[0] == "what":
        d, kind = keyboard()
        print({None: "No keyboard light found.", "mono": f"White light, {read(d, 'max_brightness') if d else 0} steps of brightness.",
               "rgb": "One colour for the whole keyboard (Asus), and brightness.",
               "multi": "One colour for the whole keyboard, and brightness."}[kind])
        print("Patterns are kept per key either way:", NOW)
        return 0
    if a[0] == "all" and len(a) == 2:
        colour(a[1])
        pat = {"LEVEL": pat.get("LEVEL", "3"), "ALL": a[1]}
    elif a[0] == "key" and len(a) == 3:
        colour(a[2])
        pat[a[1].upper()] = a[2]
    elif a[0] == "level" and len(a) == 2 and a[1] in "0123":
        pat["LEVEL"] = a[1]
    elif a[0] == "load" and len(a) == 2:
        pat = load(a[1])
        for k, v in pat.items():
            if k != "LEVEL":
                colour(v)
    elif a[0] == "off":
        pat["LEVEL"] = "0"
    else:
        print("golem-keylight what | all COLOUR | key KEY COLOUR | level 0-3 | load FILE | off")
        return 2
    save(pat)
    return show(pat)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
