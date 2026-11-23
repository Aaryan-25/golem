# Automated tests: GitHub starts Golem in a virtual laptop and checks it, on every change.
# (The real laptop still has the last word: see TESTS.md.)
{ pkgs, modules, golemRev }:
pkgs.testers.runNixOSTest {
  name = "golem";
  node.specialArgs = { inherit golemRev; };
  # A small web server on the test network, for the internet part of the truth log.
  nodes.web = { ... }: {
    services.nginx = {
      enable = true;
      virtualHosts.web = { default = true; locations."/".return = "200 hello"; };
    };
    networking.firewall.allowedTCPPorts = [ 80 ];
  };
  nodes.machine = { lib, pkgs, ... }: {
    imports = modules;
    virtualisation.memorySize = 2048;
    virtualisation.qemu.options = [ "-device qemu-xhci,id=xhci" ];   # a USB port to plug things into
    networking.networkmanager.unmanaged = [ "eth1" ];               # the test network stays as the test set it
    environment.systemPackages = [ pkgs.socat pkgs.curl ];
    # the test laptop's small disk is always nearly full: no drive alert here
    systemd.tmpfiles.rules = [ "f /var/lib/golem/settings.conf 0644 root root - alert_disk=off"
      # the test's own answer to the Gate, given once in advance: bash in YELLOW may always reach the test web server
      "d /var/lib/golem-gate 0755 golem-gate golem-gate -"
      "f /var/lib/golem-gate/rules.json 0644 golem-gate golem-gate - {\"bash|YELLOW|web\": \"always\"}" ];
    # through the Gate, the only way out (gate.nix)
    environment.etc."golem-test-long.sh".text = ''
      exec 3<>/dev/tcp/127.0.0.1/3128
      printf 'CONNECT web:80 HTTP/1.1\r\n\r\n' >&3
      sleep 90
    '';
    environment.etc."golem-test-fetch.sh".text = ''
      exec 3<>/dev/tcp/127.0.0.1/3128
      sleep 2
      printf 'GET http://web/ HTTP/1.0\r\nHost: web\r\n\r\n' >&3
      cat <&3 >/dev/null
    '';
    boot.loader.grub.enable = lib.mkForce false;     # the test machine starts the kernel directly
    boot.growPartition = lib.mkForce false;
  };

  enableOCR = true;      # lets the test read the screen when something goes wrong
  testScript = ''
    web.start()
    machine.wait_for_unit("multi-user.target")

    with subtest("Step 3: Wi-Fi off at start, no internet clock, nothing comes in"):
        machine.succeed("grep -q WirelessEnabled=false /var/lib/NetworkManager/NetworkManager.state")
        machine.fail("systemctl is-active systemd-timesyncd")
        machine.succeed("iptables -S | grep -q DROP")

    with subtest("Step 5: the key and window settings are valid"):
        machine.succeed("i3 -C -c /etc/i3/config")

    with subtest("Step A: Golem starts straight in, no lock screen"):
        if machine.execute("timeout 180 sh -c 'until pgrep -x i3 && pgrep -u lilgolemwitch -x xss-lock; do sleep 1; done'")[0] != 0:
            print(machine.execute("journalctl -b --no-pager -t golem -t login -t systemd-logind | tail -30; tail -30 /home/lilgolemwitch/.local/share/xorg/Xorg.0.log; ps aux | grep -E 'X|i3|startx' | grep -v grep")[1])
            raise Exception("the desktop did not start")
        machine.wait_for_x()
        machine.fail("pgrep i3lock")
        machine.sleep(3)

    with subtest("Step A: the text-only start exists, and golem-why answers"):
        machine.succeed("test -e /run/current-system/specialisation/text-only/etc/golem/text-only")
        machine.fail("test -e /etc/golem/text-only")
        out = machine.succeed("su - lilgolemwitch -c golem-why")
        assert "Problems on this start" in out, out

    realm_seen = "su - lilgolemwitch -c 'DISPLAY=:0 xdotool search --onlyvisible --class golem-realm'"

    with subtest("Step B: Golem wakes up into the Start panel; Esc goes to the desktop"):
        if machine.execute("timeout 120 sh -c 'until journalctl -b -t golem -o cat | grep -q \"The realm woke up\"; do sleep 1; done'")[0] != 0:
            print(machine.execute("set +e +o pipefail; journalctl -b -t golem --no-pager | tail -20; cat /run/user/1000/golem-realm.err; ps -u lilgolemwitch -o args; which golem-realm; grep -n realm $(ps -o args= -C i3 | awk '{print $3}') ; su - lilgolemwitch -c 'DISPLAY=:0 timeout 20 golem-realm --daemon; cat /run/user/1000/golem-realm.err' 2>&1 | tail -30")[1])
            raise Exception("the realm did not wake up")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(5)
        machine.screenshot("start_panel")
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)

    with subtest("Step B: Super+Escape brings it back; SLUMBER opens its own list; Esc twice leaves"):
        machine.send_key("meta_l-esc")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(3)
        for _ in range(4):
            machine.send_key("down")
            machine.sleep(1)
        machine.send_key("ret")
        machine.sleep(2)
        machine.screenshot("slumber")
        machine.succeed(realm_seen)
        machine.send_key("esc")
        machine.sleep(1)
        machine.succeed(realm_seen)
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.fail("journalctl -b -t golem -o cat | grep -q 'Start panel: SLEEP'")

    def as_me(cmd):
        return machine.succeed(
            "su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; " + cmd + "'"
        ).strip()

    with subtest("Step 5: Alt+Enter opens a terminal"):
        machine.sleep(5)                              # let the window manager settle
        machine.send_key("alt-ret")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f bin/xterm", timeout=60)

    with subtest("Step C: windows as sand: maximise and back, minimise and bring back"):
        machine.sleep(2)
        machine.send_key("alt-f")
        machine.sleep(3)
        machine.send_key("alt-f")
        machine.sleep(3)
        machine.send_key("meta_l-m")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'WINDOW minimised'", timeout=30)
        machine.sleep(2)
        machine.send_key("meta_l-shift-m")
        machine.sleep(2)
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.succeed("pgrep -u lilgolemwitch -f realm.py")
        machine.succeed("pgrep -u lilgolemwitch -f bin/xterm")
        machine.succeed("grep -q window_sand /etc/golem/settings-schema.json")

    def close_menu():
        for _ in range(10):
            machine.sleep(2)
            if machine.execute("pgrep -u lilgolemwitch rofi")[0] != 0:
                return
            machine.send_key("esc")
        raise Exception("Esc did not close the menu")

    with subtest("Step 5: Super+H shows the key list, Alt+Space the launcher"):
        machine.send_key("meta_l-h")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f 'rofi.*KEYS'", timeout=60)
        close_menu()
        machine.send_key("alt-spc")
        if machine.execute("timeout 30 sh -c 'until pgrep -u lilgolemwitch -f rofi.*drun; do sleep 1; done'")[0] != 0:
            print(machine.execute("ps -u lilgolemwitch -o pid,args; journalctl -b --no-pager | grep -iE 'rofi|golem-launch|i3' | tail -30")[1])
            print(machine.execute("su - lilgolemwitch -c 'DISPLAY=:0 timeout 5 golem-launch' 2>&1 | tail -20")[1])
            raise Exception("Alt+Space did not open the launcher")
        close_menu()

    with subtest("Step 4: a RED app with a window opens (launched from the desktop)"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 i3-msg exec \"zone red xterm\"'")
        if machine.execute("timeout 40 sh -c 'until pgrep -f \"firejail.*xterm\" && [ $(pgrep -u lilgolemwitch -f bin/xterm | wc -l) -ge 2 ]; do sleep 1; done'")[0] != 0:
            print(machine.execute("journalctl -b --no-pager | grep -iE 'firejail|zone|xauth' | tail -20; ps -u lilgolemwitch -o args")[1])
            raise Exception("RED xterm did not open")

    with subtest("Idle: golem-idle starts when untouched and ends on the first touch"):
        machine.sleep(4)                              # untouched for a moment, as when the idle time comes
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 XSS_SLEEP_LOCK_FD=9 golem-idle 9</dev/null' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -qx IDLE", timeout=30)
        machine.sleep(4)
        machine.succeed("pgrep -u lilgolemwitch -f bin/golem-idle")
        machine.send_key("shift")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -qx AWAKE", timeout=30)
        machine.wait_until_fails("pgrep -u lilgolemwitch -f bin/golem-idle", timeout=30)
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'The idle screen came'", timeout=30)
        machine.succeed(realm_seen)
        machine.sleep(2)
        machine.send_key("esc")
        machine.wait_until_fails(realm_seen, timeout=30)

    with subtest("Step 4: my folders exist"):
        for d in ["documents", "projects", "media", "zones"]:
            machine.succeed(f"test -d /home/lilgolemwitch/{d}")

    with subtest("Step 4: RED sees none of my files and has no internet"):
        assert as_me("zone red bash -c \"ls ~ | wc -l\"") == "0"
        assert as_me("zone red bash -c \"ip -o link | wc -l\"") == "1"   # only the loopback

    with subtest("Step 4: OFFLINE keeps its files in its own folder, no internet"):
        as_me("zone offline bash -c \"touch ~/hello\"")
        machine.succeed("test -f /home/lilgolemwitch/zones/bash/hello")
        assert as_me("zone offline bash -c \"ls ~\"") == "hello"
        assert as_me("zone offline bash -c \"ip -o link | wc -l\"") == "1"

    with subtest("Step 4: GREEN sees my folders, internet only if allowed"):
        assert "documents" in as_me("zone green bash -c \"ls ~\"")
        assert as_me("zone green bash -c \"ip -o link | wc -l\"") == "1"

    with subtest("Step 4: saved zones are used"):
        as_me("zone set bash yellow")  # (zones run without the screen here)
        assert "YELLOW" in as_me("zone show bash")
        assert as_me("zone bash -c \"ls ~ | grep -c documents || true\"") == "0"

    with subtest("Step 7: the truth log tells what happened, in plain words"):
        web.wait_for_unit("nginx.service")
        web.wait_for_open_port(80)
        machine.wait_for_unit("golem-netwatch.service")
        as_me("zone bash /etc/golem-test-fetch.sh")        # bash is YELLOW (internet allowed) by now
        machine.send_monitor_command("device_add usb-tablet,bus=xhci.0,id=t1")
        if machine.execute("timeout 60 sh -c 'until golem-truth --text | grep -q \"bash (YELLOW) talked to\"; do sleep 2; done'")[0] != 0:
            print(machine.execute("journalctl -u golem-netwatch --no-pager | tail -30; golem-truth --text | tail -8; sysctl net.netfilter.nf_conntrack_acct; conntrack -L 2>&1 | tail -5; timeout 8 conntrack -E -o id 2>&1 & sleep 1; zone_dummy=1; su - lilgolemwitch -c 'zone bash /etc/golem-test-fetch.sh'; sleep 7")[1])
            raise Exception("the internet connection was not written down")
        truth = machine.succeed("golem-truth --text")
        print(truth)
        for words in ["Opened xterm in RED", "Untouched for a while (idle)", "Touched again",
                      "The realm woke up", "Settings: bash: zone YELLOW", "USB plugged in",
                      "bash (YELLOW) talked to", "out,"]:
            assert words in truth, f"missing from the truth log: {words}"

    import json

    def ask_guard(req):
        machine.succeed("cat > /tmp/req.json << 'EOF'\n" + json.dumps(req) + "\nEOF")
        return as_me("socat -t 10 - UNIX-CONNECT:/run/golem-helper.sock < /tmp/req.json")

    def current():
        apps = {}
        for f in machine.succeed("ls /var/lib/golem/apps").split():
            text = machine.succeed(f"cat /var/lib/golem/apps/{f}")
            apps[f[:-5]] = dict(line.split("=", 1) for line in text.splitlines() if "=" in line)
        keys = [[p.strip() for p in line.split("|", 2)] for line in
                machine.succeed("grep -v '^#' /var/lib/golem/keys.conf").splitlines()]
        return apps, keys

    with subtest("Step 8: settings can't be changed behind the Control Panel's back"):
        machine.fail("su - lilgolemwitch -c 'touch /var/lib/golem/apps/sneaky.conf'")
        machine.fail("su - lilgolemwitch -c 'echo zone=green >> /var/lib/golem/apps/bash.conf'")
        assert "already has settings" in as_me("zone set bash green 2>&1 || true")

    with subtest("Step 8: a wrong password changes nothing"):
        apps, keys = current()
        apps["bash"]["zone"] = "green"
        assert "wrong password" in ask_guard({"do": "apply", "password": "nope", "apps": apps, "keys": []})
        machine.succeed("grep -q zone=yellow /var/lib/golem/apps/bash.conf")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Wrong password in the Control Panel'")

    with subtest("Step 8: with the password, an app's zone and a key change, and both are logged"):
        apps, keys = current()
        apps["bash"]["zone"] = "offline"
        apps["bash"]["internet"] = "never"
        for k in keys:
            if k[2].endswith("golem-truth"):
                k[0] = "Super+y"
        answer = ask_guard({"do": "apply", "password": "golem", "apps": apps, "keys": keys})
        if answer != "OK":
            print(machine.execute("journalctl -b --no-pager | grep -iE 'golem-helper|golem-panel|pam' | tail -20")[1])
        assert answer == "OK", answer
        machine.succeed("grep -q zone=offline /var/lib/golem/apps/bash.conf")
        machine.succeed("grep -q 'bindsym Mod4+y .*golem-truth' /var/lib/golem/keys.i3")
        truth = machine.succeed("golem-truth --text")
        assert "Settings: bash: zone offline, internet never" in truth, truth
        assert "Keys: Super+y now does: Truth log" in truth, truth
        assert as_me("zone bash -c \"ip -o link | wc -l\"") == "1"     # OFFLINE now: no internet

    with subtest("Step 8: the Control Panel opens with Super+Z and changes a zone with the keyboard"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 i3-msg -q reload'")
        machine.sleep(2)
        machine.send_key("meta_l-z")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f panel.py", timeout=60)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Opened golem-panel in GREEN'", timeout=30)
        machine.sleep(4)
        machine.screenshot("panel_open")
        for key in ["e", "ret", "ret", "down", "ret"]:        # WEAVE > APPS > bash > zone > next zone
            machine.send_key(key)
            machine.sleep(1)
        machine.succeed("test -s /run/user/1000/golem-page-b.png")      # the page changes went through the sand
        machine.send_key("a")
        machine.sleep(1)
        machine.send_chars("golem\n")
        if machine.execute("timeout 30 sh -c 'until grep -q zone=yellow /var/lib/golem/apps/bash.conf; do sleep 1; done'")[0] != 0:
            print("SCREEN:", machine.get_screen_text())
            print(machine.execute("cat /var/lib/golem/apps/bash.conf; golem-truth --text | tail -5")[1])
            raise Exception("the panel did not apply the change")
        for key in ["esc", "esc", "esc"]:
            machine.send_key(key)
            machine.sleep(1)
        machine.wait_until_fails("pgrep -u lilgolemwitch -f panel.py", timeout=30)
        machine.screenshot("panel_done")

    with subtest("Truth log: a connection open for over a minute is written down while still open"):
        as_me("zone set bash yellow 2>/dev/null; true")
        apps, keys = current()
        apps["bash"]["zone"] = "yellow"
        apps["bash"]["internet"] = "allowed"
        assert ask_guard({"do": "apply", "password": "golem", "apps": apps, "keys": []}) == "OK"
        machine.succeed("su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; zone bash /etc/golem-test-long.sh' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'has been talking to .* (still open)'", timeout=120)

    with subtest("The Gate: no way out but through it; it asks me; my answer is kept and logged"):
        machine.wait_for_unit("golem-gate.service")
        machine.fail("su - lilgolemwitch -c 'timeout 5 bash -c \"echo > /dev/tcp/web/80\"'")      # straight out: refused
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 curl -s -o /tmp/gate-answer -w %{http_code} http://web/ > /tmp/gate-code' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("pgrep -f 'THE GATE'", timeout=30)              # the question is on the screen
        machine.sleep(1)
        machine.screenshot("gate_asks")
        machine.send_key("esc")                                                     # no, this time
        machine.wait_until_succeeds("grep -q 403 /tmp/gate-code", timeout=30)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Gate: curl (not in a zone) was stopped from reaching web'", timeout=30)
        assert "web" in machine.succeed("tail -n 3 /var/lib/golem-gate/feed.jsonl")
        assert "bash  YELLOW  web  always" in as_me("golem-gate rules")
        assert as_me("golem-gate off") == "off"
        assert as_me("zone bash -c \"curl -s -o /dev/null -w %{http_code} http://web/\"") == "403"
        assert as_me("golem-gate on") == "normal"

    with subtest("The clock can be set by hand from the Control Panel, with the password, and it is logged"):
        assert "wrong password" in ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "nope"})
        assert ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "golem"}) == "OK"
        assert machine.succeed("date +%Y-%m-%d").strip() == "2026-12-25"
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Clock set by hand'")

    with subtest("Settings: the system side runs at start; trackers are blocked by default"):
        machine.succeed("systemctl show -p Result --value golem-settings | grep -q success")
        machine.succeed("test $(grep -c ^0.0.0.0 /var/lib/golem/blocklist.hosts) -gt 50000")
        machine.succeed("grep -q addn-hosts /etc/NetworkManager/dnsmasq.d/golem-block.conf")

    with subtest("DRIVERS: switching the camera off means its driver can't load at all"):
        machine.succeed("modprobe uvcvideo && modprobe -r uvcvideo")
        assert ask_guard({"do": "apply", "password": "golem", "apps": current()[0], "keys": [],
                          "settings": {"camera": "off"}}) == "OK"
        machine.fail("modprobe uvcvideo")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Settings: Camera: off'")
        assert ask_guard({"do": "apply", "password": "golem", "apps": current()[0], "keys": [],
                          "settings": {"camera": "on"}}) == "OK"
        machine.succeed("modprobe uvcvideo")

    with subtest("LOOK: Super+I turns the face to Negative everywhere, at once"):
        machine.send_key("meta_l-i")
        machine.wait_until_succeeds("grep -q face=negative /var/lib/golem/settings.conf", timeout=30)
        machine.wait_until_succeeds("grep -q '${(import ./settings.nix).themeNegative.void}' /home/lilgolemwitch/zones/settings/face.i3", timeout=30)
        machine.screenshot("negative")
        machine.send_key("meta_l-i")
        machine.wait_until_succeeds("grep -q face=shadow /var/lib/golem/settings.conf", timeout=30)

    with subtest("The red alert covers the screen and goes away only after 3 presses"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 golem-alert Test alert' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f 'alert.py Test'", timeout=30)
        machine.sleep(3)
        machine.screenshot("red_alert")
        machine.send_key("spc")
        machine.sleep(1)
        machine.succeed("pgrep -u lilgolemwitch -f 'alert.py Test'")
        machine.send_key("spc")
        machine.sleep(1)
        machine.send_key("spc")
        if machine.execute("timeout 20 sh -c 'while pgrep -u lilgolemwitch -f \"alert.py Test\"; do sleep 1; done'")[0] != 0:
            print("FOCUS:", machine.execute("su - lilgolemwitch -c 'DISPLAY=:0 xdotool getwindowfocus getwindowname; DISPLAY=:0 xprop -id $(DISPLAY=:0 xdotool getwindowfocus) WM_CLASS' 2>&1")[1])
            print(machine.execute("journalctl -b --no-pager | grep -iE 'alert|golem\\[' | tail -15")[1])
            print("SCREEN:", machine.get_screen_text())
            raise Exception("the red alert did not go away after 3 presses")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'RED ALERT dismissed'")

    with subtest("Backups and save slots work through the guard"):
        assert ask_guard({"do": "backup-save", "name": "test1", "password": "golem"}) == "OK"
        machine.succeed("test -s /var/lib/golem/backups/test1.tar")
        assert ask_guard({"do": "backup-load", "name": "test1", "password": "golem"}) == "OK"
        assert "newest 3" in ask_guard({"do": "delete-version", "version": "1", "password": "golem"})

    with subtest("Firefox out: none in Golem; the preview window shows this computer only; Word/Excel helper"):
        machine.fail("su - lilgolemwitch -c 'command -v firefox'")
        machine.fail("su - lilgolemwitch -c 'DISPLAY=:0 golem-view https://example.com'")
        machine.succeed("su - lilgolemwitch -c 'echo \"<h1>LOCAL</h1>\" > /tmp/p.html'")
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000 golem-preview /tmp/p.html >/tmp/preview.log 2>&1 &'")
        if machine.execute("timeout 90 sh -c 'until su - lilgolemwitch -c \"DISPLAY=:0 xdotool search --class golem-preview\"; do sleep 2; done'")[0] != 0:
            print(machine.execute("cat /tmp/preview.log")[1])
            raise Exception("the preview window did not open")
        machine.execute("pkill -f golem-view; pkill -f golem-preview")
        out = machine.execute("su - lilgolemwitch -c 'golem-office open /etc/hostname'")[1]
        assert "WORD" in out, out

    with subtest("Step E: GADA in the Start panel opens the editor"):
        machine.send_key("meta_l-esc")
        machine.wait_until_succeeds(realm_seen, timeout=30)
        machine.sleep(3)
        machine.send_key("down")
        machine.sleep(1)
        machine.send_key("ret")
        machine.wait_until_succeeds("journalctl -b -t golem -o cat | grep -q 'Start panel: GADA'", timeout=30)
        machine.wait_until_fails(realm_seen, timeout=30)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Opened golem-edit in GREEN'", timeout=60)

    with subtest("golem-selftest runs and its machine checks pass (the laptop parts can't, here)"):
        out = machine.execute("su - lilgolemwitch -c 'export DISPLAY=:0 XDG_RUNTIME_DIR=/run/user/1000; golem-selftest' 2>&1")[1]
        print(out)
        assert "command not found" not in out, "a command inside golem-selftest is missing"
        for line in ["✓ Wi-Fi was switched off at start", "✓ no clock over the internet", "✓ the firewall is on",
                     "✓ RED sees none of my files", "✓ RED has no network at all", "✓ OFFLINE has no network at all",
                     "✓ the truth log writes and reads", "✓ the internet watcher is running", "✓ the settings guard is listening",
                     "✓ system settings were applied at start", "✓ the window manager is running", "✓ my key list is valid"]:
            assert line in out, "missing: " + line
        machine.succeed("test -s /home/lilgolemwitch/golem-selftest.txt")

    with subtest("golem-sand draws the sand and writes down how smooth it was"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 timeout 120 golem-sand --windowed --seconds 6' >&2")
        machine.succeed("grep -q 'Sand test:' /home/lilgolemwitch/golem-sand.txt")
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Sand test'", timeout=30)
  '';
}
