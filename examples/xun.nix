{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "xun";
  hardware.redmi-pad-se.enable = true;

  # Set this to the directory you prepared before building for the tablet.
  # hardware.redmi-pad-se.firmwareDir = ./firmware;

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_XUN";
    fsType = "ext4";
  };

  # Add your key before first boot to log in over the ECM link.
  # users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Optional provisioning link. The host side uses 172.16.42.2/24.
  networking.interfaces.usb0.ipv4.addresses = [{ address = "172.16.42.1"; prefixLength = 24; }];
  systemd.services.xun-usb-network = {
    description = "USB Ethernet for provisioning";
    wantedBy = [ "multi-user.target" ];
    after = [ "sys-kernel-config.mount" ];
    requires = [ "sys-kernel-config.mount" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      gadget=/sys/kernel/config/usb_gadget/nixos
      mkdir -p "$gadget"
      cd "$gadget"
      echo 0x1d6b > idVendor
      echo 0x0104 > idProduct
      mkdir -p functions/ecm.usb0 configs/c.1
      ln -s functions/ecm.usb0 configs/c.1/
      for udc in /sys/class/udc/*; do
        test -e "$udc" || exit 1
        basename "$udc" > UDC
        break
      done
    '';
    preStop = "echo '' > /sys/kernel/config/usb_gadget/nixos/UDC";
    postStop = ''
      cd /sys/kernel/config/usb_gadget/nixos
      rm -f configs/c.1/ecm.usb0
      rmdir configs/c.1 functions/ecm.usb0
      cd ..
      rmdir nixos
    '';
  };

  environment.systemPackages = [ pkgs.qbootctl ];
  system.stateVersion = "26.05";
}
