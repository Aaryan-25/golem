# golem-panel: the Control Panel (Super+Z). A game menu for the system. Keyboard only.
#   Q / E      previous / next group (SPELL, WEAVE, MIMIC, MEMORIES, TRUE NAME)
#   ↑ ↓        move        Enter / →  open or change        Esc / ←  back, or leave
#   A apply the waiting changes (your password, once)        X throw them away
#   F find anything        I switch the face (Shadow / Negative)
# Closing an app, volume, brightness, Wi-Fi, Bluetooth and the look change at once.
import json
import math
import os
import random
import socket
import subprocess
import tkinter as tk

THEMES = json.loads(os.environ["GOLEM_THEMES"])          # {"shadow": {...}, "negative": {...}}
SCHEMA = json.load(open("/etc/golem/settings-schema.json"))
APPS = "/var/lib/golem/apps"
KEYS = "/var/lib/golem/keys.conf"
SETTINGS = "/var/lib/golem/settings.conf"
LOOK = ("face", "effects", "motes", "night_light", "window_sand")
RUNES = os.environ.get("GOLEM_RUNES", "")                 # Golem's own carved letters (realm.nix)
FIELDS = ["zone", "internet", "camera", "sound", "usb", "nvidia", "ram", "cpu", "folder"]
CYCLE = {
    "zone": ["red", "offline", "yellow", "green"],
    "internet": ["never", "allowed"], "camera": ["never", "allowed"], "usb": ["never", "allowed"],
    "nvidia": ["never", "allowed"], "sound": ["off", "on"],
    "ram": ["512M", "1G", "1500M", "2G", "2500M", "3G", "4G", "6G"],
    "cpu": ["25%", "50%", "100%", "150%", "180%", "200%", "400%", "800%"],
}
EXPLAIN = {
    "zone": "RED: nothing, wiped on close.  OFFLINE: no internet, own folder.  YELLOW: internet, own folder.  GREEN: trusted, my files.",
    "internet": "May it use the internet? (RED and OFFLINE never can.)",
    "camera": "May it use the camera?", "usb": "May it see USB drives?",
    "nvidia": "May it use the NVIDIA card (the Asus)? For heavy work like training Echo. Never in RED.", "sound": "Sound and microphone.",
    "ram": "The most memory it may use.", "cpu": "The most processor it may use (100% = one core).",
    "folder": "Its folder, inside your home. Empty = ~/zones/<app>. Enter to type.",
}
# The groups and their pages, named by me (21-22 Nov 2026)
GROUPS = [
    ("SPELL", ["RUNNING", "STARTUP", "STORAGE", "SAVE SLOTS", "ABOUT"]),
    ("WEAVE", ["APPS", "KEYS", "DRIVERS", "NETWORK", "THE GATE", "SOUND & SCREEN", "POWER", "KEYBOARD"]),
    ("MIMIC", ["FACE", "COLOURS", "ANIMATIONS", "TEXT", "WINDOWS", "NIGHT LIGHT", "RED ALERT",
               "START SCREEN", "LOCK SCREEN", "WALLPAPER", "TRANSITIONS", "KEYBOARD LIGHT", "WAKING UP"]),
    ("MEMORIES", ["TRUTH LOG", "PRIVACY", "BACKUPS"]),
    ("TRUE NAME", ["ZONES", "ALL KEYS", "GOLEM"]),
]
# MIMIC pages still being made: what's there now, and what comes
IN_PROGRESS = {
    "COLOURS": [("Black and white", "the shadow realm", "Black ground, everything else white. I (or B in the Start panel) turns it over. Colours come later.")],
    "TEXT": [("Golem Runes", "my own carved letters", "Readable as English, cut like stone. Sizes and other letters come later.")],
    "START SCREEN": [("The picture on the right", "~/zones/settings/scenery.png", "Put any picture there (an avatar or scenery). Until then, a moon. Super+Escape opens the Start panel."),
                     ("Idle screen", "WEAVE > POWER", "After the idle time the tabs blow away and the picture stays.")],
    "LOCK SCREEN": [("None for now", None, "Decided 22 Nov 2026: Golem starts straight in. A way to lock comes later.")],
    "WALLPAPER": [("Plain black", None, "Animations or videos take its place later.")],
    "TRANSITIONS": [("Picture to picture", "on", "The Start panel, windows (WINDOWS) and these pages turn to sand that flies. More kinds later.")],
    "KEYBOARD LIGHT": [("The Asus keyboard's light", None, "Comes with the Asus.")],
    "WAKING UP": [("The sand gathers", None, "For now the sand gathers into the Start panel. The real waking-up animation is designed together, later.")],
}
CORE = ("dbus", "dbus-broker", "systemd-journald", "systemd-logind", "systemd-udevd", "NetworkManager",
        "polkit", "nix-daemon", "getty@tty1", "golem-netwatch", "golem-helper", "display-manager", "systemd-")
KINDS = ["all", "apps", "internet", "devices", "passwords", "settings", "system"]


def run(*cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=20).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def helper(req):
    s = socket.socket(socket.AF_UNIX)
    s.settimeout(120)
    try:
        s.connect("/run/golem-helper.sock")
        s.sendall((json.dumps(req) + "\n").encode())
        return s.makefile().readline().strip() or "ERROR no answer"
    except OSError as e:
        return f"ERROR the settings guard is not reachable ({e})"
    finally:
        s.close()


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


def load():
    apps = {}
    if os.path.isdir(APPS):
        for f in sorted(os.listdir(APPS)):
            if f.endswith(".conf"):
                apps[f[:-5]] = read_conf(f"{APPS}/{f}")
    keys = []
    for line in open(KEYS):
        parts = [p.strip() for p in line.split("|", 2)]
        if len(parts) == 3 and not line.startswith("#"):
            keys.append(parts)
    st = {k: v["default"] for k, v in SCHEMA.items()}
    st.update({k: v for k, v in read_conf(SETTINGS).items() if k in SCHEMA and v in SCHEMA[k]["values"]})
    return apps, keys, st


def mix(a, b, t):
    """a colour between a (t=0) and b (t=1)"""
    a, b = a.lstrip("#"), b.lstrip("#")
    c = [round(int(a[i:i + 2], 16) * (1 - t) + int(b[i:i + 2], 16) * t) for i in (0, 2, 4)]
    return "#%02x%02x%02x" % tuple(c)


def copy(x):
    return json.loads(json.dumps(x))


def laptop():
    """This computer, as it says it is: maker and model, processor, memory."""
    name = " ".join(open(f"/sys/class/dmi/id/{f}").read().strip() for f in ("sys_vendor", "product_name")
                    if os.path.exists(f"/sys/class/dmi/id/{f}"))
    cpu = next((line.split(":", 1)[1].strip() for line in open("/proc/cpuinfo") if line.startswith("model name")), "?")
    gb = round(int(open("/proc/meminfo").readline().split()[1]) / 1048576)
    return f"{name or '?'} · {cpu.replace('(R)', '').replace('(TM)', '').replace(' CPU', '')} · {gb} GB"


class Panel:
    def __init__(self, root):
        self.root = root
        self.saved_apps, self.saved_keys, self.saved_st = load()
        self.apps, self.keys, self.st = copy(self.saved_apps), copy(self.saved_keys), copy(self.saved_st)
        self.T = THEMES[self.st["face"]]
        self.group, self.pidx = 0, 0          # chosen group and page
        self.page = None                      # the open page (None = the page list has focus)
        self.app = None
        self.rows, self.sel, self.top = [], 0, 0
        self.mode = "pages"                   # pages | rows | text | keycapture | confirm | leaving
        self.msg = None
        self.kind = "all"
        self.anim = []                        # running animations (generators)
        self.busy = False
        self.queue = []                       # keys pressed during an animation, handled after it
        self.final = {}

        root.attributes("-fullscreen", True)
        self.W, self.H = root.winfo_screenwidth(), root.winfo_screenheight()
        self.size = max(11, min(20, self.H // 58))
        self.f = ("Golem Runes", self.size)
        self.fs = ("Golem Runes", max(9, self.size - 3))
        self.ft = ("Golem Runes", max(11, self.size + 1))
        self.LH = int(self.size * 2.2)
        self.c = tk.Canvas(root, width=self.W, height=self.H, bg=self.T["void"], highlightthickness=0)
        self.c.pack(fill="both", expand=True)
        self.motes = []
        self.make_motes()
        root.bind("<Key>", self.key)
        root.after(300, self.take_focus)
        self.draw()
        self.tick()

    def take_focus(self, n=4):
        self.root.focus_force()
        run("i3-msg", "-q", '[class="(?i)^golem-panel$"] focus')
        if n > 0:
            self.root.after(500, self.take_focus, n - 1)

    # ---------------------------------------------------------------- the realm behind
    def make_motes(self):
        self.c.delete("mote")
        self.motes = []
        n = {"sparse": 30, "normal": 60, "dense": 110}[self.st["motes"]] if self.st["effects"] == "on" else 0
        for _ in range(n):
            z = random.uniform(0.25, 1.0)
            x, y = random.uniform(0, self.W), random.uniform(0, self.H)
            r = 0.6 + 1.8 * z
            col = mix(self.T["void"], self.T["mist"] if z < 0.7 else self.T["pale"], 0.25 + 0.5 * z)
            i = self.c.create_oval(x - r, y - r, x + r, y + r, fill=col, outline="", tags="mote")
            self.motes.append([i, x, y, random.uniform(-0.25, 0.25) * z, random.uniform(-0.45, -0.1) * z, z])
        self.c.tag_lower("mote")

    def tick(self):
        for m in self.motes:
            i, x, y, vx, vy, z = m
            nx, ny = x + vx, y + vy
            if ny < -5:
                ny = self.H + 5
            if nx < -5:
                nx = self.W + 5
            elif nx > self.W + 5:
                nx = -5
            self.c.move(i, nx - x, ny - y)
            m[1], m[2] = nx, ny
        for a in list(self.anim):
            try:
                next(a)
            except StopIteration:
                self.anim.remove(a)
        self.root.after(33, self.tick)

    # ---------------------------------------------------------------- drawing
    def text(self, x, y, s, col, font=None, anchor="w"):
        i = self.c.create_text(x, y, text=s, fill=col, font=font or self.f, anchor=anchor, tags=("ui",))
        self.final[i] = col
        return i

    def rect(self, x0, y0, x1, y1, col):
        i = self.c.create_rectangle(x0, y0, x1, y1, fill=col, outline="", tags=("ui",))
        self.final[i] = col

    def draw(self, fade_in=False):
        T, W, H = self.T, self.W, self.H
        self.c.delete("ui")
        self.c.configure(bg=T["void"])
        self.final = {}
        M = int(W * 0.06)
        # title and group tabs
        self.text(M, int(H * 0.06), "GOLEM", T["mist"], self.fs)
        x = M
        for gi, (g, _) in enumerate(GROUPS):
            on = gi == self.group
            i = self.text(x, int(H * 0.11), g, T["pale"] if on else T["mist"], self.ft)
            bx = self.c.bbox(i)
            if on:
                ln = self.c.create_line(bx[0], bx[3] + 4, bx[2], bx[3] + 4, fill=T["pale"], tags=("ui",))
                self.final[ln] = T["pale"]
            x = bx[2] + int(self.size * 2.2)
        self.text(W - M, int(H * 0.11), "Q ‹    › E", T["mist"], self.fs, anchor="e")
        # left: the pages of the group
        y0 = int(H * 0.2)
        LX, RX, VX = M, M + int(W * 0.2), M + int(W * 0.58)
        for pi, p in enumerate(GROUPS[self.group][1]):
            on = pi == self.pidx
            y = y0 + pi * self.LH
            if on and self.mode == "pages":
                self.rect(LX - 10, y - self.LH // 2 + 2, RX - 30, y + self.LH // 2 - 2, T["shade"])
            self.text(LX + (16 if on else 0), y, p, T["pale"] if on else T["mist"])
            if on:
                self.text(LX, y, "◆", T["pale"], self.fs)
        # right: the open page
        vis = max(3, int(H * 0.6) // self.LH)
        if self.sel < self.top:
            self.top = self.sel
        if self.sel >= self.top + vis:
            self.top = self.sel - vis + 1
        if self.page:
            for ri, r in enumerate(self.rows[self.top:self.top + vis]):
                idx = self.top + ri
                y = y0 + ri * self.LH
                on = idx == self.sel and self.mode != "pages"
                if on:
                    self.rect(RX - 14, y - self.LH // 2 + 2, W - M + 10, y + self.LH // 2 - 2, T["shade"])
                    self.text(RX - 4, y, "›", T["pale"])
                actionable = r[2] is not None
                self.text(RX + 12, y, str(r[0])[:80], T["pale"] if on else (T["text"] if actionable else T["mist"]))
                if r[1] is not None:
                    self.text(VX, y, str(r[1]), T["pale"] if on else T["text"])
            if len(self.rows) > vis:
                self.text(W - M, y0 + vis * self.LH, f"{self.sel + 1} / {len(self.rows)}", T["mist"], self.fs, anchor="e")
            if self.rows and self.mode != "pages":
                r = self.rows[min(self.sel, len(self.rows) - 1)]
                if len(r) > 3 and r[3]:
                    self.text(M, int(H * 0.86), r[3], T["mist"], self.fs)
        # bottom line
        self.text(M, int(H * 0.92), self.footer(), T["pale"], self.fs)
        if fade_in:
            self.fade()

    def footer(self):
        if self.mode == "text":
            shown = "•" * len(self.buf) if self.secret else self.buf
            return f"{self.prompt}   {shown}▏"
        if self.msg:
            return self.msg
        base = "Q E groups    ↑↓ move    Enter open / change    Esc back    F find    I face"
        if self.changes():
            base += "        CHANGES WAITING:  A apply (password)    X throw away"
        return base

    def say(self, msg=None):
        self.msg = msg
        self.draw()

    # ---------------------------------------------------------------- animations: gather, melt, turn inside out
    def setfill(self, i, col):
        try:
            self.c.itemconfigure(i, fill=col)
        except tk.TclError:
            pass

    def fade(self, steps=6):
        items, void = dict(self.final), self.T["void"]
        for i in items:
            self.setfill(i, void)

        def go():
            for s in range(1, steps + 1):
                for i, col in items.items():
                    self.setfill(i, mix(void, col, s / steps))
                yield
        self.anim.append(go())

    def picture(self):
        """What the panel shows now, as a picture for the sand (half size): how far each thing stands out
        from the ground."""
        from PIL import Image, ImageDraw, ImageFont
        import tkinter.font as tkfont
        W2, H2 = self.W // 2, self.H // 2
        im = Image.new("L", (W2, H2), 0)
        d = ImageDraw.Draw(im)
        ground = sum(int(self.T["void"][i:i + 2], 16) for i in (1, 3, 5)) / 765
        fonts, sizes = {}, {}
        for i in self.c.find_withtag("ui"):
            col = self.final.get(i) or self.c.itemcget(i, "fill")
            if not col.startswith("#"):
                continue
            v = int(abs(sum(int(col[j:j + 2], 16) for j in (1, 3, 5)) / 765 - ground) * 255)
            xy = [c / 2 for c in self.c.coords(i)]
            kind = self.c.type(i)
            if kind == "text":
                spec = self.c.itemcget(i, "font")
                if spec not in sizes:
                    sizes[spec] = abs(tkfont.Font(font=spec).actual("size"))
                size = sizes[spec]
                if size not in fonts:
                    try:
                        fonts[size] = ImageFont.truetype(RUNES, max(6, int(size * 0.67)))
                    except OSError:
                        fonts[size] = ImageFont.load_default()
                anchor = {"w": "lm", "e": "rm", "center": "mm"}.get(self.c.itemcget(i, "anchor"), "lm")
                d.text((xy[0], xy[1]), self.c.itemcget(i, "text"), font=fonts[size], fill=v, anchor=anchor)
            elif kind == "rectangle":
                d.rectangle(xy, fill=v // 3)
            elif kind == "line":
                d.line(xy, fill=v)
        return im

    def sand_turn(self, change):
        """Picture to picture through the realm: the page now and the next page, as sand that flies."""
        rt = os.environ.get("XDG_RUNTIME_DIR") or f"/run/user/{os.getuid()}"
        a, b = os.path.join(rt, "golem-page-a.png"), os.path.join(rt, "golem-page-b.png")
        try:
            self.picture().save(a)
        except Exception:
            return False
        change()
        self.draw()
        try:
            self.picture().save(b)
            # the realm covers the screen with the old page's sand before Tk shows the new page underneath
            subprocess.run(["golem-realm", "page", a, b], timeout=3, capture_output=True)
        except Exception:
            pass
        return True

    def melt_then(self, change):
        """the old page turns to sand that flies into the new one (or, without the realm, melts and gathers)"""
        if self.st["effects"] == "on" and self.st.get("window_sand") == "on" and not self.busy and self.sand_turn(change):
            return
        if self.st["effects"] != "on" or self.busy:
            change()
            self.draw()
            return
        self.busy = True
        T = self.T
        bits = []
        for i in self.c.find_withtag("ui"):
            if self.c.type(i) != "text":
                continue
            bx = self.c.bbox(i)
            if not bx or bx[1] < self.H * 0.15 or bx[1] > self.H * 0.88:
                continue
            for _ in range(3):
                x, y = random.uniform(bx[0], bx[2]), random.uniform(bx[1], bx[3])
                p = self.c.create_oval(x - 1.2, y - 1.2, x + 1.2, y + 1.2, fill=T["pale"], outline="", tags="fx")
                bits.append([p, random.uniform(-1.5, 1.5), random.uniform(0.5, 3.0)])
        old = dict(self.final)

        def melt():
            for s in range(7):
                for i, col in old.items():
                    self.setfill(i, mix(col, T["void"], (s + 1) / 7))
                for b in bits:
                    self.c.move(b[0], b[1], b[2])
                    b[2] += 0.6
                    self.setfill(b[0], mix(T["pale"], T["void"], s / 7))
                yield
            self.c.delete("fx")
            change()
            self.draw()
            for i in self.final:
                self.setfill(i, T["void"])
            yield from self.gather()
            self.busy = False
            while self.queue and not self.busy:
                self.key(self.queue.pop(0))
        self.anim.append(melt())

    def gather(self):
        T = self.T
        targets = []
        for i in self.c.find_withtag("ui"):
            if self.c.type(i) == "text":
                bx = self.c.bbox(i)
                if bx:
                    targets.append(((bx[0] + bx[2]) / 2, (bx[1] + bx[3]) / 2))
        motes = []
        for tx, ty in targets[:40]:
            ang = random.uniform(0, 2 * math.pi)
            d = random.uniform(80, 260)
            sx, sy = tx + d * math.cos(ang), ty + d * math.sin(ang)
            p = self.c.create_oval(sx - 1.4, sy - 1.4, sx + 1.4, sy + 1.4, fill=T["pale"], outline="", tags="fx")
            motes.append([p, sx, sy, tx, ty])
        steps = 9
        final = dict(self.final)
        for s in range(1, steps + 1):
            t = 1 - (1 - s / steps) ** 2
            self.c.delete("tracker")
            for k, m in enumerate(motes):
                x = m[1] + (m[3] - m[1]) * t
                y = m[2] + (m[4] - m[2]) * t
                self.c.coords(m[0], x - 1.4, y - 1.4, x + 1.4, y + 1.4)
                if k % 3 == 0 and k + 1 < len(motes) and s < steps - 1:
                    n = motes[k + 1]
                    nx, ny = n[1] + (n[3] - n[1]) * t, n[2] + (n[4] - n[2]) * t
                    self.c.create_line(x, y, nx, ny, fill=mix(T["void"], T["mist"], 0.5), tags=("fx", "tracker"))
            for i, col in final.items():
                self.setfill(i, mix(T["void"], col, t))
            yield
        self.c.delete("fx")
        for i, col in final.items():
            self.setfill(i, col)

    def turn_face(self, face):
        """the realm turns inside out: a circle of the other face spreads from the middle"""
        new = THEMES[face]
        if self.st["effects"] != "on":
            self.T = new
            self.make_motes()
            self.draw()
            return
        cx, cy = self.W / 2, self.H / 2
        R = math.hypot(cx, cy) + 10
        circ = self.c.create_oval(cx, cy, cx, cy, fill=new["void"], outline=new["pale"], width=1, tags="fx")

        def go():
            for s in range(1, 15):
                r = R * (s / 14) ** 1.6
                self.c.coords(circ, cx - r, cy - r, cx + r, cy + r)
                self.c.tag_raise(circ)
                yield
            self.T = new
            self.c.delete("fx")
            self.make_motes()
            self.draw(fade_in=True)
        self.anim.append(go())

    # ---------------------------------------------------------------- state
    def changes(self):
        def plain(st):
            return {k: v for k, v in st.items() if k not in LOOK}
        return self.apps != self.saved_apps or self.keys != self.saved_keys or plain(self.st) != plain(self.saved_st)

    def pages(self):
        return GROUPS[self.group][1]

    def open_page(self, name, keep=False, animate=True, sel=None):
        def change():
            self.page = name
            self.rows = self.build(name)
            if not keep:
                self.sel, self.top = 0, 0
            if sel is not None:
                self.sel = sel
            self.sel = min(self.sel, max(0, len(self.rows) - 1))
            self.mode = "rows"
            self.msg = None
        if animate:
            self.melt_then(change)
        else:
            change()
            self.draw()

    def refresh(self):
        if self.page:
            self.rows = self.build(self.page)
            self.sel = min(self.sel, max(0, len(self.rows) - 1))
        self.draw()

    def build(self, name):
        return {
            "RUNNING": self.p_running, "STARTUP": self.p_startup, "STORAGE": self.p_storage,
            "SAVE SLOTS": self.p_slots, "ABOUT": self.p_about, "APPS": self.p_apps, "KEYS": self.p_keys,
            "DRIVERS": self.p_drivers, "NETWORK": self.p_network, "SOUND & SCREEN": self.p_sound,
            "POWER": self.p_power, "KEYBOARD": self.p_keyboard, "THE GATE": self.p_gate, "FACE": self.p_face, "RED ALERT": self.p_alerts,
            "ANIMATIONS": lambda: self.setting_rows("ANIMATIONS"), "WINDOWS": lambda: self.setting_rows("WINDOWS"),
            "NIGHT LIGHT": lambda: self.setting_rows("NIGHT LIGHT"),
            **{k: (lambda k=k: [(a, b, None, c) for a, b, c in IN_PROGRESS[k]] + [("IN PROGRESS", None, None, "This page is still being made.")])
               for k in IN_PROGRESS},
            "TRUTH LOG": self.p_truth, "PRIVACY": self.p_privacy, "BACKUPS": self.p_backups,
            "ZONES": self.p_zones, "ALL KEYS": self.p_allkeys, "GOLEM": self.p_golem, "CERTS": self.p_certs,
        }[name]()

    def setting_rows(self, page):
        rows = []
        for k, d in SCHEMA.items():
            if d["page"] == page:
                v = self.st[k]
                unit = d.get("unit", "")
                shown = v + (f" {unit}" if unit and v not in ("off", "never", "on") else "")
                if v != self.saved_st[k] and k not in LOOK:
                    shown += "   •"
                rows.append((d["label"], shown, ("setting", k), d["help"] + ("  (changes at once)" if k in LOOK else "")))
        return rows

    # ---------------------------------------------------------------- pages
    def p_running(self):
        rows = []
        units = run("systemctl", "--user", "list-units", "--type=scope", "--state=active", "--plain", "--no-legend", "zone-*").split()
        for u in [x for x in units if x.startswith("zone-")]:
            desc = run("systemctl", "--user", "show", "-p", "Description", "--value", u).strip()
            mem = run("systemctl", "--user", "show", "-p", "MemoryCurrent", "--value", u).strip()
            mem = f"{int(mem) // 1048576} MB" if mem.isdigit() else ""
            rows.append((desc.split("|")[0].strip(), mem, ("close", u, desc), "Enter: close this app (asks first).   " + desc.split("|", 1)[-1].strip()))
        return rows or [("No apps are running in zones.", None, None, "Apps opened with Alt+Space run in their zone and show up here.")]

    def p_startup(self):
        rows = []
        out = run("systemctl", "list-units", "--type=service,timer", "--state=active", "--plain", "--no-legend")
        for line in out.splitlines():
            parts = line.split(None, 4)
            if len(parts) < 5:
                continue
            unit, desc = parts[0], parts[4]
            core = unit.startswith(CORE)
            rows.append((unit.rsplit(".", 1)[0], "running" + ("  (core)" if core else ""), ("service", unit, core),
                         desc + (".  CORE: stopping it can break Golem." if core else ".  Enter: stop it (your password).")))
        return rows or [("Nothing listed.", None, None)]

    def p_storage(self):
        df = run("df", "-h", "--output=used,size,pcent", "/").splitlines()
        used = df[1].split() if len(df) > 1 else ["?", "?", "?"]
        rows = [("Golem's drive", f"{used[0]} of {used[1]} used ({used[2]})", None, "The whole pendrive.")]
        home = os.path.expanduser("~")
        for d in ["documents", "projects", "media", "zones"]:
            sz = run("du", "-sh", f"{home}/{d}").split()
            rows.append((f"   {d}", sz[0] if sz else "?", None, f"Your {d} folder."))
        rows.append(("Clean unused pieces", None, ("clean",),
                     "Enter: removes pieces no version of Golem uses any more (your password). Your files are never touched."))
        return rows

    def p_slots(self):
        out = run("nix-env", "-p", "/nix/var/nix/profiles/system", "--list-generations")
        gens = [line.split() for line in reversed(out.splitlines()) if line.split()]
        rows = []
        for n, g in enumerate(gens):
            num, date = g[0], " ".join(g[1:3])
            cur = "  (now)" if "(current)" in g else ""
            if n < 3:
                rows.append((f"Version {num}{cur}", date, None, "One of the newest 3: always kept. Hold Shift while Golem starts to pick an older version."))
            else:
                rows.append((f"Version {num}", date, ("delete-version", num), "Enter: delete this older version (your password)."))
        return rows or [("No versions found.", None, None)]

    def p_about(self):
        mem = run("free", "-m").splitlines()
        used = mem[1].split() if len(mem) > 1 else []
        bat = run("sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null").strip()
        temp = run("sh", "-c", "cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | sort -n | tail -1").strip()
        ver = open("/etc/golem/version").read().strip()[:7] if os.path.exists("/etc/golem/version") else "?"
        up = run("uptime", "-p").strip().replace("up ", "")
        return [("Golem version", ver, None, "To update: open a terminal (Alt+Enter) and type golem-update."),
                ("Memory used", f"{used[2]} of {used[1]} MB" if used else "?", None),
                ("Battery", f"{bat}%" if bat else "no battery", None),
                ("Hottest part", f"{int(temp) // 1000} °C" if temp.isdigit() else "?", None),
                ("On for", up or "?", None),
                ("Laptop", laptop(), None)]

    def p_apps(self):
        if self.app:
            c = self.apps[self.app]
            rows = [(f"‹ {self.app}", None, ("back",), "Enter or Esc: back to the list of apps.")]
            for k in FIELDS:
                v = c.get(k, "")
                shown = v.upper() if k == "zone" else (v or "default")
                if self.saved_apps.get(self.app, {}).get(k) != v:
                    shown += "   •"
                rows.append((k, shown, ("field", k), EXPLAIN[k]))
            rows.append(("Remove this app's settings", None, ("remove",), "It will ask its zone again the next time it starts."))
            return rows
        rows = [(name, f"{c.get('zone', '?').upper():<9} internet {c.get('internet', '?')}", ("app", name),
                 "Enter: change what this app may do.") for name, c in self.apps.items()]
        return rows or [("No apps yet. Open one with Alt+Space; it asks its zone once.", None, None)]

    def p_keys(self):
        return [(label, combo + ("   •" if [combo, label, cmd] not in self.saved_keys else ""), ("key", i),
                 "Enter, then press the new keys. Esc cancels.") for i, (combo, label, cmd) in enumerate(self.keys)]

    def p_drivers(self):
        rows = self.setting_rows("DRIVERS")
        missing = []
        for block in run("lspci", "-k").split("\n\n"):
            lines = block.strip().splitlines()
            if lines and not any("Kernel driver in use" in ln for ln in lines):
                missing.append(lines[0].split(" ", 1)[-1])
        for m in missing[:8]:
            rows.append((f"No driver: {m[:46]}", None, None,
                         "This part has no driver loaded. Golem carries only what this laptop needs; it can be added to the recipe if you want it."))
        if not missing:
            rows.append(("Every part of the laptop has its driver", None, None, "The driver finder found nothing missing."))
        return rows

    def p_network(self):
        wifi = run("nmcli", "radio", "wifi").strip() or "?"
        bt = "on" if "Powered: yes" in run("bluetoothctl", "show") else "off"
        now = run("date", "+%d %b %Y  %H:%M").strip()
        net = run("nmcli", "-t", "-f", "NAME", "connection", "show", "--active").strip().splitlines()
        return [("Wi-Fi", wifi, ("wifi",), "Enter: turn Wi-Fi on or off (at once). Super+W chooses a network."),
                ("Connected to", net[0] if net else "nothing", None),
                ("Bluetooth", bt, ("bluetooth", bt), "Enter: turn Bluetooth on or off (at once). The driver itself is in DRIVERS."),
                ("Hidden PC name and MAC address", "on", None, "Networks see a new random address each time and no PC name."),
                ("Clock", now, None, "The clock never sets itself over the internet."),
                ("Set the clock from the internet, once", None, ("clock-once",), "Enter: your password, then one question to a time server (Wi-Fi must be on). It's logged."),
                ("Set the clock by hand", None, ("clock-set",), "Enter: type the time like 2026-11-22 02:30, then your password.")]

    def p_gate(self):
        """The Gate: the only way to the internet. Its switch, and every decision I made, each one undoable."""
        status = run("golem-gate", "status").strip()
        mode = "OFF" if status.startswith("mode off") else ("ON" if status.startswith("mode") else "not running")
        hidden = status.startswith("mode hidden")
        if hidden:
            mode = "ON"
        rows = [("The Gate", mode, ("do", ["golem-gate", "on" if mode == "OFF" else "off"]),
                 "Enter: OFF stops everything going out at once; ON lets apps ask me, site by site."),
                ("HIDDEN (through Tor)", "on" if hidden else "off", ("do", ["golem-gate", "on" if hidden else "hidden"]),
                 "Enter: on/off. Sites can't see where you are; your Wi-Fi can't see which sites; .onion sites open. "
                 "But your Wi-Fi sees that you use Tor, a site you log in to knows it's you, and downloads can give you away."),
                ("Asking", "ready" if "asking ready" in status else "not running", None,
                 "The question (ONCE / ALWAYS / NEVER / any site for this app) appears on the screen."),
                ("Written down", "truth log + /var/lib/golem-gate/feed.jsonl", None,
                 "One plain sentence and one line of JSON per connection (for my AI). Nothing inside them is read.")]
        for line in run("golem-gate", "rules").splitlines():
            parts = line.split()
            if len(parts) != 4:
                continue
            app, zone, site, answer = parts
            what = "any site" if site == "*" else site
            rows.append((f"{app} ({zone})  {what}", answer, ("do", ["golem-gate", "forget", app, zone, site]),
                         "Enter: take this decision back; the Gate will ask again next time."))
        if len(rows) == 4:
            rows.append(("No decisions yet", None, None, "ALWAYS and NEVER answers show up here."))
        return rows

    def p_sound(self):
        vol = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").strip().replace("Volume: ", "")
        mic = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@").strip()
        bri = run("brightnessctl", "-m").split(",")
        return [("Volume up", vol, ("do", ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%+"]), "At once."),
                ("Volume down", None, ("do", ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"]), "At once."),
                ("Sound on / off", None, ("do", ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]), "At once."),
                ("Microphone on / off", "muted" if "MUTED" in mic else "on", ("do", ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"]),
                 "At once. To switch it off for good, see DRIVERS."),
                ("Brighter", bri[3] if len(bri) > 3 else None, ("do", ["brightnessctl", "-q", "set", "+10%"]), "At once."),
                ("Dimmer", None, ("do", ["brightnessctl", "-q", "set", "10%-"]), "At once.")] + self.setting_rows("SCREEN")

    def p_power(self):
        bat = run("sh", "-c", "cat /sys/class/power_supply/BAT*/capacity /sys/class/power_supply/BAT*/status 2>/dev/null").split()
        health = run("sh", "-c", "cd /sys/class/power_supply/BAT* 2>/dev/null && echo $(( $(cat energy_full 2>/dev/null || cat charge_full) * 100 / $(cat energy_full_design 2>/dev/null || cat charge_full_design) ))").strip()
        limit = run("sh", "-c", "ls /sys/class/power_supply/BAT*/charge_control_end_threshold 2>/dev/null").strip()
        rows = [("Battery", " ".join(bat) if bat else "no battery", None),
                ("Battery health", f"{health}% of new" if health.isdigit() else "?", None, "How much it holds compared with when it was new.")]
        rows += self.setting_rows("POWER")
        if not limit:
            rows.append(("Charge limit from Golem", "not allowed by this laptop", None,
                         "Set it in the BIOS: F2 > Power Management > Primary Battery Charge Configuration > Custom."))
        return rows

    def p_keyboard(self):
        return self.setting_rows("KEYBOARD")

    def p_face(self):
        return self.setting_rows("FACE")

    def p_alerts(self):
        return self.setting_rows("RED ALERT") + [("Show a test alert", None, ("test-alert",), "Enter: shows the red alert now.")]

    def p_truth(self):
        out = run("golem-truth", "--text", *(["--kind", self.kind] if self.kind != "all" else []))
        lines = out.splitlines()[-300:]
        rows = [("Show", self.kind, ("kind",), "Enter: show only apps, internet, devices, passwords, settings or system.")]
        return rows + ([(ln, None, None, ln) for ln in lines] or [("Nothing yet.", None, None)])

    def p_privacy(self):
        certs = run("sh", "-c", "grep -c 'BEGIN CERTIFICATE' /etc/ssl/certs/ca-certificates.crt").strip()
        return self.setting_rows("PRIVACY") + [
            ("Telemetry", "none", None, "Golem sends nothing anywhere. Every connection is in the truth log."),
            ("Sharing", "none", None, "Nothing listens for connections from outside; the firewall drops them."),
            ("History", "none kept", None, "No recent files and no searches are remembered."),
            ("Internet clock", "off", None, "The clock only changes when you say so (NETWORK)."),
            ("Updates", "only when you run golem-update", None, "It always shows what will change and asks first."),
            ("Hidden PC name and MAC address", "on", None),
            ("Trusted certificates", certs, ("certs",), "Enter: see who they are. Distrusting one comes in a later version."),
            ("Software comes from", "nixpkgs, signatures checked", None, "Ready-built from cache.nixos.org, only when you update."),
        ]

    def p_certs(self):
        out = run("sh", "-c", "awk '/^# /{print substr($0,3)}' /etc/ssl/certs/ca-certificates.crt | head -200")
        rows = [("‹ back", None, ("privacy",), "Enter or Esc: back.")]
        return rows + [(ln[:70], None, None, ln) for ln in out.splitlines() if ln.strip()]

    def p_backups(self):
        rows = [("Save a backup now", None, ("backup-save",), "Saves app settings, keys, look and other settings under a name (your password).")]
        folder = "/var/lib/golem/backups"
        for f in sorted(os.listdir(folder)) if os.path.isdir(folder) else []:
            if f.endswith(".tar"):
                rows.append((f"Load '{f[:-4]}'", None, ("backup-load", f[:-4]), "Enter: puts these settings back (your password)."))
        return rows

    def p_zones(self):
        return [("RED", "nothing", None, "No files, no internet, no camera, sound or USB. Wiped when it closes. For anything you don't trust."),
                ("OFFLINE", "own folder, no internet", None, "Sees only its folder in ~/zones. For documents, media, tools."),
                ("YELLOW", "internet, own folder", None, "Internet, but never your files. Downloads stay in its folder until you move them."),
                ("GREEN", "trusted", None, "Your files; internet, camera and USB only if allowed. The Control Panel runs here."),
                ("BLUE", "later", None, "For your own offline AI."),
                ("Known gap", "windows can see windows", None, "On this desktop any app with a window can see other windows. Wayland, a later step, closes it.")]

    def p_allkeys(self):
        return [(label, combo, None, label) for combo, label, _ in self.keys]

    def p_golem(self):
        return [("Private", None, None, "No app touches a file or permission you didn't give it. Nothing updates itself. All traffic is visible."),
                ("Clean", None, None, "No bloat, nothing you didn't ask for, no process you can't stop."),
                ("Usable", None, None, "Designed around your needs."),
                ("The Control Panel reigns supreme", None, None, "Settings change only here (or with your password), never by an app."),
                ("Truthful", None, None, "It does only what you say, and the truth log shows what it did.")]

    # ---------------------------------------------------------------- actions
    def act(self):
        if not self.rows:
            return
        a = self.rows[self.sel][2]
        if not a:
            return
        kind = a[0]
        if kind == "close":
            name = a[2].split("|")[0].strip()

            def close():
                run("systemctl", "--user", "stop", a[1])
                run("logger", "-t", "golem", f"Closed from the Control Panel: {name}")
                self.refresh()
            self.confirm(f"Close {name}?   Enter = yes    Esc = no", close)
        elif kind == "app":
            self.app = a[1]
            self.open_page("APPS")
        elif kind == "back":
            self.app = None
            self.open_page("APPS")
        elif kind == "field":
            k = a[1]
            c = self.apps[self.app]
            if k == "folder":
                def folder(v):
                    c["folder"] = v.strip()
                    self.refresh()
                self.ask(f"Folder for {self.app} (e.g. ~/projects/photos), empty = default:", c.get("folder", ""), folder)
                return
            vals = CYCLE[k]
            cur = c.get(k)
            c[k] = vals[(vals.index(cur) + 1) % len(vals)] if cur in vals else vals[0]
            self.refresh()
        elif kind == "remove":
            def remove():
                self.apps.pop(self.app)
                self.app = None
                self.open_page("APPS")
            self.confirm(f"Remove the settings of {self.app}?   Enter = yes    Esc = no", remove)
        elif kind == "key":
            self.mode = "keycapture"
            self.capture = a[1]
            self.say(f"Press the new keys for: {self.keys[a[1]][1]}    (Esc cancels)")
        elif kind == "setting":
            self.change_setting(a[1])
        elif kind == "wifi":
            r = helper({"do": "wifi", "on": run("nmcli", "radio", "wifi").strip() != "enabled"})
            self.refresh()
            self.say(None if r == "OK" else r)
        elif kind == "bluetooth":
            r = helper({"do": "bluetooth", "on": a[1] != "on"})
            self.refresh()
            self.say(None if r == "OK" else r)
        elif kind == "clock-once":
            self.ask("Your password, to set the clock from the internet once:", "",
                     lambda pw: self.admin({"do": "clock-once", "password": pw}, "Clock set."), secret=True)
        elif kind == "clock-set":
            def when(t):
                self.ask("Your password, to set the clock:", "",
                         lambda pw: self.admin({"do": "clock-set", "time": t.strip(), "password": pw}, "Clock set."), secret=True)
            self.ask("The time, like 2026-11-22 02:30:", run("date", "+%Y-%m-%d %H:%M").strip(), when)
        elif kind == "service":
            unit, core = a[1], a[2]
            warn = "  CORE: Golem may stop working!" if core else ""
            self.confirm(f"Stop {unit}?{warn}   Enter = yes    Esc = no",
                         lambda: self.ask("Your password, to stop it:", "",
                                          lambda pw: self.admin({"do": "service", "unit": unit, "op": "stop", "password": pw}, f"{unit} stopped."),
                                          secret=True))
        elif kind == "delete-version":
            self.confirm(f"Delete version {a[1]}?   Enter = yes    Esc = no",
                         lambda: self.ask("Your password:", "",
                                          lambda pw: self.admin({"do": "delete-version", "version": a[1], "password": pw}, "Deleted."), secret=True))
        elif kind == "clean":
            self.ask("Your password, to clean unused pieces:", "",
                     lambda pw: self.admin({"do": "clean", "password": pw}, "Cleaned."), secret=True)
        elif kind == "backup-save":
            def named(name):
                self.ask("Your password:", "",
                         lambda pw: self.admin({"do": "backup-save", "name": name.strip(), "password": pw}, "Backup saved."), secret=True)
            self.ask("A name for this backup (letters, numbers, - _):", "", named)
        elif kind == "backup-load":
            self.ask(f"Your password, to load '{a[1]}':", "",
                     lambda pw: self.reload_after(self.admin({"do": "backup-load", "name": a[1], "password": pw}, "Backup loaded.")), secret=True)
        elif kind == "test-alert":
            subprocess.Popen(["golem-alert", "This is a test of the red alert."])
        elif kind == "kind":
            self.kind = KINDS[(KINDS.index(self.kind) + 1) % len(KINDS)]
            self.refresh()
        elif kind == "certs":
            self.open_page("CERTS")
        elif kind == "privacy":
            self.open_page("PRIVACY")
        elif kind == "do":
            run(*a[1])
            self.refresh()

    def change_setting(self, k):
        vals = SCHEMA[k]["values"]
        self.st[k] = vals[(vals.index(self.st[k]) + 1) % len(vals)]
        if k not in LOOK:
            self.refresh()
            return
        res = helper({"do": "look", "settings": {k: self.st[k]}})
        if res != "OK":
            self.st[k] = self.saved_st[k]
            self.refresh()
            self.say(res.replace("ERROR ", "Not changed: "))
            return
        self.saved_st[k] = self.st[k]
        run("golem-session-apply")
        if k == "face":
            self.turn_face(self.st[k])
            return
        if k in ("effects", "motes"):
            self.make_motes()
        self.refresh()

    def admin(self, req, done):
        self.say("Working…")
        self.root.update()
        r = helper(req)
        self.refresh()
        self.say(done + "  It's in the truth log." if r.startswith("OK") else r.replace("ERROR ", "Not done: "))
        return r

    def reload_after(self, r):
        if r.startswith("OK"):
            self.saved_apps, self.saved_keys, self.saved_st = load()
            self.apps, self.keys, self.st = copy(self.saved_apps), copy(self.saved_keys), copy(self.saved_st)
            run("golem-session-apply")
            run("i3-msg", "-q", "reload")
            self.refresh()

    def confirm(self, text, then):
        self.mode = "confirm"
        self.confirm_then = then
        self.say(text)

    def ask(self, prompt, value, then, secret=False):
        if self.mode in ("pages", "rows"):
            self.back_mode = self.mode
        elif not hasattr(self, "back_mode") or self.back_mode not in ("pages", "rows"):
            self.back_mode = "rows" if self.page else "pages"
        self.mode = "text"
        self.prompt, self.buf, self.secret, self.then = prompt, value, secret, then
        self.msg = None
        self.draw()

    def apply(self):
        def go(pw):
            req = {"do": "apply", "password": pw, "apps": self.apps,
                   "keys": self.keys if self.keys != self.saved_keys else [],
                   "settings": {k: v for k, v in self.st.items() if v != self.saved_st[k] and k not in LOOK}}
            r = helper(req)
            if r == "OK":
                self.reload_after("OK")
                self.say("Applied. Every change is in the truth log.")
            else:
                self.say(r.replace("ERROR ", "Not applied: "))
        self.ask("Your password, to apply the changes:", "", go, secret=True)

    def discard(self):
        self.apps, self.keys, self.st = copy(self.saved_apps), copy(self.saved_keys), copy(self.saved_st)
        if self.app not in self.apps:
            self.app = None
        self.refresh()
        self.say("Changes thrown away.")

    def find(self, text):
        text = text.lower().strip()
        if not text:
            return
        for gi, (_, pages) in enumerate(GROUPS):
            for pi, p in enumerate(pages):
                rows = self.build(p)
                for ri, r in enumerate(rows):
                    if text in p.lower() or text in str(r[0]).lower() or (len(r) > 3 and r[3] and text in r[3].lower()):
                        self.group, self.pidx, self.app = gi, pi, None
                        self.open_page(p, sel=0 if text in p.lower() else ri)
                        return
        self.say(f"Nothing found for '{text}'.")

    def leave(self):
        if self.changes():
            self.mode = "leaving"
            self.say("Changes are waiting.   A apply    X throw away and leave    Esc stay")
            return
        self.root.destroy()

    def switch_group(self, d):
        def change():
            self.group = (self.group + d) % len(GROUPS)
            self.pidx, self.page, self.app, self.mode, self.msg = 0, None, None, "pages", None
        self.melt_then(change)

    # ---------------------------------------------------------------- keyboard
    def key(self, e):
        k = e.keysym
        if self.mode == "text":
            if k == "Return":
                v = self.buf
                self.mode = self.back_mode
                self.then(v)
                if self.mode != "text":
                    self.draw()
            elif k == "Escape":
                self.mode = self.back_mode
                self.say(None)
            elif k == "BackSpace":
                self.buf = self.buf[:-1]
                self.draw()
            elif e.char and e.char.isprintable():
                self.buf += e.char
                self.draw()
            return
        if self.busy:
            self.queue.append(e)
            return
        if self.mode == "keycapture":
            if k == "Escape":
                self.mode = "rows"
                self.say(None)
                return
            if k in ("Super_L", "Super_R", "Alt_L", "Alt_R", "Control_L", "Control_R", "Shift_L", "Shift_R"):
                return
            mods = [n for bit, n in ((0x40, "Super"), (0x8, "Alt"), (0x4, "Ctrl"), (0x1, "Shift")) if e.state & bit]
            combo = "+".join(mods + [k])
            clash = [lab for c, lab, _ in self.keys if c.lower() == combo.lower()]
            self.mode = "rows"
            if clash:
                self.say(f"{combo} is already used for: {clash[0]}. Nothing changed.")
                return
            self.keys[self.capture][0] = combo
            self.refresh()
            self.say(None)
            return
        if self.mode == "confirm":
            self.mode = "rows" if self.page else "pages"
            self.msg = None
            if k == "Return":
                self.confirm_then()
            if self.mode != "text":
                self.draw()
            return
        if self.mode == "leaving":
            self.mode = "rows" if self.page else "pages"
            self.msg = None
            if k in ("a", "A"):
                self.apply()
            elif k in ("x", "X"):
                self.root.destroy()
            else:
                self.draw()
            return
        self.msg = None
        if k in ("a", "A") and self.changes():
            self.apply()
        elif k in ("x", "X") and self.changes():
            self.discard()
        elif k in ("q", "Q"):
            self.switch_group(-1)
        elif k in ("e", "E"):
            self.switch_group(1)
        elif k in ("f", "F"):
            self.ask("Find:", "", self.find)
        elif k in ("i", "I"):
            new = "negative" if self.st["face"] == "shadow" else "shadow"
            if helper({"do": "look", "settings": {"face": new}}) == "OK":
                self.st["face"] = self.saved_st["face"] = new
                run("golem-session-apply")
                self.turn_face(new)
        elif self.mode == "pages":
            if k in ("Up", "Down"):
                self.pidx = max(0, min(len(self.pages()) - 1, self.pidx + (-1 if k == "Up" else 1)))
                self.draw()
            elif k in ("Return", "Right"):
                self.app = None
                self.open_page(self.pages()[self.pidx])
            elif k == "Escape":
                self.leave()
        elif self.mode == "rows":
            if k in ("Up", "Down", "Prior", "Next"):
                step = {"Up": -1, "Down": 1, "Prior": -10, "Next": 10}[k]
                self.sel = max(0, min(len(self.rows) - 1, self.sel + step))
                self.draw()
            elif k in ("Return", "Right"):
                self.act()
            elif k in ("Escape", "Left"):
                if self.page == "APPS" and self.app:
                    self.app = None
                    self.open_page("APPS")
                elif self.page == "CERTS":
                    self.open_page("PRIVACY")
                else:
                    def change():
                        self.page, self.mode, self.rows = None, "pages", []
                    self.melt_then(change)


def main():
    root = tk.Tk(className="golem-panel")
    root.title("Control Panel")
    Panel(root)
    root.mainloop()


if __name__ == "__main__":
    main()
