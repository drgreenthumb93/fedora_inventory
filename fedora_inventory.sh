#!/usr/bin/env bash
# =============================================================================
#  fedora-inventory.sh  –  Bestandsaufnahme für Fedora Workstation (GNOME)
#  Liest NUR aus, ändert NICHTS am System.
#  Aufruf:  chmod +x fedora-inventory.sh && ./fedora-inventory.sh
#  Ergebnis: ~/fedora-inventory-<Datum>.txt
# =============================================================================

if [[ $EUID -eq 0 ]]; then
  echo "Bitte als normaler Benutzer starten (sudo wird intern genutzt)." >&2
  exit 1
fi

OUT="${HOME}/fedora-inventory-$(date +%Y%m%d-%H%M).txt"
HN="$(hostname -s 2>/dev/null || hostname)"
DNF="dnf5"; command -v dnf5 >/dev/null 2>&1 || DNF="dnf"

echo "sudo-Passwort wird für einige Abfragen (Ports, Firewall, Logs) benötigt ..." >&2
sudo -v || exit 1
( while true; do sudo -n true; sleep 45; done ) 2>/dev/null &
KEEPALIVE=$!
trap 'kill $KEEPALIVE 2>/dev/null' EXIT

have() { command -v "$1" >/dev/null 2>&1; }
sec()  { printf '\n\n######################## %s ########################\n' "$*"; echo ">> $*" >&2; }
run()  {
  printf '\n$ %s\n' "$*"
  timeout 180 bash -c "$*" 2>&1 | sed "s/${HN}/<HOST>/g"
}

{
echo "Fedora-Bestandsaufnahme  –  $(date -Iseconds)"
echo "Paketmanager: $DNF"

# -----------------------------------------------------------------------------
sec "1. SYSTEM"
run "cat /etc/os-release"
run "uname -a"
run "hostnamectl | grep -vE 'Machine ID|Boot ID|Static hostname|Transient'"
run "uptime"
run "echo Session=\$XDG_SESSION_TYPE Desktop=\$XDG_CURRENT_DESKTOP"
have gnome-shell && run "gnome-shell --version"
run "cat /proc/cmdline"
run "rpm -q kernel-core kernel-modules-extra 2>/dev/null"
have getenforce && run "getenforce; sestatus 2>/dev/null | head -10"
have mokutil && run "mokutil --sb-state"
run "systemctl get-default"

# -----------------------------------------------------------------------------
sec "2. HARDWARE"
run "lscpu | grep -E 'Model name|^CPU\(s\)|Thread|Core|Socket|MHz|Virtualization|Vulnerab' "
run "free -h"
run "lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS,ROTA,TRAN,MODEL"
run "lspci -k | grep -EA3 -i 'vga|3d|display|network|ethernet|audio|nvme|sata'"
have lsusb && run "lsusb"
run "for d in /sys/block/*/queue/scheduler; do echo \"\$d: \$(cat \$d)\"; done"
run "grep -H . /sys/devices/system/cpu/vulnerabilities/* 2>/dev/null"
have nvidia-smi && run "nvidia-smi"
have glxinfo && run "glxinfo -B"
have vainfo && run "vainfo 2>&1 | head -30"
have bluetoothctl && run "bluetoothctl list"
have mmcli && run "mmcli -L"
have lpstat && run "lpstat -p -v 2>&1"

# -----------------------------------------------------------------------------
sec "3. DATEISYSTEME / SPEICHER / SWAP"
run "df -hT -x tmpfs -x devtmpfs -x squashfs -x overlay"
run "findmnt -t btrfs,ext4,xfs,vfat,ntfs3,exfat -o TARGET,SOURCE,FSTYPE,OPTIONS"
run "cat /etc/fstab"
run "zramctl; swapon --show"
run "cat /etc/systemd/zram-generator.conf /usr/lib/systemd/zram-generator.conf 2>/dev/null"
run "sysctl vm.swappiness vm.vfs_cache_pressure vm.dirty_ratio vm.dirty_background_ratio vm.max_map_count kernel.split_lock_mitigate 2>/dev/null"
run "systemctl is-enabled fstrim.timer"
have btrfs && run "sudo btrfs filesystem usage / 2>/dev/null | head -15"
run "journalctl --disk-usage"
run "sudo du -sh /var/cache/libdnf5 /var/cache/dnf /var/log /var/lib/flatpak /var/lib/containers /var/lib/libvirt/images \$HOME/.cache \$HOME/.local/share/flatpak \$HOME/.local/share/containers 2>/dev/null"
run "sudo du -sh /var/lib/systemd/coredump 2>/dev/null"

# -----------------------------------------------------------------------------
sec "4. PERFORMANCE / BOOT"
have powerprofilesctl && run "powerprofilesctl get; powerprofilesctl list"
have tuned-adm && run "tuned-adm active"
run "cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_driver /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null"
run "systemd-analyze"
run "systemd-analyze blame | head -40"
run "systemd-analyze critical-chain"
run "systemd-analyze --user blame | head -25"
run "ps -eo pid,user,%mem,rss,%cpu,comm --sort=-rss | head -30"
run "ps -eo pid,user,%cpu,%mem,comm --sort=-%cpu | head -20"
run "cat /etc/dnf/dnf.conf; ls /etc/dnf/libdnf5.conf.d/ 2>/dev/null && cat /etc/dnf/libdnf5.conf.d/* 2>/dev/null"

# -----------------------------------------------------------------------------
sec "5. DIENSTE"
run "systemctl list-unit-files --type=service --state=enabled --no-pager"
run "systemctl list-unit-files --type=socket --state=enabled --no-pager"
run "systemctl list-units --type=service --state=running --no-pager"
run "systemctl list-timers --all --no-pager"
run "systemctl --failed --no-pager"
run "systemctl --user list-unit-files --state=enabled --no-pager"
run "systemctl --user list-units --type=service --state=running --no-pager"
run "systemctl --user --failed --no-pager"
run "ls -1 /etc/xdg/autostart/ \$HOME/.config/autostart/ 2>/dev/null"

# -----------------------------------------------------------------------------
sec "6. NETZWERK / SICHERHEIT"
run "sudo ss -tulpn"
have firewall-cmd && run "sudo firewall-cmd --state; sudo firewall-cmd --get-default-zone; sudo firewall-cmd --get-active-zones"
have firewall-cmd && run "sudo firewall-cmd --list-all"
run "systemctl is-enabled sshd 2>/dev/null; systemctl is-active sshd 2>/dev/null"
run "sudo grep -hE '^\s*(PermitRootLogin|PasswordAuthentication|Port)' /etc/ssh/sshd_config /etc/ssh/sshd_config.d/* 2>/dev/null"
run "nmcli -t -f NAME,TYPE,DEVICE connection show --active"
run "resolvectl status 2>/dev/null | grep -E 'DNS Servers|DNSSEC|DNSOverTLS|Protocols' | sort -u"
run "sudo ls -la /etc/sudoers.d/"
run "getent group wheel"
run "sudo ausearch -m AVC -ts this-week 2>/dev/null | grep -c 'type=AVC' || echo 0"

# -----------------------------------------------------------------------------
sec "7. UPDATES / SICHERHEITSLÜCKEN"
run "$DNF check-upgrade --refresh"
if [[ $DNF == dnf5 ]]; then
  run "$DNF advisory summary"
  run "$DNF advisory list --security"
else
  run "$DNF updateinfo summary"
  run "$DNF updateinfo list --security"
fi
run "$DNF needs-restarting -r 2>/dev/null"
have fwupdmgr && run "fwupdmgr get-devices --no-unreported-check 2>/dev/null | grep -E '^[├└─ ]*[A-Za-z]|Current version' | head -60"
have fwupdmgr && run "fwupdmgr get-updates --no-unreported-check 2>&1 | head -40"
have flatpak && run "flatpak remote-ls --updates 2>/dev/null"
run "rpm -q --last kernel-core | head -5"

# -----------------------------------------------------------------------------
sec "8. REPOSITORIES"
run "$DNF repo list --enabled"
run "$DNF repo list --disabled"
run "ls -1 /etc/yum.repos.d/"
run "rpm -q gpg-pubkey --qf '%{VERSION}-%{RELEASE}  %{SUMMARY}\n'"

# -----------------------------------------------------------------------------
sec "9. PAKETE"
run "echo RPM-Pakete gesamt: \$(rpm -qa | wc -l)"
run "$DNF environment list --installed 2>/dev/null"
run "$DNF group list --installed 2>/dev/null"
run "$DNF group info gnome-desktop 2>/dev/null"
run "$DNF group info workstation-product 2>/dev/null"
echo; echo "---- Vom Benutzer explizit installiert (userinstalled) ----"
run "$DNF repoquery --userinstalled --qf '%{name}\n' 2>/dev/null | sort -u"
echo; echo "---- Leaves (von nichts abhängig) ----"
run "$DNF leaves 2>/dev/null"
echo; echo "---- autoremove (Trockenlauf, löscht nichts) ----"
run "sudo $DNF autoremove --assumeno 2>&1 | tail -60"
echo; echo "---- Pakete ohne Repo (verwaist / manuell) ----"
run "$DNF list --extras 2>/dev/null"
echo; echo "---- Duplikate ----"
run "$DNF repoquery --duplicates 2>/dev/null"
echo; echo "---- Pakete aus Drittquellen (nicht fedora/updates) ----"
run "$DNF repoquery --installed --qf '%{from_repo}\t%{name}\n' 2>/dev/null | grep -vE '^(fedora|updates|updates-testing|anaconda|<unknown>)\s' | sort"
echo; echo "---- 60 größte Pakete ----"
run "rpm -qa --qf '%{SIZE}\t%{NAME}\n' | sort -rn | head -60 | numfmt --field=1 --to=iec"
echo; echo "---- Kernel-Module / akmods / dkms ----"
run "rpm -qa | grep -Ei 'akmod|kmod-|dkms|nvidia|broadcom|virtualbox|vmware' | sort"
echo; echo "---- Sprachpakete / Fonts / Input ----"
run "rpm -qa | grep -Ei '^(langpacks|glibc-langpack|hunspell-|google-noto|ibus-)' | sort | tr '\n' ' '; echo"
echo; echo "---- Vollständige Paketliste (Name|Repo) ----"
run "$DNF repoquery --installed --qf '%{name}|%{from_repo}\n' 2>/dev/null | sort -u"

# -----------------------------------------------------------------------------
sec "10. FLATPAK / SNAP / CONTAINER / VM"
if have flatpak; then
  run "flatpak remotes --columns=name,url,options"
  run "flatpak list --app --columns=application,origin,installation,size"
  run "flatpak list --runtime --columns=application,branch,installation,size"
fi
have snap    && run "snap list"
have podman  && run "podman ps -a --format '{{.Names}} {{.Image}} {{.Status}}'; podman images"
have toolbox && run "toolbox list"
have distrobox && run "distrobox list"
have virsh   && run "sudo virsh list --all"
have docker  && run "sudo docker ps -a"

# -----------------------------------------------------------------------------
sec "11. GNOME"
have gnome-extensions && run "gnome-extensions list --enabled; echo '-- deaktiviert:'; gnome-extensions list --disabled"
run "gsettings get org.gnome.desktop.interface enable-animations"
run "gsettings get org.gnome.desktop.search-providers disabled"
run "gsettings get org.gnome.desktop.search-providers disable-external"
run "gsettings get org.gnome.software download-updates 2>/dev/null; gsettings get org.gnome.software allow-updates 2>/dev/null"
run "gsettings get org.gnome.desktop.privacy remember-recent-files; gsettings get org.gnome.desktop.privacy report-technical-problems"
run "gsettings get org.gnome.mutter experimental-features"
run "gsettings get org.freedesktop.Tracker3.Miner.Files index-recursive-directories 2>/dev/null"
run "gsettings get org.freedesktop.Tracker3.Miner.Files index-single-directories 2>/dev/null"
have localsearch && run "localsearch status 2>&1 | head -20"
have tracker3    && run "tracker3 status 2>&1 | head -20"
run "du -sh \$HOME/.cache/tracker3 \$HOME/.cache/localsearch 2>/dev/null"

# -----------------------------------------------------------------------------
sec "12. FEHLER / LOGS (aktueller Boot)"
run "journalctl -b -p 3 --no-pager | tail -80"
run "sudo dmesg --level=err,warn | tail -60"
have coredumpctl && run "coredumpctl list --no-pager 2>/dev/null | tail -20"

echo; echo "=== ENDE ==="
} > "$OUT"

echo >&2
echo "Fertig: $OUT  ($(wc -l < "$OUT") Zeilen)" >&2
echo "Datei hier hochladen oder Inhalt einfügen." >&2
