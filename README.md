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

## Provision the example host

[examples/xun.nix](examples/xun.nix) defines a headless host with an ext4 microSD root and a USB Ethernet link for first login. Add your public SSH key before building.

1. Back up the tablet before unlocking. Unlock Xiaomi's bootloader using the procedure for your tablet. Unlocking can erase Android userdata. Keep stock slot A and the matching stock images available for recovery.
2. On an `aarch64-linux` NixOS machine, build the example system and its boot image from the same configuration. An aarch64 remote builder can also produce the two outputs.

   ```sh
   nix build 'path:.#nixosConfigurations.xun.config.system.build.toplevel' -o result-system
   nix build 'path:.#nixosConfigurations.xun.config.system.build.xunBootImage' -o result-boot
   ```

3. Create a partition on a spare microSD card and verify its path with `lsblk`. The following formats that partition. Replace `/dev/SD_PARTITION` with the actual **microSD partition**, then install the closure with `nixos-install` from a NixOS system with aarch64 execution support.

   ```sh
   sudo mkfs.ext4 -L NIXOS_XUN /dev/SD_PARTITION
   sudo mount /dev/SD_PARTITION /mnt
   sudo nixos-install --root /mnt --system "$(readlink -f result-system)" \
     --no-bootloader --no-root-passwd
   sudo umount /mnt
   ```

4. Insert the card. Enter bootloader fastboot with Power + Volume Down, connect USB, and verify the product and active slot. Try a temporary boot first.

   ```sh
   fastboot getvar product
   fastboot getvar current-slot
   fastboot boot result-boot/boot.img
   ```

5. In the example, set the USB Ethernet interface on the host to `172.16.42.2/24` and connect with `ssh root@172.16.42.1`. Verify the root mount, display, touch, radios and reboot before flashing.

## Bootloader, updates and recovery

The image uses Xiaomi's existing Android bootloader and the [tapas v4 shim](https://github.com/Sype0/pmos-tapas/tree/5dee84cc5d7939a1042cf9daf2a21e67ab5c3579). The shim supplies the xun DTB and passes the NixOS initrd to Linux. The output fits within the stock 96 MiB boot partition or fails with a size error. Leave `vendor_boot`, `init_boot`, `dtbo`, `vbmeta`, and the Android bootloader partitions stock. There is no GRUB or systemd-boot menu in this setup.

After the temporary boot succeeds, verify that slot A is your stock Android slot and that slot B can be overwritten. From bootloader fastboot:

```sh
fastboot flash boot_b result-boot/boot.img
fastboot set_active b
fastboot reboot
```

After verifying the flashed system boots, run `qbootctl -m` as root on the tablet to mark the current slot successful. The example includes `qbootctl`. Check the slot with `qbootctl` before marking it. To return to Android, enter fastboot, run `fastboot set_active a`, and reboot. Keep the bootloader unlocked while running the custom image.

The boot image embeds the exact NixOS system generation's init path. For updates, build both outputs, install the new closure to the card before flashing its matching boot image, and retain the previous closure and image together for rollback. A normal NixOS activation does not update `boot_b`. For an eMMC install, supply your own suitable root partition in `fileSystems."/".device`. Android's `userdata` is shared across slots, so repurposing it also erases Android's data and can prevent Android from starting.

The NixOS configuration and boot image derivation have been evaluated. Compilation and tablet boot still need testing.
