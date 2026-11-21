# nixun

NixOS hardware support for the Xiaomi Redmi Pad SE 11-inch (`xun`, Snapdragon 680). The module builds the official Linux **7.2.1** stable source with SM6225 and tablet patches from the [upstream xun port](https://github.com/xushengfeng/redmi_pad_se_xun_linux/tree/f25fba528aa352b3706bba363c5b05444e03ebe8). The flake targets `nixos-unstable`. Your host configuration supplies the desktop, audio server, network manager, users, and root filesystem.

## Add the module

Add nixun as a flake input, then import its module in your `aarch64-linux` host.

```nix
# In the inputs of your flake. Adjust the path to your nixun checkout.
nixun.url = "path:../nixun";
nixun.inputs.nixpkgs.follows = "nixpkgs";
```

```nix
# In the modules list passed to nixpkgs.lib.nixosSystem.
[
  inputs.nixun.nixosModules.redmi-pad-se
  {
    nixpkgs.hostPlatform = "aarch64-linux";
    hardware.redmi-pad-se = {
      enable = true;
      # Optional factory addresses in ordinary colon-separated order.
      # wifiMac = "xx:xx:xx:xx:xx:xx";
      # bluetoothMac = "xx:xx:xx:xx:xx:xx";
    };
  }
  ./configuration.nix
]
```

Use a unique hostname per tablet if you omit the factory addresses, since the module derives locally administered addresses from it.

The module configures the board kernel, per-generation device tree, early firmware, ALSA UCM profile, and Qualcomm DSP services for Wi-Fi. It enables Mesa graphics and Bluetooth by default. The upstream port still lacks working cameras, accelerometer and ambient-light sensors, and USB Power Delivery. The DTS has a fixed 6 GiB memory layout and defaults to USB peripheral mode. Start with the matching 6 GiB model and the upstream-supported FT8203 touch hardware. Other memory layouts, touch variants and USB host mode require board testing.

## Firmware

The module uses the `xun-firmware` package. It extracts the stock
firmware from Xiaomi's pinned EEA HyperOS `OS2.0.207.0.VMUEUXM` OTA. The
package fetches about **356 MB** with hash-pinned HTTP ranges for the OTA
manifest and the `modem`, `bluetooth`, `odm`, and `vendor` partitions.
Extraction runs offline and verifies the partition images against the OTA
manifest.
[Official Xiaomi archive](https://cdnorg.d.miui.com/OS2.0.207.0.VMUEUXM/xun_eea_global-ota_full-OS2.0.207.0.VMUEUXM-user-15.0-6b1513122d.zip)

The package includes the modem and ADSP images, Wi-Fi board data,
Bluetooth firmware, both FT8203 touch firmwares, and the stock Adreno
firmware. The WCN3990 Wi-Fi driver also uses `board-2.bin` and `firmware-5.bin`
from Linux firmware. The package fetches just those files and their notices.
The module adds the AudioReach topology and the wireless regulatory database.

## Install to internal storage

This fresh NixOS installation is untested on the tablet.
[The example host](examples/xun.nix) boots from an ext4 filesystem on internal
`userdata`. It offers USB Ethernet for the initial login. Add your SSH public
key before building if you want to use that link.

1. Back up the tablet and keep a matching stock firmware package for recovery.
   Unlocking Xiaomi's bootloader wipes the tablet. Keep it unlocked. Flashing
   `userdata` replaces its contents with the NixOS root filesystem.
2. Build the initial root filesystem and the U-Boot image from the same
   configuration, using an aarch64 Linux builder with KVM. The nixpkgs image
   builder runs `nixos-install` and installs the extlinux menu in a build VM.

   ```sh
   nix build 'path:.#nixosConfigurations.xun.config.system.build.xunRootImage' -o result-root
   nix build 'path:.#nixosConfigurations.xun.config.system.build.xunBootImage' -o result-boot
   ```

3. Enter bootloader fastboot with Power + Volume Down. Check that the product
   is `xun` before flashing. Leave `vendor_boot`, `init_boot`, `dtbo`,
   `vbmeta`, and the Android bootloader partitions stock.

   ```sh
   fastboot getvar product
   fastboot -S 256M flash userdata result-root/userdata.img
   fastboot boot result-boot/boot.img
   ```

4. Verify that NixOS boots from internal storage. The first boot expands ext4
   to fill `userdata`. For the example's SSH login, set the computer's USB
   Ethernet interface to `172.16.42.2/24` and run `ssh root@172.16.42.1`.
   Check `findmnt /` and `readlink -f /run/booted-system` on the tablet.

5. Return to bootloader fastboot with Power + Volume Down. Install the tested
   image in slot A, then boot it from flash.

   ```sh
   fastboot flash boot_a result-boot/boot.img
   fastboot set_active a
   fastboot reboot
   ```

   Once NixOS boots from flash, run `sudo qbootctl -m a` on the tablet to
   mark slot A successful. Xiaomi's bootloader uses this flag to record a successful boot.

## Deploy and roll back

Xiaomi's bootloader starts U-Boot through the Android v4 shim. U-Boot loads
`/boot/extlinux/extlinux.conf` from the internal `userdata` filesystem
and shows the NixOS generation menu. The stock NixOS extlinux module
manages the menu and stores the kernel, initrd, and DTB for each entry
under `/boot/nixos`.

The default entry boots after `boot.loader.timeout` seconds (five by default).
Press a volume key during the countdown to pause, use the volume keys to
select a generation, then press Power. The loader reads the entries generated
by `boot.loader.generic-extlinux-compatible`; its `configurationLimit`
controls how many generations are available.

Deploy with deploy-rs or `nixos-rebuild switch` and reboot to load the new
kernel. To roll back, select an older generation in the boot menu or use
`nixos-rebuild switch --rollback` and reboot. Kernel updates leave the
Android boot partition alone. Updates to U-Boot itself still require
rebuilding and flashing `xunBootImage`. The SM6225 U-Boot port reserves
128 MiB each for loading the kernel and initrd; keep each boot file within
that size when customizing the host.
