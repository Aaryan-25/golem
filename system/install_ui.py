# golem-install-ui: the visual installer (INSTALL in the Start panel, only on the pendrive).
# A small window in Golem's look that walks through golem-install (install.nix) in four pages:
#   1. what is about to happen          2. the laptop's disks as tiles (never the pendrive)
#   3. what's on the chosen disk; type ERASE; my files too?; my password
#   4. sand pours into a bar while golem-install works; then DONE (or what went wrong)
# It does nothing itself: every step is golem-install's, run with sudo and the same safety checks.
# "SEND TO CLAUDE" sends a report (golem-report --screen) with the installer's log to my golem-reports repo,
# so Claude can read what happened from GitHub. The first time it asks for the reports key.
# Part of Golem: the system (start, hardware, power, updates); MAP.md section 5.10.
import json
import os
import random
import re
import subprocess
import threading
import tkinter as tk

T = json.loads(os.environ.get("GOLEM_THEMES", "{}")).get("shadow", {"void": "#000000", "pale": "#ffffff", "mist": "#8a8a8a"})
EMBER = "#c96a3a"
TOKEN = os.path.expanduser("~/.config/golem-report/token")


def disks():
    """[(name, size, model)] from golem-install --list (it already leaves out the pendrive)."""
    out = subprocess.run(["golem-install", "--list"], capture_output=True, text=True).stdout
    return [m.groups() for m in re.finditer(r"^\s*\d+\)\s+/dev/(\S+)\s+(\S+)\s*(.*)$", out, re.M)]


class Installer:
    def __init__(self):
        self.root = tk.Tk(className="golem-install")
        self.root.title("INSTALL GOLEM")
        self.root.configure(bg=T["void"])
        self.root.geometry("760x560")
        self.F = ("Golem Runes", 14)
        self.big = ("Golem Runes", 26)
        self.small = ("Golem Runes", 11)
        self.disk = None
        self.body = tk.Frame(self.root, bg=T["void"])
        self.body.pack(fill="both", expand=True, padx=28, pady=(22, 6))
        foot = tk.Frame(self.root, bg=T["void"])
        foot.pack(fill="x", padx=28, pady=(0, 16))
        self.status = tk.Label(foot, text="", font=self.small, fg=T["mist"], bg=T["void"], anchor="w")
        self.status.pack(side="left", fill="x", expand=True)
        self.button(foot, "SEND TO CLAUDE", self.send).pack(side="right")
        self.page_intro()

    # ---- small helpers
    def clear(self):
        for w in self.body.winfo_children():
            w.destroy()

    def text(self, t, font=None, fg=None, **kw):
        lb = tk.Label(self.body, text=t, font=font or self.F, fg=fg or T["pale"], bg=T["void"], justify="left",
                      anchor="w", wraplength=700, **kw)
        lb.pack(fill="x", pady=4)
        return lb

    def button(self, parent, label, cmd):
        return tk.Button(parent, text=label, command=cmd, font=self.F, fg=T["void"], bg=T["pale"], activebackground=T["mist"],
                         relief="flat", padx=14, pady=4, cursor="hand2")

    # ---- 1. what is about to happen
    def page_intro(self):
        self.clear()
        self.text("INSTALL GOLEM", self.big)
        self.text("Golem goes onto this laptop's own disk, and starts from there without the pendrive.")
        self.text("Everything on the disk you choose is erased: Windows, files, everything.", fg=EMBER)
        self.text("No internet is needed: the installed Golem is already on this pendrive.", self.small, T["mist"])
        self.button(self.body, "CHOOSE THE DISK", self.page_disks).pack(anchor="w", pady=18)

    # ---- 2. the disks
    def page_disks(self):
        self.clear()
        self.text("WHICH DISK?", self.big)
        found = disks()
        if not found:
            self.text("No disk found to install on (only the pendrive).", fg=EMBER)
            return
        self.text("The pendrive Golem is running from is not listed.", self.small, T["mist"])
        for name, size, model in found:
            tile = tk.Button(self.body, text=f"{name}    {size}    {model}", font=self.F, fg=T["pale"], bg=T["void"],
                             activebackground="#222222", activeforeground=T["pale"], relief="solid", bd=1,
                             anchor="w", padx=14, pady=10, cursor="hand2",
                             command=lambda n=name: self.page_confirm(n))
            tile.pack(fill="x", pady=5)

    # ---- 3. what's on it; ERASE; my files; password
    def page_confirm(self, name):
        self.disk = name
        self.clear()
        self.text(f"/dev/{name}", self.big)
        now = subprocess.run(["lsblk", "-o", "NAME,SIZE,FSTYPE,LABEL", f"/dev/{name}"], capture_output=True, text=True).stdout
        self.text("On it now:", self.small, T["mist"])
        tk.Label(self.body, text=now.strip() or "(nothing readable)", font=("DejaVu Sans Mono", 10), fg=T["pale"], bg=T["void"],
                 justify="left", anchor="w").pack(fill="x")
        self.text("All of this will be erased. Type ERASE to go ahead:", fg=EMBER)
        erase = tk.Entry(self.body, font=self.F, fg=T["pale"], bg="#111111", insertbackground=T["pale"], relief="flat")
        erase.pack(fill="x")
        copy = tk.BooleanVar(value=True)
        tk.Checkbutton(self.body, text="Also copy my files from the pendrive (Echo, zones, editor)", variable=copy,
                       font=self.small, fg=T["pale"], bg=T["void"], selectcolor="#111111", activebackground=T["void"],
                       activeforeground=T["pale"], anchor="w").pack(fill="x", pady=6)
        self.text("My password (the same as for sudo):", self.small, T["mist"])
        pw = tk.Entry(self.body, show="•", font=self.F, fg=T["pale"], bg="#111111", insertbackground=T["pale"], relief="flat")
        pw.pack(fill="x")
        row = tk.Frame(self.body, bg=T["void"])
        row.pack(fill="x", pady=14)
        self.button(row, "BACK", self.page_disks).pack(side="left")

        def go():
            if erase.get().strip() != "ERASE":
                self.status.configure(text="Type ERASE (in capitals) to go ahead. Nothing was changed.", fg=EMBER)
                return
            self.page_work(pw.get(), copy.get())
        self.button(row, "INSTALL", go).pack(side="right")
        erase.focus_set()

    # ---- 4. sand pours while golem-install works
    def page_work(self, password, copy):
        self.clear()
        self.text("INSTALLING", self.big)
        self.step = self.text("Starting ...")
        W, H = 700, 160
        cv = tk.Canvas(self.body, width=W, height=H, bg=T["void"], highlightthickness=0)
        cv.pack(pady=10)
        self.last = self.text("", self.small, T["mist"])
        cv.create_rectangle(10, H - 60, W - 10, H - 10, outline=T["mist"])
        heights = self.heights = [0] * (W - 22)
        self.cv, self.H = cv, H
        grains = []
        self.fill, self.done = 0.02, None

        def tick():                      # grains fall onto the filled part of the bar and pile up
            if self.done is None or grains:
                if self.done is None:
                    for _ in range(4):
                        grains.append([random.uniform(11, 11 + (W - 22) * self.fill), 0, random.uniform(2, 5)])
                for g in grains[:]:
                    g[1] += g[2]
                    col = min(len(heights) - 1, max(0, int(g[0] - 11)))
                    floor = H - 11 - heights[col]
                    if g[1] >= floor:
                        heights[col] = min(48, heights[col] + 1)
                        grains.remove(g)
                cv.delete("g")
                for g in grains:
                    cv.create_rectangle(g[0], g[1], g[0] + 1, g[1] + 1, fill=T["pale"], outline="", tags="g")
                for x in range(0, len(heights), 2):
                    if heights[x]:
                        cv.create_line(11 + x, H - 11, 11 + x, H - 11 - heights[x], fill=T["pale"], tags="g")
                self.root.after(40, tick)
        tick()

        def work():
            cmd = ["sudo", "-S", "-p", "", "golem-install", "--disk", self.disk, "--erase", "--copy-files", "yes" if copy else "no"]
            p = subprocess.Popen(cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
            p.stdin.write(password + "\n")
            p.stdin.close()
            for line in p.stdout:
                line = line.strip()
                m = re.match(r"^([1-4])/4\s+(.*)", line)
                if m:
                    self.fill = int(m.group(1)) / 4 - 0.05
                    self.root.after(0, self.step.configure, {"text": f"{m.group(1)} of 4:  {m.group(2)}"})
                elif line:
                    self.root.after(0, self.last.configure, {"text": line[-110:]})
            ok = p.wait() == 0
            self.root.after(0, self.finish, ok)
        threading.Thread(target=work, daemon=True).start()

    def finish(self, ok):
        self.done = ok
        if ok:
            self.fill = 1.0
            for x in range(0, len(self.heights), 2):      # the bar full of sand
                self.cv.create_line(11 + x, self.H - 11, 11 + x, self.H - 59, fill=T["pale"])
            self.step.configure(text="DONE. Golem is on the laptop's own disk.")
            self.text("Shut down, unplug the pendrive, and start the laptop. The password stays the same.")
            self.button(self.body, "SHUT DOWN", lambda: subprocess.run(["systemctl", "poweroff"])).pack(anchor="w", pady=10)
        else:
            self.step.configure(text="It did not finish.", fg=EMBER)
            self.text("Nothing more will happen. Press SEND TO CLAUDE (below), then tell Claude: it can read what "
                      "went wrong from GitHub. (A wrong password also ends up here: try again with BACK.)")
            self.button(self.body, "BACK", self.page_disks).pack(anchor="w", pady=10)

    # ---- sending a report to my golem-reports repo
    def send(self):
        if not os.path.exists(TOKEN):
            win = tk.Toplevel(self.root, bg=T["void"])
            win.title("REPORTS KEY")
            tk.Label(win, text="Paste the key for golem-reports (the GitHub token), once:", font=self.small,
                     fg=T["pale"], bg=T["void"]).pack(padx=16, pady=(14, 4))
            e = tk.Entry(win, show="•", width=48, font=self.small, fg=T["pale"], bg="#111111", insertbackground=T["pale"])
            e.pack(padx=16)

            def keep():
                subprocess.run(["golem-report", "setup"], input=e.get().strip() + "\n", text=True, capture_output=True)
                win.destroy()
                self.send()
            self.button(win, "KEEP IT", keep).pack(pady=12)
            return
        self.status.configure(text="Sending the report (the Gate may ask about git and github.com: say ALWAYS) ...", fg=T["mist"])

        def go():
            r = subprocess.run(["golem-report", "--screen", "from the installer"], capture_output=True, text=True)
            msg = "Sent. Tell Claude: it can read it from golem-reports." if r.returncode == 0 else \
                (r.stdout.strip().splitlines() or ["Couldn't send it."])[-1]
            self.root.after(0, self.status.configure, {"text": msg, "fg": T["pale"] if r.returncode == 0 else EMBER})
        threading.Thread(target=go, daemon=True).start()


if __name__ == "__main__":
    Installer().root.mainloop()
