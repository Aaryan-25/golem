# Golem, step 7: the truth log. What the system did, in plain words, kept 30 days.
# Super+T (or `golem-truth` in a terminal) shows it, newest at the bottom.
#
# Written into it: apps opened and closed (with zone and permissions), every internet connection
# (which app, which site, how long, data in and out), USB plugged in and out, admin rights used,
# wrong passwords, lock and unlock, Wi-Fi on and off, networks joined, zone and window changes, updates.
{ pkgs, ... }:
let
  py = name: file: pkgs.writers.writePython3Bin name { flakeIgnore = [ "E501" ]; } (builtins.readFile file);
  netwatch = py "golem-netwatch" ./netwatch.py;
  truth = py "golem-truth" ./truth.py;
  logger = "${pkgs.util-linux}/bin/logger";
in {
  environment.systemPackages = [ truth pkgs.conntrack-tools ];
  services.journald.extraConfig = "MaxRetentionSec=30day";

  # Internet: a small watcher notes each connection when it ends. Site names come from the
  # laptop's own DNS answers (NetworkManager's local dnsmasq, which writes each answer down).
  networking.networkmanager.dns = "dnsmasq";
  environment.etc."NetworkManager/dnsmasq.d/golem-log.conf".text = "log-queries\n";
  systemd.services.golem-netwatch = {
    description = "Golem: write every internet connection into the truth log";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-pre.target" ];
    path = with pkgs; [ conntrack-tools iproute2 systemd kmod procps coreutils ];
    serviceConfig = {
      ExecStartPre = [
        "${pkgs.kmod}/bin/modprobe -a nf_conntrack nf_conntrack_netlink"
        "${pkgs.procps}/bin/sysctl -q -w net.netfilter.nf_conntrack_acct=1"
        # a finished connection is written down after 10 s, not the usual 2 minutes
        "${pkgs.procps}/bin/sysctl -q -w net.netfilter.nf_conntrack_tcp_timeout_time_wait=10"
      ];
      ExecStart = "${netwatch}/bin/golem-netwatch";
      Restart = "always";
    };
  };

  # USB plugged in and out.
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", RUN+="${logger} -t golem-usb 'USB plugged in: $attr{manufacturer} $attr{product}'"
    ACTION=="remove", SUBSYSTEM=="usb", ENV{DEVTYPE}=="usb_device", RUN+="${logger} -t golem-usb 'USB unplugged: $env{ID_VENDOR} $env{ID_MODEL}'"
  '';
}
