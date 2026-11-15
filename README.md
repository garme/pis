# Slackware Post-Install Scripts (PIS)

> Let the Slackers be a little bit lazy. ;)

PIS is a `dialog`-based assistant for selected Slackware 15.0 and
Slackware-current post-installation tasks on x86 and x86_64. Version 0.5.0
keeps Slackware's traditional tools
and configuration files visible while adding validation, automatic backups,
restoration, system status and portable profiles.

## Features

- Configure the system locale and console/X keyboard layouts.
- Run Slackware's native `timeconfig` and optionally configure NTP time
  synchronization through `rc.ntpd`.
- Select CLI or GUI login and the default `startx` session.
- Add users without storing passwords and configure wheel administration.
- Publish installed Huge and Generic kernels through ELILO, LILO or GRUB.
- Select explicitly which configured bootloader to update when several coexist.
- Create explicit GRUB entries only for the selected PIS kernels and choose the
  default PIS entry; GRUB's automatic entries remain available as fallbacks.
- Create compact low-memory initrds for 32-bit LILO systems with legacy BIOS.
- Select a matching Slackware 15.0 or current `slackpkg` mirror by URL.
- Install and configure supported `slackpkg+`, `sbopkg` and slapt tools.
- Back up every changed configuration file and restore it from the menu.
- Export and validate versioned profiles that never contain passwords.
- Inspect the recorded configuration and run compatibility checks.

PIS does not replace Slackware's general network and service configuration
tools. The date/time module integrates the native `timeconfig` and `rc.ntpd`.

## Running

Install the Slackware package and run PIS as root:

```text
# pis
```

Useful command-line actions:

```text
# pis --check
# pis --output workstation.pis
# pis --file workstation.pis
# pis --restore
```

Version 0.2 profiles are rejected because they may contain plaintext
passwords. Configure or inspect the system with PIS 0.5.0 and export a new
profile.

## Compatibility

PIS detects Slackware 15.0 or current from the active slackpkg mirror and
`/etc/slackware-version`, and supports x86 and x86_64. Repository choices are
filtered for the detected combination; multilib is offered only on x86_64.
Prebuilt slapt-get, GSlapt and slapt-src installers remain limited to 15.0.
On current, an already installed compatible slapt-get can still be configured.

See `doc/README` and `man pis` for full details.

## Development check

```text
$ tests/run-tests.sh
```

## License

Copyright (c) 2022-2026 Guilherme Esmeraldo. PIS is distributed under the
GNU General Public License, version 3 or later.
