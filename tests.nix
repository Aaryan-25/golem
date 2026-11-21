# Automated tests: GitHub starts Golem in a virtual laptop and checks it, on every change.
# (The real laptop still has the last word: see TESTS.md.)
{ pkgs, modules, golemRev }:
pkgs.testers.runNixOSTest {
  name = "golem";
  node.specialArgs = { inherit golemRev; };
  nodes.machine = { lib, ... }: {
    imports = modules;
    virtualisation.memorySize = 2048;
    boot.loader.grub.enable = lib.mkForce false;     # the test machine starts the kernel directly
    boot.growPartition = lib.mkForce false;
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("Step 3: Wi-Fi off at start, no internet clock, nothing comes in"):
        machine.succeed("grep -q WirelessEnabled=false /var/lib/NetworkManager/NetworkManager.state")
        machine.fail("systemctl is-active systemd-timesyncd")
        machine.succeed("iptables -S | grep -q DROP")

    with subtest("Step 5: the key and window settings are valid"):
        machine.succeed("i3 -C -c /etc/i3/config")

    with subtest("Login on the text screen starts the windows"):
        machine.wait_until_tty_matches("1", "login: ")
        machine.send_chars("lilgolemwitch\n")
        machine.wait_until_tty_matches("1", "Password: ")
        machine.send_chars("golem\n")
        machine.wait_for_x()
        machine.wait_until_succeeds("pgrep -x i3")

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
  '';
}
