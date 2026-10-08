#!/usr/bin/env python3
"""Copy the ISO's patched GRUB config into the embedded UEFI boot image.

mkksiso --skip-mkefiboot updates /EFI/BOOT on the ISO9660 tree. UEFI boot
uses the FAT image appended as partition 2, so that copy is what the menu
actually shows. mtools updates it without losetup.
"""

import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

EFI_GUID = "C12A7328-F81F-11D2-BA4B-00A0C93EC93B"
CFG_NAMES = ("grub.cfg", "BOOT.conf")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(cmd, check=False, text=True, **kwargs)
    if result.returncode != 0:
        if result.stderr:
            sys.stderr.write(result.stderr)
        sys.exit(f"command failed ({result.returncode}): {' '.join(cmd)}")
    return result


def efi_partition(iso: Path) -> tuple[int, int]:
    report = run(
        ["xorriso", "-indev", str(iso), "-report_el_torito", "as_mkisofs"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    ).stdout
    match = re.search(r"appended_partition_2_start_(\d+)s_size_(\d+)d", report)
    if not match:
        sys.exit(f"{iso} has no appended EFI partition")
    start = int(match.group(1)) * 2048
    size = int(match.group(2)) * 512
    return start, size


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} kickstart.iso")
    iso = Path(sys.argv[1]).resolve()
    if not iso.is_file():
        sys.exit(f"missing {iso}")

    start, size = efi_partition(iso)
    with tempfile.TemporaryDirectory(prefix="efiboot-") as tmp:
        work = Path(tmp)
        fat = work / "efiboot.img"
        with iso.open("rb") as src, fat.open("wb") as dst:
            src.seek(start)
            blob = src.read(size)
            if len(blob) != size:
                sys.exit("short read of the EFI partition")
            dst.write(blob)

        for name in CFG_NAMES:
            extracted = work / name
            run(
                [
                    "xorriso",
                    "-osirrox",
                    "on",
                    "-indev",
                    str(iso),
                    "-extract",
                    f"/EFI/BOOT/{name}",
                    str(extracted),
                ],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
            run(["mcopy", "-o", "-i", str(fat), str(extracted), f"::/EFI/BOOT/{name}"])

        menu = run(
            ["mtype", "-i", str(fat), "::/EFI/BOOT/grub.cfg"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout
        if 'set default="0"' not in menu or "set timeout=0" not in menu:
            sys.exit("EFI grub.cfg is not the automated install menu")
        if "rd.live.check" in menu:
            sys.exit("EFI grub.cfg still runs the media check")

        rebuilt = iso.with_name(iso.name + ".rebuilt")
        if rebuilt.exists():
            rebuilt.unlink()
        run(
            [
                "xorriso",
                "-indev",
                str(iso),
                "-outdev",
                str(rebuilt),
                "-boot_image",
                "any",
                "replay",
                "-append_partition",
                "2",
                EFI_GUID,
                str(fat),
            ]
        )
        run(["implantisomd5", str(rebuilt)])
        os.replace(rebuilt, iso)


if __name__ == "__main__":
    main()
