"""Extend the tapas payload descriptor with the NixOS initrd location."""

import struct
import sys
from pathlib import Path

DESC_OFF = 0x1000
DTB_OFF = 0x2000
KERNEL_OFF = 0x200000
ALIGNMENT = 4096
# The first reserved region above the shim's primary kernel destination.
MAX_RELOCATED_SIZE = 0x9B01000
BOOT_PARTITION_SIZE = 96 * 1024 * 1024


def main():
    payload_path, initrd_path = map(Path, sys.argv[1:])
    payload = bytearray(payload_path.read_bytes())
    kernel_size, kernel_mem, _, dtb_size = struct.unpack_from(
        "<4Q", payload, DESC_OFF + 16
    )
    initrd = initrd_path.read_bytes()
    start = (max(kernel_size, kernel_mem) + ALIGNMENT - 1) & -ALIGNMENT
    end = start + len(initrd)
    copy_size = (end + ALIGNMENT - 1) & -ALIGNMENT
    if copy_size > MAX_RELOCATED_SIZE:
        sys.exit("kernel and initrd exceed the shim's relocation area")
    # v4 header and the separately packed, empty Android ramdisk each use a page.
    if KERNEL_OFF + copy_size + 2 * ALIGNMENT > BOOT_PARTITION_SIZE:
        sys.exit("kernel and initrd exceed the xun 96 MiB boot partition")

    dtb = payload[DTB_OFF : DTB_OFF + dtb_size]
    offsets = []
    for marker in (0x13716A5E, 0x29D53B78):
        needle = struct.pack(">I", marker)
        offset = dtb.find(needle)
        if offset < 0 or offset % 4 or dtb.count(needle) != 1:
            sys.exit("could not locate a unique aligned initrd marker in the DTB")
        offsets.append(offset)

    del payload[KERNEL_OFF + kernel_size :]
    payload.extend(bytes(start - kernel_size))
    payload.extend(initrd)
    payload.extend(bytes(copy_size - end))
    struct.pack_into("<Q", payload, 16, len(payload))
    struct.pack_into("<2Q", payload, DESC_OFF + 16, copy_size, copy_size)
    struct.pack_into("<4Q", payload, DESC_OFF + 48, start, end, *offsets)
    payload_path.write_bytes(payload)


if __name__ == "__main__":
    main()
