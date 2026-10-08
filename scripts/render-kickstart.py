#!/usr/bin/env python3
"""Render kickstart/fedora-server.ks.in into an Anaconda kickstart."""

import argparse
import os
import re
import secrets
import stat
import subprocess
import sys
from pathlib import Path

TOKEN_RE = re.compile(r"@([A-Z][A-Z0-9_]*)@")
USER_RE = re.compile(r"^[a-z_][a-z0-9_-]{0,31}$")
DRIVE_RE = re.compile(r"^[A-Za-z0-9._-]+$")
HOSTNAME_RE = re.compile(r"^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$")


def hash_password(password: str) -> str:
    result = subprocess.run(
        ["openssl", "passwd", "-6", "-stdin"],
        input=password.encode(),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        sys.stderr.write(result.stderr.decode())
        sys.exit("openssl passwd failed while hashing a password file")
    hashed = result.stdout.decode().strip()
    if not hashed.startswith("$6$"):
        sys.exit("openssl did not return a SHA-512 crypt hash")
    return hashed


def read_secret(path: Path) -> str:
    if not path.is_file():
        return ""
    mode = stat.S_IMODE(path.stat().st_mode)
    if mode & 0o077:
        print(f"warning: {path} is readable by group or other users", file=sys.stderr)
    text = path.read_text().replace("\r\n", "\n").removesuffix("\n")
    if not text:
        sys.exit(f"{path} is empty")
    return text


def quote_kickstart(value: str) -> str:
    if "'" in value:
        sys.exit("password hash contains a single quote; refusing to render kickstart")
    return f"'{value}'"


def auth_commands(args: argparse.Namespace) -> str:
    if args.dummy:
        admin_password = secrets.token_hex(16)
        root_password = ""
        pubkeys = []
    else:
        admin_password = read_secret(Path(args.admin_password_file))
        root_password = read_secret(Path(args.root_password_file))
        pubkey_path = Path(args.admin_pubkey_file)
        pubkeys = []
        if pubkey_path.is_file():
            for line in pubkey_path.read_text().splitlines():
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if '"' in line:
                    sys.exit(f"SSH public key in {pubkey_path} contains a double quote")
                pubkeys.append(line)

    if not admin_password and not pubkeys and not root_password:
        sys.exit(
            "No login secret found. Create at least one of:\n"
            f"  {args.admin_password_file}\n"
            f"  {args.admin_pubkey_file}\n"
            f"  {args.root_password_file}"
        )
    if not USER_RE.fullmatch(args.admin_user):
        sys.exit(f"invalid ADMIN_USER {args.admin_user!r}")

    lines = []
    if root_password:
        # Root SSH stays off when an admin user exists. Allow it only when
        # root is the sole login, so the installed system is reachable.
        allow_ssh = "" if (admin_password or pubkeys) else " --allow-ssh"
        lines.append(f"rootpw --iscrypted {quote_kickstart(hash_password(root_password))}{allow_ssh}")
    else:
        lines.append("rootpw --lock")

    if admin_password or pubkeys:
        if admin_password:
            lines.append(
                "user "
                f"--name={args.admin_user} --groups=wheel --iscrypted "
                f"--password={quote_kickstart(hash_password(admin_password))}"
            )
        else:
            lines.append(f"user --name={args.admin_user} --groups=wheel --lock")
        for key in pubkeys:
            lines.append(f'sshkey --username={args.admin_user} "{key}"')
    return "\n".join(lines)


def bootloader(boot_drive: str) -> str:
    command = 'bootloader --timeout=1 --append="console=tty0 console=ttyS0,115200n8 rd.lvm.lv=fedora/recovery"'
    if boot_drive:
        command += f" --boot-drive={boot_drive}"
    return command


def install_partitioning(boot_drive: str, root_size: int, swap_size: int, recovery_size: int) -> str:
    lines = []
    clearpart = "clearpart --all --initlabel --disklabel=gpt"
    if boot_drive:
        if not DRIVE_RE.fullmatch(boot_drive):
            sys.exit(f"invalid BOOT_DRIVE {boot_drive!r}")
        lines.append(f"ignoredisk --only-use={boot_drive}")
        clearpart += f" --drives={boot_drive}"
    # The PV fills the disk. Recovery is fixed; / takes the rest.
    lines.extend(
        [
            "zerombr",
            clearpart,
            "reqpart --add-boot",
            "part pv.01 --fstype=lvmpv --size=1024 --grow",
            "volgroup fedora pv.01",
            f"logvol swap --vgname=fedora --name=swap --fstype=swap --size={swap_size}",
            (
                "logvol /mnt/recovery_data --vgname=fedora --name=recovery "
                f"--fstype=xfs --size={recovery_size} --label=RECOVER_DATA"
            ),
            (
                "logvol / --vgname=fedora --name=root --fstype=xfs "
                f"--size={root_size} --grow --label=PRIMARY_ROOT"
            ),
        ]
    )
    return "\n".join(lines)


def image_partitioning(root_size: int, swap_size: int, recovery_size: int, uefi: bool) -> str:
    lines = [
        "zerombr",
        "clearpart --all --initlabel --disklabel=gpt",
    ]
    if uefi:
        lines.append("part /boot/efi --fstype=efi --size=600")
    else:
        lines.append("part biosboot --fstype=biosboot --size=1")
    lines.extend(
        [
            "part /boot --fstype=xfs --size=1024",
            f"part swap --fstype=swap --size={swap_size}",
            (
                f"part /mnt/recovery_data --fstype=xfs --size={recovery_size} "
                "--label=RECOVER_DATA"
            ),
            f"part / --fstype=xfs --size={root_size} --label=PRIMARY_ROOT",
        ]
    )
    return "\n".join(lines)


def recovery_install(recovery_dir: Path) -> str:
    scripts = ("auto-reset.sh", "update-baseline.sh")
    missing = [name for name in scripts if not (recovery_dir / name).is_file()]
    if missing:
        sys.exit(f"missing recovery script(s) in {recovery_dir}: {', '.join(missing)}")
    lines = ["install -d -m 0755 /usr/local/sbin"]
    for name in scripts:
        body = (recovery_dir / name).read_text()
        delimiter = "RECOVERY_SCRIPT"
        while delimiter in body:
            delimiter += "_X"
        lines.append(f"cat > /usr/local/sbin/{name} <<'{delimiter}'")
        lines.append(body.rstrip("\n"))
        lines.append(delimiter)
        lines.append(f"chmod 0755 /usr/local/sbin/{name}")
    return "\n".join(lines)


def render(args: argparse.Namespace) -> str:
    if args.hostname and not HOSTNAME_RE.fullmatch(args.hostname):
        sys.exit(f"invalid HOSTNAME {args.hostname!r}")
    if args.hostname:
        hostname_option = f" --hostname={args.hostname}"
        hostname_setup = ""
    else:
        # Chosen here, not when the ISO is built, so two installs differ.
        hostname_option = ""
        hostname_setup = "\n".join(
            [
                "name=$(python3 -c 'import secrets; print(\"fedora-\" + secrets.token_hex(3))')",
                "printf '%s\\n' \"$name\" > /etc/hostname",
            ]
        )
    if args.layout == "install":
        partitioning = install_partitioning(
            args.boot_drive, args.root_size_mb, args.swap_size_mb, args.recovery_size_mb
        )
        finish = "reboot --eject"
        drive = args.boot_drive
        install_source = (
            "url --url=https://download.fedoraproject.org/pub/fedora/linux/releases/"
            f"{args.fedora_release}/Server/x86_64/os/\n"
            "repo --name=everything --baseurl=https://download.fedoraproject.org/pub/fedora/linux/releases/"
            f"{args.fedora_release}/Everything/x86_64/os/"
        )
    elif args.layout == "image":
        # livemedia-creator sizes the disk from part --size and cannot use autopart.
        # The guest disk name is not the host BOOT_DRIVE, so ignore that setting.
        partitioning = image_partitioning(
            args.root_size_mb, args.swap_size_mb, args.recovery_size_mb, args.uefi
        )
        finish = "shutdown"
        drive = ""
        install_source = (
            "cdrom\n"
            "repo --name=everything --baseurl=https://download.fedoraproject.org/pub/fedora/linux/releases/"
            f"{args.fedora_release}/Everything/x86_64/os/"
        )
    else:
        sys.exit(f"unknown layout {args.layout!r}")

    template = Path(args.template).read_text()
    values = {
        "FEDORA_RELEASE": args.fedora_release,
        "TIMEZONE": args.timezone,
        "HOSTNAME_OPTION": hostname_option,
        "HOSTNAME_SETUP": hostname_setup,
        "ADMIN_USER": args.admin_user,
        "AUTH": auth_commands(args),
        "BOOTLOADER": bootloader(drive),
        "PARTITIONING": partitioning,
        "INSTALL_SOURCE": install_source,
        "RECOVERY_INSTALL": recovery_install(Path(args.recovery_dir)),
        "FINISH": finish,
    }

    def replace(match: re.Match[str]) -> str:
        name = match.group(1)
        if name not in values:
            sys.exit(f"unknown kickstart token @{name}@")
        return values[name]

    rendered = TOKEN_RE.sub(replace, template)
    if TOKEN_RE.search(rendered):
        sys.exit("unreplaced kickstart tokens remain")
    if not rendered.endswith("\n"):
        rendered += "\n"
    return rendered


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--template", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--layout", choices=("install", "image"), required=True)
    parser.add_argument("--fedora-release", default=os.environ.get("FEDORA_RELEASE", "43"))
    parser.add_argument("--hostname", default="")
    parser.add_argument("--timezone", default=os.environ.get("TIMEZONE", "UTC"))
    parser.add_argument("--admin-user", default=os.environ.get("ADMIN_USER", "agent"))
    parser.add_argument("--boot-drive", default=os.environ.get("BOOT_DRIVE", ""))
    parser.add_argument("--root-size-mb", type=int, default=int(os.environ.get("ROOT_SIZE_MB", "12288")))
    parser.add_argument("--swap-size-mb", type=int, default=int(os.environ.get("SWAP_SIZE_MB", "2048")))
    parser.add_argument("--recovery-size-mb", type=int, default=int(os.environ.get("RECOVERY_SIZE_MB", "32768")))
    parser.add_argument("--admin-password-file", default=os.environ.get("ADMIN_PASSWORD_FILE", "secrets/admin.password"))
    parser.add_argument("--root-password-file", default=os.environ.get("ROOT_PASSWORD_FILE", "secrets/root.password"))
    parser.add_argument("--admin-pubkey-file", default=os.environ.get("ADMIN_PUBKEY_FILE", "secrets/id_ed25519.pub"))
    parser.add_argument("--recovery-dir", default="kickstart/recovery")
    parser.add_argument("--uefi", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--dummy", action="store_true", help="syntax-check creds; do not use the output to install")
    args = parser.parse_args()
    if args.root_size_mb < 4096 or args.swap_size_mb < 512 or args.recovery_size_mb < 8192:
        sys.exit(
            "ROOT_SIZE_MB must be at least 4096, SWAP_SIZE_MB at least 512, "
            "and RECOVERY_SIZE_MB at least 8192"
        )
    return args


def main() -> None:
    args = parse_args()
    output = Path(args.output)
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(render(args))
    os.chmod(output, 0o600)


if __name__ == "__main__":
    main()
