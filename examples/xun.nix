{ pkgs, ... }:
{
  nixpkgs.hostPlatform = "aarch64-linux";
  networking.hostName = "xun";
  hardware.redmi-pad-se.enable = true;

  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_XUN";
    fsType = "ext4";
    autoResize = true;
  };

  # Add your key before first boot to log in over the ECM link.
  # users.users.root.openssh.authorizedKeys.keys = [ "ssh-ed25519 ..." ];
  services.openssh = {
    enable = true;
    settings.PermitRootLogin = "prohibit-password";
  };

  # Optional provisioning link. The host side uses 172.16.42.2/24.
  networking.interfaces.usb0.ipv4.addresses = [{ address = "172.16.42.1"; prefixLength = 24; }];
  boot.kernelModules = [ "g_ether" ];

  environment.systemPackages = [ pkgs.qbootctl ];
  system.stateVersion = "26.05";
}
