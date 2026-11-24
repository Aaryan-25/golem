# The Asus's NVIDIA card (GTX 1650), for apps I mark only (Control Panel > APPS > an app > nvidia: allowed).
# NVIDIA's own driver (closed, chosen 24 Nov 2026), its open kernel part, for computing only (Echo's training).
# The Intel graphics keep running the screen, and the card sleeps whenever nothing uses it.
# On the Dell (no NVIDIA card) none of this loads. The HDMI port still needs more (a later step).
{ config, lib, pkgs, ... }:
let
  nv = config.boot.kernelPackages.nvidiaPackages.stable;
in {
  # The only closed parts Golem allows: NVIDIA's driver and its tools.
  nixpkgs.config.allowUnfreePredicate = p: builtins.elem (lib.getName p) [ "nvidia-x11" ];
  boot.extraModulePackages = [ nv.open ];
  boot.blacklistedKernelModules = [ "nouveau" "nova_core" "nvidiafb" ];
  # Sleep whenever unused (Turing card with a Comet Lake processor can).
  boot.extraModprobeConfig = ''
    options nvidia NVreg_DynamicPowerManagement=0x02
  '';
  # The driver's own computing libraries (CUDA) go where programs look for them: /run/opengl-driver/lib.
  hardware.graphics.enable = true;
  hardware.graphics.extraPackages = [ nv.out ];
  environment.systemPackages = [ nv.bin ];     # nvidia-smi: what the card is doing
  services.udev.extraRules = ''
    # The card's doors in /dev, made when the driver loads; then the part CUDA needs (nvidia_uvm).
    KERNEL=="nvidia", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidiactl c 195 255; for i in $$(cat /proc/driver/nvidia/gpus/*/information | grep Minor | cut -d \  -f 4); do mknod -m 666 /dev/nvidia$${i} c 195 $${i}; done; ${pkgs.kmod}/bin/modprobe nvidia_uvm'"
    KERNEL=="nvidia_uvm", RUN+="${pkgs.runtimeShell} -c 'mknod -m 666 /dev/nvidia-uvm c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 0; mknod -m 666 /dev/nvidia-uvm-tools c $$(grep nvidia-uvm /proc/devices | cut -d \  -f 1) 1'"
    ACTION=="add", SUBSYSTEM=="pci", ATTR{vendor}=="0x10de", ATTR{class}=="0x03*", ATTR{power/control}="auto"
  '';
}
