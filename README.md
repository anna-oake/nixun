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

The module configures the board kernel, device tree in the boot image, early firmware, ALSA UCM profile, and Qualcomm DSP services for Wi-Fi. It enables Mesa graphics and Bluetooth by default. The upstream port still lacks working cameras, accelerometer and ambient-light sensors, and USB Power Delivery. The DTS has a fixed 6 GiB memory layout and defaults to USB peripheral mode. Start with the matching 6 GiB model and the upstream-supported FT8203 touch hardware. Other memory layouts, touch variants and USB host mode require board testing.

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
firmware. The module also adds the AudioReach topology and standard Linux
firmware.

## Install to internal storage

[The example host](examples/xun.nix) boots from an ext4 filesystem on internal
`userdata`. It offers USB Ethernet for the initial login. Add your SSH public
key before building if you want to use that link.

1. Back up the tablet and keep a matching stock firmware package for recovery.
   Unlock Xiaomi's bootloader and keep it unlocked. Flashing `userdata` erases
   Android's data, which is shared across slots.
2. Build the initial root filesystem and the U-Boot image from the same
   configuration, using an aarch64 Nix builder.

   ```sh
   nix build 'path:.#nixosConfigurations.xun.config.system.build.xunRootImage' -o result-root
   nix build 'path:.#nixosConfigurations.xun.config.system.build.xunBootImage' -o result-boot
   ```

3. Enter bootloader fastboot with Power + Volume Down. Check that the product
   is `xun` before flashing. Leave `vendor_boot`, `init_boot`, `dtbo`,
   `vbmeta`, and the Android bootloader partitions stock.

   ```sh
   fastboot getvar product
   fastboot -S 256M flash userdata result-root
   fastboot boot result-boot/boot.img
   # After a successful test boot, return to fastboot and install U-Boot.
   fastboot flash boot_a result-boot/boot.img
   fastboot set_active a
   fastboot reboot
   ```

4. On first boot the example expands ext4 to fill `userdata` and registers the
   Nix store. If you enabled the example's SSH login, set the computer's USB
   Ethernet interface to `172.16.42.2/24` and connect with
   `ssh root@172.16.42.1`. After verifying the flashed slot A boots, run
   `sudo qbootctl -m a` once to confirm the Android boot slot.

## Deploy and roll back

Xiaomi's bootloader starts U-Boot through the Android v4 shim. U-Boot loads
`/boot/extlinux/extlinux.conf` from the internal `userdata` filesystem
and shows the NixOS generation menu. The stock NixOS extlinux module
manages the menu and stores the kernel, initrd, and DTB for each entry
under `/boot/nixos`.

Deploy with deploy-rs or `nixos-rebuild switch` and reboot to load the new
kernel. To roll back, select an older generation in the boot menu or use
`nixos-rebuild switch --rollback` and reboot. Kernel updates leave the
Android boot partition alone. Updates to U-Boot itself still require
rebuilding and flashing `xunBootImage`.

If migrating from the earlier A/B setup on internal storage, activate this
configuration first to populate `/boot`. Then test or flash `xunBootImage`
as above. The existing root filesystem can be reused.

The U-Boot chain and menu input are experimental on `xun`. Keep fastboot
available and test with `fastboot boot` before flashing U-Boot.
