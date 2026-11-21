# golem-panel: the Control Panel (Super+Z). Full screen, keyboard only.
# Pages on the left, the chosen page on the right.  Up/Down move, Enter opens or changes,
# Esc goes back or leaves.  Changes are made on a copy: A applies them (your password, once),
# X throws them away.  Closing an app, volume and brightness happen at once.
import json
import os
import socket
import subprocess
import tkinter as tk

T = json.loads(os.environ["GOLEM_THEME"])
APPS = "/var/lib/golem/apps"
KEYS = "/var/lib/golem/keys.conf"
FIELDS = ["zone", "internet", "camera", "sound", "usb", "ram", "cpu", "folder"]
CYCLE = {
    "zone": ["red", "offline", "yellow", "green"],
    "internet": ["never", "allowed"], "camera": ["never", "allowed"], "usb": ["never", "allowed"],
    "sound": ["off", "on"],
    "ram": ["512M", "1G", "1500M", "2G", "2500M", "3G"],
    "cpu": ["25%", "50%", "100%", "150%", "180%", "200%"],
}
EXPLAIN = {
    "zone": "RED: nothing, wiped on close.  OFFLINE: no internet, own folder.  YELLOW: internet, own folder.  GREEN: trusted, my files.",
    "internet": "May it use the internet? (RED and OFFLINE never can.)",
    "camera": "May it use the camera?", "usb": "May it see USB drives?", "sound": "Sound and microphone.",
    "ram": "Most memory it may use.", "cpu": "Most processor it may use (100% = one core).",
    "folder": "Its folder, inside your home. Empty = ~/zones/<app>. Enter to type.",
}


def run(*cmd):
    return subprocess.run(cmd, capture_output=True, text=True).stdout


def helper(req):
    s = socket.socket(socket.AF_UNIX)
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
    for line in open(path):
        if "=" in line:
            k, v = line.rstrip("\n").split("=", 1)
            out[k] = v
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
    return apps, keys


class Panel:
    PAGES = ["RUNNING", "APPS", "KEYS", "NETWORK", "SOUND & SCREEN", "TRUTH LOG", "ABOUT"]

    def __init__(self, root):
        self.root = root
        self.saved_apps, self.saved_keys = load()
        self.apps = json.loads(json.dumps(self.saved_apps))
        self.keys = [list(k) for k in self.saved_keys]
        self.page = None        # which page is open on the right
        self.app = None         # the app being edited on the APPS page
        self.mode = "pages"     # pages | rows | password | keycapture | text | confirm
        self.rows = []          # (label, value, action) for the right side
        self.confirm_action = None

        root.configure(bg=T["void"])
        root.attributes("-fullscreen", True)
        big = ("DejaVu Sans", 13)
        self.title = tk.Label(root, text="GOLEM  /  CONTROL PANEL", fg=T["mist"], bg=T["void"],
                              font=("DejaVu Sans", 11), anchor="w")
        self.title.pack(fill="x", padx=40, pady=(30, 20))
        body = tk.Frame(root, bg=T["void"])
        body.pack(fill="both", expand=True, padx=40)
        opts = dict(bg=T["void"], fg=T["mist"], selectbackground=T["shade"], selectforeground=T["pale"],
                    highlightthickness=0, borderwidth=0, activestyle="none", font=big)
        self.left = tk.Listbox(body, width=18, exportselection=False, **opts)
        self.left.pack(side="left", fill="y")
        self.right = tk.Listbox(body, exportselection=False, **opts)
        self.right.pack(side="left", fill="both", expand=True, padx=(40, 0))
        self.help = tk.Label(root, text="", fg=T["mist"], bg=T["void"], font=("DejaVu Sans", 11), anchor="w",
                             justify="left")
        self.help.pack(fill="x", padx=40, pady=(10, 4))
        self.foot = tk.Label(root, text="", fg=T["pale"], bg=T["void"], font=("DejaVu Sans", 11), anchor="w")
        self.foot.pack(fill="x", padx=40, pady=(0, 30))
        self.entry = tk.Entry(root, bg=T["shade"], fg=T["pale"], insertbackground=T["pale"],
                              relief="flat", font=big)
        for p in self.PAGES:
            self.left.insert("end", "  " + p)
        self.left.selection_set(0)
        root.bind("<Key>", self.key)
        self.left.focus_set()
        self.status()

    # ---- helpers ----
    def changes(self):
        return self.apps != self.saved_apps or self.keys != [list(k) for k in self.saved_keys]

    def status(self, msg=None):
        base = "↑↓ move    Enter open / change    Esc back"
        if self.changes():
            base += "        CHANGES WAITING:  A apply (your password)    X throw away"
        self.foot.configure(text=msg or base)

    def sel(self, box):
        s = box.curselection()
        return s[0] if s else 0

    def move(self, box, d):
        i = max(0, min(box.size() - 1, self.sel(box) + d))
        box.selection_clear(0, "end")
        box.selection_set(i)
        box.see(i)
        if box is self.right and self.rows:
            self.help.configure(text=self.rows[i][3] if len(self.rows[i]) > 3 else "")

    def show(self, rows, keep=False):
        old = self.sel(self.right)
        self.rows = rows
        self.right.delete(0, "end")
        for r in rows:
            label, value = r[0], r[1]
            self.right.insert("end", f"  {label:<34}{value}" if value is not None else f"  {label}")
        i = min(old, len(rows) - 1) if keep else 0
        if rows:
            self.right.selection_set(max(i, 0))
            self.help.configure(text=rows[max(i, 0)][3] if len(rows[max(i, 0)]) > 3 else "")

    # ---- pages ----
    def open_page(self, name, keep=False):
        self.page = name
        build = {"RUNNING": self.p_running, "APPS": self.p_apps, "KEYS": self.p_keys, "NETWORK": self.p_network,
                 "SOUND & SCREEN": self.p_sound, "TRUTH LOG": self.p_truth, "ABOUT": self.p_about}[name]
        self.show(build(), keep)

    def p_running(self):
        rows = []
        units = run("systemctl", "--user", "list-units", "--type=scope", "--state=active", "--plain",
                    "--no-legend", "zone-*").split()
        for u in [x for x in units if x.startswith("zone-")]:
            desc = run("systemctl", "--user", "show", "-p", "Description", "--value", u).strip()
            mem = run("systemctl", "--user", "show", "-p", "MemoryCurrent", "--value", u).strip()
            mem = f"{int(mem) // 1048576} MB" if mem.isdigit() else ""
            rows.append((desc.split("|")[0].strip(), mem, ("close", u, desc), "Enter: close this app (asks first)."))
        return rows or [("No apps are running in zones.", None, None)]

    def p_apps(self):
        if self.app:
            c = self.apps[self.app]
            rows = [(f"‹ {self.app}", None, ("back",), "Enter or Esc: back to the list of apps.")]
            for k in FIELDS:
                v = c.get(k, "")
                shown = v.upper() if k == "zone" else (v or "default")
                rows.append((k, shown, ("field", k), EXPLAIN[k]))
            rows.append(("Remove this app's settings", None, ("remove",), "It will ask its zone again next time it starts."))
            return rows
        rows = [(name, f"{c.get('zone', '?').upper():<9} internet {c.get('internet', '?')}", ("app", name),
                 "Enter: change what this app may do.") for name, c in self.apps.items()]
        return rows or [("No apps yet. Open one with Alt+Space; it asks its zone once.", None, None)]

    def p_keys(self):
        return [(label, combo, ("key", i), "Enter, then press the new keys. Esc cancels.")
                for i, (combo, label, _) in enumerate(self.keys)]

    def p_network(self):
        on = run("nmcli", "radio", "wifi").strip() or "unknown (Super+N)"
        return [("Wi-Fi", on, ("wifi",), "Enter: turn Wi-Fi on or off (happens at once).")]

    def p_sound(self):
        vol = run("wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@").strip()
        bri = run("brightnessctl", "-m").split(",")
        return [("Volume up", vol, ("do", ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SINK@", "5%+"])),
                ("Volume down", None, ("do", ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "5%-"])),
                ("Sound on / off", None, ("do", ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])),
                ("Brighter", bri[3] if len(bri) > 3 else None, ("do", ["brightnessctl", "-q", "set", "+10%"])),
                ("Dimmer", None, ("do", ["brightnessctl", "-q", "set", "10%-"]))]

    def p_truth(self):
        lines = run("golem-truth", "--text").splitlines()[-300:]
        rows = [(line, None, None) for line in lines] or [("Nothing yet.", None, None)]
        self.root.after(10, lambda: (self.right.selection_clear(0, "end"),
                                     self.right.selection_set("end"), self.right.see("end")))
        return rows

    def p_about(self):
        mem = run("free", "-m").splitlines()
        used = mem[1].split() if len(mem) > 1 else []
        bat = run("sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null").strip()
        ver = open("/etc/golem/version").read().strip()[:7] if os.path.exists("/etc/golem/version") else "?"
        return [("Golem version", ver, None), ("Memory used", f"{used[2]} of {used[1]} MB" if used else "?", None),
                ("Battery", f"{bat}%" if bat else "no battery", None)]

    # ---- actions ----
    def act(self):
        if not self.rows:
            return
        row = self.rows[self.sel(self.right)]
        a = row[2]
        if not a:
            return
        kind = a[0]
        if kind == "close":
            self.confirm(f"Close {a[2].split('|')[0].strip()}?  Enter = yes, Esc = no",
                         lambda: (run("systemctl", "--user", "stop", a[1]),
                                  run("logger", "-t", "golem", f"Closed from the Control Panel: {a[2].split('|')[0].strip()}"),
                                  self.open_page("RUNNING")))
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
                self.ask_text(f"Folder for {self.app} (e.g. ~/projects/photos), empty = default:", c.get("folder", ""),
                              lambda v: (c.__setitem__("folder", v.strip()), self.open_page("APPS", keep=True)))
                return
            vals = CYCLE[k]
            cur = c.get(k)
            c[k] = vals[(vals.index(cur) + 1) % len(vals)] if cur in vals else vals[0]
            self.open_page("APPS", keep=True)
        elif kind == "remove":
            self.confirm(f"Remove the settings of {self.app}?  Enter = yes, Esc = no",
                         lambda: (self.apps.pop(self.app), setattr(self, "app", None), self.open_page("APPS")))
        elif kind == "key":
            self.mode = "keycapture"
            self.capture = a[1]
            self.status(f"Press the new keys for: {self.keys[a[1]][1]}    (Esc cancels)")
            return
        elif kind == "wifi":
            on = run("nmcli", "radio", "wifi").strip() != "enabled"
            r = helper({"do": "wifi", "on": on})
            self.open_page("NETWORK", keep=True)
            self.status(None if r == "OK" else r)
            return
        elif kind == "do":
            run(*a[1])
            self.open_page(self.page, keep=True)
        self.status()

    def confirm(self, text, then):
        self.mode = "confirm"
        self.confirm_action = then
        self.status(text)

    def ask_text(self, prompt, value, then, secret=False):
        self.mode = "text"
        self.text_then = then
        self.status(prompt)
        self.entry.configure(show="•" if secret else "")
        self.entry.delete(0, "end")
        self.entry.insert(0, value)
        self.entry.pack(fill="x", padx=40, pady=(0, 30), before=self.foot)
        self.entry.focus_set()

    def end_text(self):
        self.entry.pack_forget()
        self.mode = "rows" if self.page else "pages"
        (self.right if self.page else self.left).focus_set()

    def apply(self):
        def go(pw):
            req = {"do": "apply", "password": pw, "apps": self.apps,
                   "keys": self.keys if self.keys != [list(k) for k in self.saved_keys] else []}
            r = helper(req)
            if r == "OK":
                self.saved_apps, self.saved_keys = load()
                self.apps = json.loads(json.dumps(self.saved_apps))
                self.keys = [list(k) for k in self.saved_keys]
                run("i3-msg", "-q", "reload")
                if self.page:
                    self.open_page(self.page, keep=True)
                self.status("Applied. Every change is in the truth log.")
            else:
                self.status(r.replace("ERROR ", "Not applied: "))
        self.ask_text("Your password, to apply the changes:", "", go, secret=True)

    def discard(self):
        self.apps = json.loads(json.dumps(self.saved_apps))
        self.keys = [list(k) for k in self.saved_keys]
        if self.app not in self.apps:
            self.app = None
        if self.page:
            self.open_page(self.page, keep=True)
        self.status("Changes thrown away.")

    def leave(self):
        if self.changes():
            self.confirm("Changes are waiting.  A apply    X throw away and leave    Esc stay",
                         lambda: None)
            self.leaving = True
            return
        self.root.destroy()

    # ---- keyboard ----
    def key(self, e):
        k = e.keysym
        if self.mode == "text":
            if k == "Return":
                v = self.entry.get()
                self.end_text()
                self.text_then(v)
            elif k == "Escape":
                self.end_text()
                self.status()
            return
        if self.mode == "keycapture":
            if k == "Escape":
                self.mode = "rows"
                self.status()
                return
            if k in ("Super_L", "Super_R", "Alt_L", "Alt_R", "Control_L", "Control_R", "Shift_L", "Shift_R"):
                return
            mods = [n for bit, n in ((0x40, "Super"), (0x8, "Alt"), (0x4, "Ctrl"), (0x1, "Shift")) if e.state & bit]
            combo = "+".join(mods + [k])
            clash = [lab for c, lab, _ in self.keys if c.lower() == combo.lower()]
            self.mode = "rows"
            if clash:
                self.status(f"{combo} is already used for: {clash[0]}. Nothing changed.")
                return
            self.keys[self.capture][0] = combo
            self.open_page("KEYS", keep=True)
            self.status()
            return
        if self.mode == "confirm":
            if getattr(self, "leaving", False):
                self.leaving = False
                if k in ("a", "A"):
                    self.mode = "rows" if self.page else "pages"
                    self.apply()
                elif k in ("x", "X"):
                    self.root.destroy()
                else:
                    self.mode = "rows" if self.page else "pages"
                    self.status()
                return
            self.mode = "rows" if self.page else "pages"
            if k == "Return":
                self.confirm_action()
            self.status()
            return
        if k in ("a", "A") and self.changes():
            self.apply()
            return
        if k in ("x", "X") and self.changes():
            self.discard()
            return
        if self.mode == "pages":
            if k in ("Up", "Down"):
                self.move(self.left, -1 if k == "Up" else 1)
            elif k in ("Return", "Right"):
                self.app = None
                self.open_page(self.PAGES[self.sel(self.left)])
                self.mode = "rows"
                self.right.focus_set()
            elif k == "Escape":
                self.leave()
        elif self.mode == "rows":
            if k in ("Up", "Down"):
                self.move(self.right, -1 if k == "Up" else 1)
            elif k == "Return":
                self.act()
            elif k in ("Escape", "Left"):
                if self.page == "APPS" and self.app:
                    self.app = None
                    self.open_page("APPS")
                else:
                    self.page = None
                    self.mode = "pages"
                    self.right.delete(0, "end")
                    self.help.configure(text="")
                    self.left.focus_set()
            self.status() if self.mode != "confirm" else None


def main():
    root = tk.Tk(className="golem-panel")
    root.title("Control Panel")
    Panel(root)
    root.mainloop()


if __name__ == "__main__":
    main()
