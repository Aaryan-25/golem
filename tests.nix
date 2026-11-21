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
    environment.systemPackages = [ pkgs.socat ];
    # the test laptop's small disk is always nearly full: no drive alert here
    systemd.tmpfiles.rules = [ "f /var/lib/golem/settings.conf 0644 root root - alert_disk=off" ];
    environment.etc."golem-test-long.sh".text = ''
      exec 3<>/dev/tcp/web/80
      sleep 90
    '';
    environment.etc."golem-test-fetch.sh".text = ''
      exec 3<>/dev/tcp/web/80
      sleep 2
      printf 'GET / HTTP/1.0\r\nHost: web\r\n\r\n' >&3
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

    with subtest("Step 6: Golem starts straight into the lock screen"):
        machine.wait_for_x()
        machine.wait_until_succeeds("pgrep -x i3")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -x i3lock")
        machine.sleep(3)

    with subtest("Step 6: a wrong password keeps it locked and is logged"):
        machine.send_chars("wrongpassword\n")
        machine.sleep(5)
        machine.succeed("pgrep -u lilgolemwitch -x i3lock")
        machine.wait_until_succeeds("journalctl -b | grep -iE 'i3lock.*(authentication failure|auth could not)'", timeout=30)

    with subtest("Step 6: the right password unlocks"):
        machine.send_chars("golem\n")
        machine.wait_until_fails("pgrep -u lilgolemwitch -x i3lock", timeout=30)
        machine.succeed("journalctl -b | grep -q 'golem.*UNLOCK'")

    def as_me(cmd):
        return machine.succeed(
            "su - lilgolemwitch -c 'export XDG_RUNTIME_DIR=/run/user/1000 "
            "DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus; " + cmd + "'"
        ).strip()

    with subtest("Step 5: Alt+Enter opens a terminal"):
        machine.sleep(5)                              # let the window manager settle
        machine.send_key("alt-ret")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f bin/xterm", timeout=60)

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

    with subtest("Step 6: Super+L locks; Caps Lock ON stops the automatic lock"):
        machine.send_key("meta_l-l")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -x i3lock", timeout=30)
        machine.sleep(3)
        machine.send_chars("golem\n")
        machine.wait_until_fails("pgrep -u lilgolemwitch -x i3lock", timeout=30)
        machine.send_key("caps_lock")
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 golem-lock --auto'")
        machine.succeed("journalctl -b | grep -q 'LOCK skipped: Caps Lock is ON'")
        machine.fail("pgrep -u lilgolemwitch -x i3lock")
        machine.send_key("caps_lock")

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
        for words in ["Opened xterm in RED", "Wrong password at the lock screen", "Screen locked",
                      "Screen unlocked", "Settings: bash: zone YELLOW", "USB plugged in",
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
        for key in ["e", "ret", "ret", "down", "ret"]:        # CONTROLS > APPS > bash > zone > next zone
            machine.send_key(key)
            machine.sleep(1)
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

    with subtest("The clock can be set by hand from the Control Panel, with the password, and it is logged"):
        assert "wrong password" in ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "nope"})
        assert ask_guard({"do": "clock-set", "time": "2026-12-25 10:00", "password": "golem"}) == "OK"
        assert machine.succeed("date +%Y-%m-%d").strip() == "2026-12-25"
        machine.wait_until_succeeds("golem-truth --text | grep -q 'Clock set by hand'")

    with subtest("Going to sleep: the lock is on the screen before the laptop sleeps"):
        machine.succeed("su - lilgolemwitch -c 'DISPLAY=:0 XSS_SLEEP_LOCK_FD=9 golem-lock --auto 9</dev/null' >/dev/null 2>&1 &")
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -x i3lock", timeout=30)
        machine.sleep(3)
        machine.send_chars("golem\n")
        machine.wait_until_fails("pgrep -u lilgolemwitch -x i3lock", timeout=30)
        machine.wait_until_succeeds("journalctl -b | grep -c 'golem.*UNLOCK' | grep -qv '^[0-2]$'")

    with subtest("Settings: the system side runs at start; trackers are blocked by default"):
        machine.succeed("systemctl show -p Result --value golem-settings | grep -q success")
        machine.succeed("readlink /var/lib/golem/blocklist.hosts | grep -q blocklist")
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
        machine.wait_until_succeeds("pgrep -u lilgolemwitch -f alert.py", timeout=30)
        machine.sleep(3)
        machine.screenshot("red_alert")
        machine.send_key("spc")
        machine.sleep(1)
        machine.succeed("pgrep -u lilgolemwitch -f alert.py")
        machine.send_key("spc")
        machine.sleep(1)
        machine.send_key("spc")
        machine.wait_until_fails("pgrep -u lilgolemwitch -f alert.py", timeout=30)
        machine.wait_until_succeeds("golem-truth --text | grep -q 'RED ALERT dismissed'")

    with subtest("Backups and save slots work through the guard"):
        assert ask_guard({"do": "backup-save", "name": "test1", "password": "golem"}) == "OK"
        machine.succeed("test -s /var/lib/golem/backups/test1.tar")
        assert ask_guard({"do": "backup-load", "name": "test1", "password": "golem"}) == "OK"
        assert "newest 3" in ask_guard({"do": "delete-version", "version": "1", "password": "golem"})
  '';
}
