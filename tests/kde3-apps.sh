#!/bin/bash
# Smoke test for the installed kde3-apps packages; run by "./build.sh test"
# as an unprivileged user in a login shell (so /etc/profile.d is sourced).
# Checks the split into one package per application, then runs the tests
# of the former kdeutils and kdegraphics applications
# (kde3-apps-utils.sh, kde3-apps-graphics.sh).
set -euo pipefail

. "$(dirname "$0")/common.sh"

apps="kde3-ark kde3-kcalc kde3-kcharselect kde3-kdf kde3-khexedit kde3-ktimer
      kde3-kwalletmanager kde3-kview kde3-kruler kde3-ksnapshot kde3-kweather
      kde3-kbluetooth"

step "one package per application, kde3-apps replaces kde3-kdeutils and kde3-kdegraphics"
if command -v pacman >/dev/null; then
    for p in kde3-apps $apps; do pacman -Q $p >/dev/null || fail "$p not installed"; done
    deps=$(pacman -Qi kde3-apps | sed -n 's/^Depends On *: //p')
    replaces=$(pacman -Qi kde3-apps | sed -n 's/^Replaces *: //p')
    echo "kde3-apps depends on: $deps"
    echo "kde3-apps replaces: $replaces"
    for p in $apps; do [[ " $deps " == *" $p="* ]] || fail "kde3-apps does not depend on $p"; done
    for p in kde3-kdeutils kde3-kdegraphics; do
        [[ " $replaces " == *" $p<"* ]] || fail "kde3-apps does not replace $p"
    done
    owner() { pacman -Qqo "$1"; }
else
    for p in kde3-apps $apps; do rpm -q $p >/dev/null || fail "$p not installed"; done
    rpm -q --obsoletes kde3-apps
    for p in kde3-kdeutils kde3-kdegraphics; do
        rpm -q --obsoletes kde3-apps | grep -q "^$p < " || fail "kde3-apps does not obsolete $p"
    done
    for p in $apps; do
        rpm -q --requires kde3-apps | grep -q "^$p(x86-64) = " || fail "kde3-apps does not require $p"
    done
    owner() { rpm -qf --qf '%{NAME}\n' "$1"; }
fi
# a few files of each application in its own package
while read -r pkg f; do
    [[ $(owner /opt/kde3/$f) == "$pkg" ]] || fail "/opt/kde3/$f is not in $pkg"
done <<'LIST'
kde3-ark bin/ark
kde3-ark lib/kde3/libarkpart.so
kde3-kcalc bin/kcalc
kde3-kcharselect bin/kcharselect
kde3-kdf bin/kwikdisk
kde3-kdf lib/kde3/kcm_kdf.so
kde3-kdf share/doc/HTML/en/kinfocenter/blockdevices/index.docbook
kde3-khexedit lib/kde3/libkhexedit2part.so
kde3-ktimer bin/ktimer
kde3-kwalletmanager lib/kde3/kcm_kwallet.so
kde3-kview lib/kde3/libkviewviewer.so
kde3-kruler bin/kruler
kde3-ksnapshot bin/ksnapshot
kde3-ksnapshot share/doc/HTML/en/ksnapshot/index.docbook
kde3-kweather bin/kweatherservice
kde3-kweather lib/kde3/weather_panelapplet.so
kde3-kweather share/apps/kicker/applets/kweather.desktop
kde3-kbluetooth bin/kbluetooth
kde3-kbluetooth share/autostart/kbluetooth.desktop
LIST
echo ok

step "kweather and kbluetooth"
# the applet's entry point for kicker, the programs' command lines
nm -D --defined-only /opt/kde3/lib/kde3/weather_panelapplet.so | grep -q ' T init$' ||
    fail "weather_panelapplet does not export init()"
for p in kweatherservice kbluetooth; do
    $p --help >$p-help.log 2>&1 || { cat $p-help.log; fail "$p --help"; }
done
grep -q 'libgio-2\.0\.so' <<<"$(ldd /opt/kde3/bin/kbluetooth)" || fail "kbluetooth not linked to GIO"
echo ok

bash "$(dirname "$0")/kde3-apps-utils.sh"
bash "$(dirname "$0")/kde3-apps-graphics.sh"

echo
echo "ALL TESTS PASSED (kde3-apps)"
