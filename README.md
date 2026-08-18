# Pillarius-live

Live ISO build configuration for Pillarius OS, built with
[live-build](https://live-team.pages.debian.net/live-manual/). Produces
`minimal` and `full` variants that boot to the Pillarius desktop and include a
Debian installer with an automated preseed option.

ISOs are published to [PillarTree/Pillarius](https://github.com/PillarTree/Pillarius).

## Requirements

- Ubuntu 24.04 (tested) or Debian
- `live-build` (3.0~a57), `syslinux`, `sudo`

## Build

```sh
./build.sh all
```

`build.sh` first runs `patch-lb-debian-installer.sh` to fix live-build 3.0~a57
quirks on trixie, then builds both variants with `lb build` and writes
`output/pillarius-<variant>-<date>-amd64.iso` plus SHA-256 checksums.

The builds run with `sudo` and take a while; the output ISOs are gitignored.

## Patch script

`patch-lb-debian-installer.sh` patches the installed live-build scripts:

- replaces the hardcoded `lilo grub linux-image-2.6-amd64` debian-installer
  packages with `grub-pc`, and installs `grub-efi-amd64` in a separate apt run
  (the two conflict in a single invocation)
- creates the missing `data/debian-cd/trixie/amd64_netinst_udeb_include` file
  required by `lb_binary_disk`

It must be re-run after a live-build package upgrade.

## Layout

- `pillarius-live/minimal`, `pillarius-live/full` — `lb config` output and
  per-variant config (`auto/config`, `config/`): package lists, includes,
  bootloader menus, and the debian-installer preseed
- `pillarius-live/minimal/config/bootloaders/isolinux/install.cfg` — installer
  boot menu (install / automatic install / expert / rescue)
- `config/includes.binary_debian-installer/preseed.cfg` — unattended install:
  creates the `user` account (password `pillarius`), installs pillarium,
  spacer-greeter and cadet from [pt-apt-repo](https://github.com/spacey32/pt-apt-repo)
  (full variant also installs audio, bluetooth, network and browser packages)

## Publish

Upload the ISOs and update the downloads page from
[Pillarius-downloads](https://github.com/PillarTree/Pillarius) via its
`publish.sh` (replaces same-named release assets when checksums differ).