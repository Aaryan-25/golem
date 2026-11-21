# golem-alert: the red alert, the only thing that ever covers the screen by itself.
#   golem-alert "message"   show it; it goes away after pressing the dismiss key several times
#   golem-alert --watch     check every minute: battery low (not charging), drive almost full
import glob
import os
import shutil
import subprocess
import sys
import time
import tkinter as tk

CONF = "/var/lib/golem/settings.conf"


def settings():
    c = {"alert_key": "space", "alert_presses": "3", "alert_battery": "10", "alert_disk": "90"}
    if os.path.exists(CONF):
        for line in open(CONF):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                c[k] = v
    return c


def log(msg):
    subprocess.run(["logger", "-t", "golem", msg])


def show(message):
    c = settings()
    key, need = c["alert_key"], int(c["alert_presses"])
    log(f"RED ALERT: {message}")
    root = tk.Tk(className="golem-alert")
    root.attributes("-fullscreen", True)
    root.configure(bg="#2a0306")
    h = root.winfo_screenheight()
    big = max(18, h // 22)
    tk.Label(root, text="RED ALERT", fg="#ff5a5a", bg="#2a0306", font=("DejaVu Sans", big // 2)).pack(pady=(h // 4, 10))
    tk.Label(root, text=message, fg="#ffe9e9", bg="#2a0306", font=("DejaVu Sans", big), wraplength=root.winfo_screenwidth() - 160,
             justify="center").pack(pady=10)
    hint = tk.Label(root, text="", fg="#ff9a9a", bg="#2a0306", font=("DejaVu Sans", big // 2))
    hint.pack(pady=30)
    left = [need]

    def update():
        hint.configure(text=f"press {key.upper()}  ×{left[0]}")

    def press(e):
        if e.keysym == key or e.keysym.lower() == key.lower():
            left[0] -= 1
            if left[0] <= 0:
                log("RED ALERT dismissed")
                root.destroy()
                return
            update()
    update()
    root.bind("<Key>", press)
    root.after(200, root.focus_force)

    def grab():
        try:
            root.grab_set_global()
        except tk.TclError:
            pass
    root.after(300, grab)
    root.mainloop()


def watch():
    raised = set()
    while True:
        c = settings()
        # battery
        bat = None
        for d in glob.glob("/sys/class/power_supply/BAT*"):
            try:
                cap = int(open(f"{d}/capacity").read())
                status = open(f"{d}/status").read().strip()
                bat = (cap, status)
            except (OSError, ValueError):
                pass
        if bat and c["alert_battery"] != "off":
            low = bat[1] == "Discharging" and bat[0] <= int(c["alert_battery"])
            if low and "battery" not in raised:
                raised.add("battery")
                show(f"The battery is at {bat[0]}% and not charging. Plug in the charger.")
            elif not low:
                raised.discard("battery")
        # drive
        if c["alert_disk"] != "off":
            u = shutil.disk_usage("/")
            full = u.used * 100 // u.total
            if full >= int(c["alert_disk"]) and "disk" not in raised:
                raised.add("disk")
                show(f"Golem's drive is {full}% full. Free space in Control Panel > STORAGE.")
            elif full < int(c["alert_disk"]):
                raised.discard("disk")
        time.sleep(60)


def main():
    if sys.argv[1:] == ["--watch"]:
        watch()
    else:
        show(" ".join(sys.argv[1:]) or "Something needs your attention.")


if __name__ == "__main__":
    main()
