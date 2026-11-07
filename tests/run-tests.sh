#!/bin/bash
set -u

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/pis-tests.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

export PIS_ROOT="$test_root/root"
export PIS_DIR="$test_root/state"
export PIS_BACKUP_DIR="$PIS_DIR/backups"
export PIS_ALLOW_UNPRIVILEGED=1
export PATH="$project_dir/tests/fixtures:$PATH"
. "$project_dir/pis_lib"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
assert_contains() { grep -Fq "$2" "$1" || fail "$1 does not contain $2"; }
assert_not_contains() { ! grep -Fq "$2" "$1" || fail "$1 unexpectedly contains $2"; }

mkdir -p "$PIS_ROOT/etc/profile.d" "$PIS_ROOT/etc/rc.d" \
    "$PIS_ROOT/etc/X11/xinit" "$PIS_ROOT/etc/X11/xorg.conf.d" \
    "$PIS_ROOT/etc/slackpkg" "$PIS_ROOT/usr/share/kbd/keymaps/i386/qwerty" \
    "$PIS_ROOT/usr/share/X11/xkb/rules" "$PIS_DIR" "$PIS_BACKUP_DIR"
touch "$PIS_BACKUP_INDEX"

printf 'export LANG=en_US.UTF-8\n' > "$PIS_ROOT/etc/profile.d/lang.sh"
printf 'setenv LANG en_US.UTF-8\n' > "$PIS_ROOT/etc/profile.d/lang.csh"
printf 'id:3:initdefault:\n' > "$PIS_ROOT/etc/inittab"
printf '# %%wheel ALL=(ALL:ALL) ALL\n' > "$PIS_ROOT/etc/sudoers"
printf '  /usr/bin/loadkeys us.map.gz\n' > "$PIS_ROOT/etc/rc.d/rc.keymap"
touch "$PIS_ROOT/usr/share/kbd/keymaps/i386/qwerty/br-abnt2.map.gz"
printf 'startxfce4\n' > "$PIS_ROOT/etc/X11/xinit/xinitrc.xfce"
ln -s xinitrc.xfce "$PIS_ROOT/etc/X11/xinit/xinitrc"
printf '! layout\n  us English\n  br Portuguese (Brazil)\n! variant\n  abnt2 br: ABNT2\n! option\n' > "$PIS_ROOT/usr/share/X11/xkb/rules/base.lst"
printf '# https://mirror.example/slackware/slackware64-15.0/\nhttps://old.example/slackware/slackware64-15.0/\n# https://mirror.example/slackware/slackware64-current/\n' > "$PIS_ROOT/etc/slackpkg/mirrors"

pis_apply_login_mode GUI || fail "GUI login application failed"
assert_contains "$PIS_ROOT/etc/inittab" 'id:4:initdefault:'
[ -s "$PIS_BACKUP_INDEX" ] || fail "login change did not create a backup"

before="$(cat "$PIS_ROOT/etc/inittab")"
pis_apply_login_mode INVALID >/dev/null 2>&1 && fail "invalid login mode was accepted"
[ "$(cat "$PIS_ROOT/etc/inittab")" = "$before" ] || fail "invalid login mode changed inittab"

pis_apply_locale C || fail "locale application failed"
assert_contains "$PIS_ROOT/etc/profile.d/lang.sh" 'export LANG=C'
assert_contains "$PIS_ROOT/etc/profile.d/lang.csh" 'setenv LANG C'

pis_apply_wheel YES || fail "wheel activation failed"
assert_contains "$PIS_ROOT/etc/sudoers" '%wheel ALL=(ALL:ALL) ALL'

pis_apply_console_keymap br-abnt2.map.gz || fail "console keymap application failed"
assert_contains "$PIS_ROOT/etc/rc.d/rc.keymap" 'loadkeys br-abnt2.map.gz'

pis_apply_desktop xinitrc.xfce || fail "desktop application failed"
[ "$(readlink "$PIS_ROOT/etc/X11/xinit/xinitrc")" = xinitrc.xfce ] || fail "desktop symlink is incorrect"

pis_apply_x_keyboard br abnt2 || fail "X keyboard application failed"
assert_contains "$PIS_ROOT/etc/X11/xorg.conf.d/90-keyboard-layout-evdev.conf" 'Option "XkbLayout" "br"'
assert_contains "$PIS_ROOT/etc/X11/xorg.conf.d/90-keyboard-layout-evdev.conf" 'Option "XkbVariant" "abnt2"'

mirror='https://mirror.example/slackware/slackware64-15.0/'
pis_apply_slackpkg_mirror "$mirror" || fail "mirror application failed"
[ "$(grep -Fxc "$mirror" "$PIS_ROOT/etc/slackpkg/mirrors")" -eq 1 ] || fail "selected mirror is not uniquely active"
pis_apply_slackpkg_mirror 'https://mirror.example/slackware/slackware64-current/' >/dev/null 2>&1 && fail "current mirror was accepted"

pis_state_write user testuser
pis_state_write user_wheel YES
pis_state_write slackpkg_mirror "$mirror"
profile="$test_root/profile.conf"
PIS_SBIN="$project_dir" "$project_dir/pis_autoconfig_save_file" "$profile" >/dev/null || fail "profile export failed"
assert_contains "$profile" 'PIS_PROFILE_VERSION=1'
assert_contains "$profile" 'user=testuser'
assert_not_contains "$profile" 'password'

printf '# PIS portable configuration profile\nPIS_PROFILE_VERSION=1\nlogin=CLI\n' > "$test_root/apply.conf"
PIS_SBIN="$project_dir" "$project_dir/pis_autoconfig_load_file" "$test_root/apply.conf" >/dev/null || fail "profile import failed"
assert_contains "$PIS_ROOT/etc/inittab" 'id:3:initdefault:'

original="$PIS_ROOT/etc/inittab"
backup="$(awk -F '\t' '$3 ~ /inittab$/ {print $4; exit}' "$PIS_BACKUP_INDEX")"
[ -n "$backup" ] || fail "inittab backup was not indexed"
pis_restore_backup "$backup" "$original" || fail "backup restoration failed"
assert_contains "$original" 'id:3:initdefault:'

for script in "$project_dir"/pis "$project_dir"/pis_*; do
    bash -n "$script" || fail "syntax error in $(basename "$script")"
done

printf 'All PIS tests passed.\n'
