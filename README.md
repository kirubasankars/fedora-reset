# Fedora Server kickstart

Builds an unattended Fedora Server 44 netinstall ISO. Booting it wipes the target disk and installs a small system that can restore itself from a snapshot.

## Build

Put the Fedora Server netinstall ISO in the repo root. The default name is `Fedora-Server-netinst-x86_64-44-1.7.iso`.

```sh
make deps
cp config.local.mk.example config.local.mk   # optional overrides
make iso
```

The result is `out/Fedora-Server-netinst-x86_64-44-kickstart.iso`. It boots straight into the install: no media check and no menu wait.

`make iso` and `make image` describe a kickstart that erases disks. `BOOT_DRIVE` in `config.local.mk` limits that to one disk, and only if the installer sees that exact name. Leave it empty for a VM.

| Target | What it does |
| --- | --- |
| `make ks` | Render the kickstart into `out/` |
| `make validate` | Check the kickstart syntax |
| `make iso` | Build the kickstart ISO |
| `make image` | Install a qcow2 with livemedia-creator |
| `make verify-src` | Check the source ISO checksum |
| `make clean` | Remove `out/` |

Overrides go in `config.local.mk`. See `config.local.mk.example`. Assignments on the command line win: `make iso HOSTNAME=fileserver`. Leave `HOSTNAME` unset and each install chooses its own name, such as `fedora-a1b2c3`.

## Installed system

The login user is `agent`, created from `secrets/id_ed25519.pub`, with passwordless sudo. The console shows the current IPv4 address. Cockpit and firewalld are disabled. Podman is installed and its socket is enabled. Docker CE (the current stable release), Buildx, and Compose are installed from Docker's Fedora repository, the `docker` service is enabled, and `agent` is in the `docker` group.

`/` is XFS, labeled `PRIMARY_ROOT`, and grows to fill the disk. A 32 GiB XFS volume labeled `RECOVER_DATA` is mounted at `/mnt/recovery_data`. `/opt` is a directory on `/`.

After the packages are installed, the kickstart upgrades the system, restores SELinux labels, and takes the recovery snapshot.

## Factory reset

`/usr/local/sbin/update-baseline.sh` freezes `/` and stores a sparse image on the recovery volume. `auto-reset.sh` installs a boot hook that looks for `/reset_me`.

```sh
sudo mkdir /data
sudo touch /reset_me
sudo reboot
```

On the next boot the hook copies the snapshot back onto `/` and reboots again. `/data` and `/reset_me` are gone, because they were not in the snapshot. Refresh the snapshot after intentional changes:

```sh
sudo /usr/local/sbin/update-baseline.sh
```

Run that only when `/` is the system you want to keep. It removes `/reset_me` and replaces the snapshot.

## Layout

| Path | Role |
| --- | --- |
| `kickstart/fedora-server.ks.in` | Kickstart template. Tokens are `@NAME@`. |
| `kickstart/recovery/` | Scripts copied to `/usr/local/sbin` and onto the ISO. |
| `scripts/` | Render, validate, and rebuild the EFI boot image. |
| `mk/` | Make rules and default settings. |
| `secrets/` | SSH public key. Not committed. |
