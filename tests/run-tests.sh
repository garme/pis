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
    "$PIS_ROOT/usr/share/X11/xkb/rules" "$PIS_ROOT/boot" "$PIS_DIR" "$PIS_BACKUP_DIR"
touch "$PIS_BACKUP_INDEX"
chmod 755 "$project_dir/tests/fixtures/grub-mkconfig" \
    "$project_dir/tests/fixtures/grub-script-check" \
    "$project_dir/tests/fixtures/grub-probe" \
    "$project_dir/tests/fixtures/grub-mkrelpath" \
    "$project_dir/tests/fixtures/timeconfig"
printf 'Slackware 15.0\n' > "$PIS_ROOT/etc/slackware-version"

printf 'export LANG=en_US.UTF-8\n' > "$PIS_ROOT/etc/profile.d/lang.sh"
printf 'setenv LANG en_US.UTF-8\n' > "$PIS_ROOT/etc/profile.d/lang.csh"
printf 'id:3:initdefault:\n' > "$PIS_ROOT/etc/inittab"
printf '# %%wheel ALL=(ALL:ALL) ALL\n' > "$PIS_ROOT/etc/sudoers"
printf '  /usr/bin/loadkeys us.map.gz\n' > "$PIS_ROOT/etc/rc.d/rc.keymap"
touch "$PIS_ROOT/usr/share/kbd/keymaps/i386/qwerty/br-abnt2.map.gz"
printf 'startxfce4\n' > "$PIS_ROOT/etc/X11/xinit/xinitrc.xfce"
ln -s xinitrc.xfce "$PIS_ROOT/etc/X11/xinit/xinitrc"
printf '! layout\n  us English\n  br Portuguese (Brazil)\n! variant\n  abnt2 br: ABNT2\n! option\n' > "$PIS_ROOT/usr/share/X11/xkb/rules/base.lst"
cat > "$PIS_ROOT/etc/slackpkg/mirrors" <<'EOF'
# https://mirror.example/slackware/slackware-15.0/
# https://mirror.example/slackware/slackware-current/
# https://mirror.example/slackware/slackware64-15.0/
https://old.example/slackware/slackware64-15.0/
# https://mirror.example/slackware/slackware64-current/
EOF

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

printf 'localtime\n' > "$PIS_ROOT/etc/hardwareclock"
printf 'old timezone\n' > "$PIS_ROOT/etc/localtime"
pis_run_timeconfig || fail "Slackware timeconfig integration failed"
[ "$(pis_state_read timezone)" = America/Sao_Paulo ] || fail "timezone state was not recorded"
[ "$(pis_state_read hardware_clock)" = UTC ] || fail "hardware-clock state was not recorded"
awk -F '\t' '$2 == "timeconfig" && $3 ~ /hardwareclock$/ {found=1} END {exit !found}' "$PIS_BACKUP_INDEX" || fail "timeconfig files were not backed up"

printf '# Slackware NTP test configuration\ndriftfile /var/lib/ntp/drift\n' > "$PIS_ROOT/etc/ntp.conf"
printf '#!/bin/bash\nexit 0\n' > "$PIS_ROOT/etc/rc.d/rc.ntpd"
chmod 644 "$PIS_ROOT/etc/rc.d/rc.ntpd"
pis_apply_ntp ENABLE pool.ntp.org || fail "NTP enablement failed"
assert_contains "$PIS_ROOT/etc/ntp.conf" '# BEGIN PIS NTP'
assert_contains "$PIS_ROOT/etc/ntp.conf" 'pool pool.ntp.org iburst'
assert_contains "$PIS_ROOT/etc/ntp.conf" 'restrict source nomodify notrap noquery'
[ -x "$PIS_ROOT/etc/rc.d/rc.ntpd" ] || fail "rc.ntpd was not enabled"
[ "$(pis_state_read ntp_enabled)" = YES ] || fail "enabled NTP state was not recorded"
[ "$(pis_ntp_pool)" = pool.ntp.org ] || fail "managed NTP pool was not detected"
pis_apply_ntp DISABLE || fail "NTP disablement failed"
[ ! -x "$PIS_ROOT/etc/rc.d/rc.ntpd" ] || fail "rc.ntpd was not disabled"
[ "$(pis_state_read ntp_enabled)" = NO ] || fail "disabled NTP state was not recorded"

pis_apply_desktop xinitrc.xfce || fail "desktop application failed"
[ "$(readlink "$PIS_ROOT/etc/X11/xinit/xinitrc")" = xinitrc.xfce ] || fail "desktop symlink is incorrect"

pis_apply_x_keyboard br abnt2 || fail "X keyboard application failed"
assert_contains "$PIS_ROOT/etc/X11/xorg.conf.d/90-keyboard-layout-evdev.conf" 'Option "XkbLayout" "br"'
assert_contains "$PIS_ROOT/etc/X11/xorg.conf.d/90-keyboard-layout-evdev.conf" 'Option "XkbVariant" "abnt2"'

mirror='https://mirror.example/slackware/slackware64-15.0/'
export PIS_RELEASE=15.0 PIS_TEST_ARCH=x86_64
pis_apply_slackpkg_mirror "$mirror" || fail "mirror application failed"
[ "$(grep -Fxc "$mirror" "$PIS_ROOT/etc/slackpkg/mirrors")" -eq 1 ] || fail "selected mirror is not uniquely active"
pis_apply_slackpkg_mirror 'https://mirror.example/slackware/slackware64-current/' >/dev/null 2>&1 && fail "current mirror was accepted"

export PIS_RELEASE=current PIS_TEST_ARCH=x86_64
current64='https://mirror.example/slackware/slackware64-current/'
pis_apply_slackpkg_mirror "$current64" || fail "current x86_64 mirror application failed"
pis_apply_slackpkg_mirror "$mirror" >/dev/null 2>&1 && fail "15.0 mirror was accepted on current"

export PIS_RELEASE=15.0 PIS_TEST_ARCH=i686
stable32='https://mirror.example/slackware/slackware-15.0/'
pis_apply_slackpkg_mirror "$stable32" || fail "15.0 x86 mirror application failed"

export PIS_RELEASE=current PIS_TEST_ARCH=i686
current32='https://mirror.example/slackware/slackware-current/'
pis_apply_slackpkg_mirror "$current32" || fail "current x86 mirror application failed"
[ "$(pis_third_party_repository_url alienbob current x86)" = 'https://slackware.nl/people/alien/sbrepos/current/x86/' ] || fail "current x86 repository URL is incorrect"
pis_third_party_repository_url multilib current x86 >/dev/null 2>&1 && fail "multilib was accepted on x86"
[ "$(pis_third_party_repository_url multilib 15.0 x86_64)" = 'https://slackware.nl/people/alien/multilib/15.0/' ] || fail "15.0 multilib URL is incorrect"

export PIS_RELEASE=15.0 PIS_TEST_ARCH=x86_64
pis_apply_slackpkg_mirror "$mirror" || fail "stable mirror restoration failed"
unset PIS_RELEASE
[ "$(pis_release)" = 15.0 ] || fail "stable release was not detected from the active mirror"
sed -i 's#^https://#\# https://#' "$PIS_ROOT/etc/slackpkg/mirrors"
printf 'Slackware 15.0+\n' > "$PIS_ROOT/etc/slackware-version"
[ "$(pis_release)" = current ] || fail "current was not detected from slackware-version"
printf 'Slackware 15.0\n' > "$PIS_ROOT/etc/slackware-version"
export PIS_RELEASE=15.0
pis_apply_slackpkg_mirror "$mirror" || fail "stable mirror reactivation failed"

printf 'boot = /dev/test\n' > "$PIS_ROOT/etc/lilo.conf"
touch "$PIS_ROOT/boot/vmlinuz-huge-test"
[ "$(pis_detect_bootloader)" = lilo ] || fail "LILO was not detected"
pis_apply_kernels 'vmlinuz-huge-test' || fail "LILO kernel publication failed"
assert_contains "$PIS_ROOT/etc/lilo.conf" '# BEGIN PIS KERNELS'
assert_contains "$PIS_ROOT/etc/lilo.conf" 'image = /boot/vmlinuz-huge-test'
[ "$(pis_lilo_managed_kernels "$PIS_ROOT/etc/lilo.conf")" = vmlinuz-huge-test ] || fail "managed LILO kernel detection failed"

mkdir -p "$PIS_ROOT/lib/modules/5.15.209-smp"
touch "$PIS_ROOT/lib/modules/5.15.209-smp/test.ko"
touch "$PIS_ROOT/boot/vmlinuz-generic-smp-5.15.209_smp"
metadata="$(pis_kernel_metadata vmlinuz-generic-smp-5.15.209_smp)"
[ "$metadata" = $'generic\t5.15.209-smp' ] || fail "x86 SMP kernel metadata is incorrect: $metadata"
printf 'boot = /dev/test\nroot = /dev/sda2\n' > "$PIS_ROOT/etc/lilo.conf"
[ "$(pis_lilo_root_device "$PIS_ROOT/etc/lilo.conf")" = /dev/sda2 ] || fail "existing LILO root device was not preserved"
mkdir -p "$PIS_ROOT/usr/share/mkinitrd"
cat > "$PIS_ROOT/usr/share/mkinitrd/mkinitrd_command_generator.sh" <<'EOF'
#!/bin/bash
while [ "$#" -gt 0 ]; do
    if [ "$1" = -a ]; then
        output="${2#-o }"
        shift 2
    else
        shift
    fi
done
printf 'printf initrd | gzip -c > %q\n' "$output"
EOF
chmod 755 "$PIS_ROOT/usr/share/mkinitrd/mkinitrd_command_generator.sh"
generated_initrd="$PIS_ROOT/boot/initrd-generator-test.gz"
pis_build_initrd 5.15.209-smp "$generated_initrd" >/dev/null || fail "Slackware initrd generator integration failed"
gzip -t "$generated_initrd" || fail "generated initrd fixture is invalid"
pis_build_initrd() {
    printf 'OK: initrd generated\n'
    touch "$2"
}
pis_apply_lilo_kernels 'vmlinuz-generic-smp-5.15.209_smp' >/dev/null || fail "generic SMP LILO publication failed"
assert_not_contains "$PIS_ROOT/etc/lilo.conf" 'OK:'
assert_contains "$PIS_ROOT/etc/lilo.conf" 'initrd = /boot/initrd-pis-5.15.209-smp.gz'
pis_apply_lilo_kernels 'vmlinuz-generic-smp-5.15.209_smp vmlinuz-huge-test' >/dev/null || fail "multiple LILO kernel publication failed"
assert_contains "$PIS_ROOT/etc/lilo.conf" 'image = /boot/vmlinuz-generic-smp-5.15.209_smp'
assert_contains "$PIS_ROOT/etc/lilo.conf" 'image = /boot/vmlinuz-huge-test'
[ "$(pis_lilo_managed_kernels "$PIS_ROOT/etc/lilo.conf" | wc -l)" -eq 2 ] || fail "multiple managed LILO kernels were not preserved"

memory_source="$test_root/lilo-memory-source"
memory_result="$test_root/lilo-memory-result"
printf 'large-memory\nimage = /boot/vmlinuz\n' > "$memory_source"
pis_lilo_set_memory_mode "$memory_source" "$memory_result" LEGACY || fail "legacy LILO memory configuration failed"
assert_contains "$memory_result" '# BEGIN PIS LILO MEMORY'
assert_contains "$memory_result" 'small-memory'
assert_not_contains "$memory_result" 'large-memory'
mkdir -p "$PIS_ROOT/boot/efi/EFI/Slackware"
touch "$PIS_ROOT/boot/efi/EFI/Slackware/elilo.conf"
pis_detect_bootloader >/dev/null 2>&1 && fail "multiple bootloaders were silently resolved"
PIS_BOOTLOADER=elilo
[ "$(pis_detect_bootloader)" = elilo ] || fail "explicit ELILO selection failed"
unset PIS_BOOTLOADER
mkdir -p "$PIS_ROOT/etc/grub.d"
available_bootloaders="$(pis_available_bootloaders)"
printf '%s\n' "$available_bootloaders" | grep -Fxq grub && fail "/etc/grub.d alone was treated as configured GRUB"
mkdir -p "$PIS_ROOT/boot/grub"
touch "$PIS_ROOT/boot/grub/grub.cfg"
[ "$(pis_available_bootloaders | wc -l)" -eq 3 ] || fail "configured bootloader inventory is incorrect"
PIS_BOOTLOADER=grub
[ "$(pis_detect_bootloader)" = grub ] || fail "explicit GRUB selection failed"
unset PIS_BOOTLOADER
touch "$PIS_ROOT/boot/vmlinuz-generic-5.15.209"
mkdir -p "$PIS_ROOT/lib/modules/5.15.209"
touch "$PIS_ROOT/lib/modules/5.15.209/test.ko"
PIS_GRUB_DEFAULT_KERNEL=vmlinuz-generic-smp-5.15.209_smp
export PIS_GRUB_DEFAULT_KERNEL
pis_apply_grub_kernels 'vmlinuz-generic-5.15.209 vmlinuz-generic-smp-5.15.209_smp' >/dev/null || fail "explicit GRUB kernel publication failed"
assert_contains "$PIS_ROOT/etc/grub.d/09_pis" "menuentry 'PIS: Slackware generic-smp-5.15.209_smp'"
assert_contains "$PIS_ROOT/etc/grub.d/09_pis" "set default='pis-vmlinuz-generic-smp-5-15-209_smp'"
assert_contains "$PIS_ROOT/etc/grub.d/09_pis" 'linux /boot/vmlinuz-generic-smp-5.15.209_smp root=/dev/test ro'
assert_contains "$PIS_ROOT/etc/grub.d/09_pis" 'initrd /boot/initrd-pis-5.15.209-smp.gz'
[ "$(grep -c "^menuentry 'PIS:" "$PIS_ROOT/boot/grub/grub.cfg")" -eq 2 ] || fail "GRUB did not contain exactly the selected PIS entries"
[ "$(grep "^menuentry 'PIS:" "$PIS_ROOT/boot/grub/grub.cfg" | head -n 1)" = "menuentry 'PIS: Slackware generic-smp-5.15.209_smp' --class slackware --class gnu-linux --class os --id 'pis-vmlinuz-generic-smp-5-15-209_smp' {" ] || fail "selected GRUB default kernel was not placed first"
unset PIS_GRUB_DEFAULT_KERNEL
rm -f "$PIS_ROOT/boot/grub/grub.cfg"
rm -f "$PIS_ROOT/boot/efi/EFI/Slackware/elilo.conf"

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

created_file="$PIS_ROOT/etc/pis-created-test"
created_source="$test_root/created-source"
printf 'created by PIS\n' > "$created_source"
pis_replace_file "$created_source" "$created_file" "created-test" || fail "new-file backup marker failed"
[ -f "$created_file" ] || fail "new test file was not created"
missing_backup="$(awk -F '\t' '$2 == "created-test" {print $4; exit}' "$PIS_BACKUP_INDEX")"
missing_state="$(awk -F '\t' '$2 == "created-test" {print $5; exit}' "$PIS_BACKUP_INDEX")"
[ "$missing_state" = absent ] || fail "absence before new-file creation was not recorded"
pis_restore_backup "$missing_backup" "$created_file" "$missing_state" || fail "absent state restoration failed"
[ ! -e "$created_file" ] || fail "restoring an absent state did not remove the created file"

for script in "$project_dir"/pis "$project_dir"/pis_*; do
    bash -n "$script" || fail "syntax error in $(basename "$script")"
done

printf 'All PIS tests passed.\n'
