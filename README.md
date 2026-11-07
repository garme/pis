# Slackware Post-Install Scripts (PIS)

> Let the Slackers be a little bit lazy. ;)

PIS is a `dialog`-based assistant for selected Slackware 15.0
post-installation tasks. Version 0.3.0 keeps Slackware's traditional tools
and configuration files visible while adding validation, automatic backups,
restoration, system status and portable profiles.

## Features

- Configure the system locale and console/X keyboard layouts.
- Select CLI or GUI login and the default `startx` session.
- Add users without storing passwords and configure wheel administration.
- Publish installed Huge and Generic kernels to an existing ELILO setup.
- Select a Slackware 15.0 `slackpkg` mirror by URL.
- Install and configure supported `slackpkg+`, `sbopkg` and slapt tools.
- Back up every changed configuration file and restore it from the menu.
- Export and validate versioned profiles that never contain passwords.
- Inspect the recorded configuration and run compatibility checks.

PIS does not replace Slackware's network and service configuration tools.
Those tasks remain with the native Slackware utilities.

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
passwords. Configure or inspect the system with PIS 0.3.0 and export a new
profile.

See `doc/README` and `man pis` for full details.

## Development check

```text
$ tests/run-tests.sh
```

## License

Copyright (c) 2022-2026 Guilherme Esmeraldo. PIS is distributed under the
GNU General Public License, version 3 or later.
