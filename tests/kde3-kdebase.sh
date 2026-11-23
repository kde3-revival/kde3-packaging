#!/bin/bash
# Smoke test for the installed kde3-kdebase packages; run by "./build.sh
# test" as an unprivileged user in a login shell (so /etc/profile.d is
# sourced).
set -euo pipefail

. "$(dirname "$0")/common.sh"

KDEDIR=/opt/kde3

step "environment"
echo "PATH=$PATH"
[[ :$PATH: == *:$KDEDIR/bin:* ]] || fail "$KDEDIR/bin not in PATH"
[[ $(kde-config --prefix) == "$KDEDIR" ]] || fail "kde-config --prefix: $(kde-config --prefix)"

step "all ELF files resolve, RUNPATH only into /opt/kde3 and /opt/kde3-qt"
check_elf $KDEDIR $KDEDIR/lib /opt/kde3-qt/lib

step "setuid/setgid programs"
ls -l $KDEDIR/bin/kcheckpass $KDEDIR/bin/kdesud
[[ -u $KDEDIR/bin/kcheckpass && $(stat -c %U $KDEDIR/bin/kcheckpass) == root ]] ||
    fail "kcheckpass is not setuid root"
[[ -g $KDEDIR/bin/kdesud && $(stat -c %G $KDEDIR/bin/kdesud) == nobody ]] ||
    fail "kdesud is not setgid nobody"
# kcheckpass works in secure mode (ld.so ignores $ORIGIN there): its
# libraries must be found through the absolute RUNPATH entries.
ldd $KDEDIR/bin/kcheckpass | grep -E 'kde3|not found' || true

step "X tools run by startkde, kcontrol, kdm and dcopserver"
for t in iceauth setxkbmap xauth xmessage xrdb; do
    command -v $t >/dev/null || fail "$t not installed"
done
echo ok

step "PAM, session, kdm"
for f in /etc/pam.d/kde3 /etc/pam.d/kde3-np /usr/share/xsessions/kde3.desktop \
         /usr/lib/systemd/system/kde3-kdm.service; do
    [[ -f $f ]] || fail "$f missing"
done
grep -a -q 'kde3' $KDEDIR/bin/kcheckpass || fail "kcheckpass does not use the PAM service kde3"
exec_=$(sed -n 's/^Exec=//p' /usr/share/xsessions/kde3.desktop)
[[ -x $exec_ ]] || fail "session Exec $exec_ is not executable"
sh -n $KDEDIR/bin/startkde || fail "startkde has syntax errors"
# XDG_CURRENT_DESKTOP=KDE3:GNOME, from the session file's DesktopNames, and
# the portal backends for it (gtk, the GNOME keyring for secrets) instead
# of the gnome-portals.conf of the fallback desktop.
grep -qx 'DesktopNames=KDE3;GNOME;' /usr/share/xsessions/kde3.desktop ||
    fail "kde3.desktop does not name the desktop KDE3;GNOME;"
portalconf=/usr/share/xdg-desktop-portal/kde3-portals.conf
[[ -f $portalconf ]] || fail "$portalconf missing"
grep -qx 'default=gtk;' $portalconf || fail "kde3-portals.conf does not default to gtk"
grep -qx 'org.freedesktop.impl.portal.Secret=gnome-keyring;' $portalconf ||
    fail "kde3-portals.conf does not use gnome-keyring for secrets"
grep -qx 'org.freedesktop.impl.portal.Screenshot=none;' $portalconf ||
    fail "kde3-portals.conf does not switch off the GNOME Shell portals"
# KDE 3's own Settings backend first, xdg-desktop-portal-kde3, started by
# the session bus from the service file in /usr/share.
grep -qx 'org.freedesktop.impl.portal.Settings=kde3;gtk;' $portalconf ||
    fail "kde3-portals.conf does not take the settings from kde3 first"
grep -q '^DBusName=org.freedesktop.impl.portal.desktop.kde3$' \
    /usr/share/xdg-desktop-portal/portals/kde3.portal || fail "kde3.portal missing or wrong"
portalexec=$(sed -n 's/^Exec=//p' /usr/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kde3.service)
[[ $portalexec == $KDEDIR/bin/xdg-desktop-portal-kde3 && -x $portalexec ]] ||
    fail "D-Bus service of xdg-desktop-portal-kde3: Exec=$portalexec"
# startkde sets up the root window and shows its errors with kstartupx
# instead of xsetroot, xprop and xmessage.
[[ -x $KDEDIR/bin/kstartupx ]] || fail "kstartupx missing"
kdmconf=$KDEDIR/share/config/kdm
ls $kdmconf
grep -E '^(SessionsDirs|ServerCmd|PidFile|Theme|UseTheme)=' $kdmconf/kdmrc || true
! grep -rIl -e /builder/ -e /rpmbuild/ -e /pkg/ $kdmconf || fail "build directory in the kdm configuration"
echo ok

step "KWin compositor"
# kompmgr is gone: KWin composites itself, with the GLES 3 backend (EGL on
# GBM, DRI3) or XRender.
[[ ! -e $KDEDIR/bin/kompmgr ]] || fail "kompmgr is still installed"
kwinlib=$KDEDIR/lib/libkdeinit_kwin.so
[[ -f $kwinlib ]] || kwinlib=$KDEDIR/lib/kde3/kwin.so
for l in libEGL libGLESv2 libgbm libdrm libxcb-dri3 libxshmfence libXpresent libXi libXrender; do
    ldd $kwinlib | grep -q "$l\.so" || fail "kwin not linked to $l"
done
echo ok

step "volume applet"
for f in $KDEDIR/lib/kde3/volume_panelapplet.so $KDEDIR/share/apps/kicker/applets/volumeapplet.desktop; do
    [[ -f $f ]] || fail "$f missing"
done
ldd $KDEDIR/lib/kde3/volume_panelapplet.so | grep -q 'libpulse\.so' || fail "volume applet not linked to libpulse"
nm -D --defined-only $KDEDIR/lib/kde3/volume_panelapplet.so | grep -q ' T init$' ||
    fail "volume applet does not export init()"
echo ok

step "network applet"
for f in $KDEDIR/lib/kde3/network_panelapplet.so $KDEDIR/share/apps/kicker/applets/networkapplet.desktop; do
    [[ -f $f ]] || fail "$f missing"
done
ldd $KDEDIR/lib/kde3/network_panelapplet.so | grep -q 'libnm\.so' || fail "network applet not linked to libnm"
nm -D --defined-only $KDEDIR/lib/kde3/network_panelapplet.so | grep -q ' T init$' ||
    fail "network applet does not export init()"
echo ok

link=/etc/fonts/conf.d/60-kde3-konsole-fonts.conf
[[ -L $link ]] || fail "$link is not a symbolic link"
[[ $(realpath "$link") == $KDEDIR/share/fontconfig/conf.avail/60-kde3-konsole-fonts.conf ]] ||
    fail "$link points to $(readlink "$link")"
fc=$(fc-list : family foundry file | grep "^$KDEDIR/share/apps/konsole/fonts/" || true)
echo "$fc"
grep -q 'console8x16.*:.*Console' <<<"$fc" || fail "fc-list does not find the console font console8x16"
# "Misc Console" where FreeType makes long PCF family names (foundry +
# family, Arch), "Console" with foundry Misc where it does not (Fedora).
fc-list :foundry=Misc family | grep -qxE '(Misc )?Console' ||
    fail "fc-list does not find the family \"Misc Console\" (or \"Console\", foundry Misc)"
echo ok

work=$(mktemp -d)
cd "$work"
export KDEHOME=$work/kdehome
mkdir -p "$KDEHOME"

step "Xvfb"
Xvfb :42 -nolisten tcp -screen 0 1024x768x24 >/dev/null 2>&1 &
xvfb=$!
cleanup() {
    timeout 30 kdeinit_shutdown >/dev/null 2>&1 || true
    timeout 30 dcopserver_shutdown --wait >/dev/null 2>&1 || true
    kill $xvfb 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
export DISPLAY=:42
for _ in $(seq 50); do [[ -e /tmp/.X11-unix/X42 ]] && break; sleep 0.1; done

step "kbuildsycoca and kcmshell --list"
kbuildsycoca --noincremental >sycoca.log 2>&1 || { cat sycoca.log; fail "kbuildsycoca"; }
kcmshell --list >kcm.log 2>&1
grep -c . kcm.log
for m in kwinoptions desktop fonts kdm keyboard_layout crypto; do
    grep -q "^$m " kcm.log || { cat kcm.log; fail "kcmshell --list lacks $m"; }
done

step "kdeinit (dcopserver, klauncher, kded)"
kdeinit +kcminit_startup >kdeinit.log 2>&1 || true
for _ in $(seq 100); do dcop 2>/dev/null | grep -q '^kded$' && break; sleep 0.1; done
dcop | grep -q '^klauncher$' || { cat kdeinit.log; fail "klauncher not running"; }

# start <app> [args]: start a program and wait until it registers with DCOP
# (under its own name), then quit it again
start() {
    local app=$1 name=${2:-$1}; shift 2 || shift
    "$app" "$@" >"$app.log" 2>&1 &
    local pid=$!
    for _ in $(seq 150); do
        dcop 2>/dev/null | grep -q "^$name" && break
        kill -0 $pid 2>/dev/null || { cat "$app.log"; fail "$app exited"; }
        sleep 0.1
    done
    dcop 2>/dev/null | grep -q "^$name" || { cat "$app.log"; fail "$app did not register with DCOP"; }
    local reg
    reg=$(dcop | grep "^$name" | head -1)
    echo "$app: running, registered as $reg"
    # programs started through kdeinit are not $pid: quit through DCOP
    timeout 10 dcop "$reg" MainApplication-Interface quit >/dev/null 2>&1 || true
    for _ in $(seq 100); do dcop 2>/dev/null | grep -qx "$reg" || break; sleep 0.1; done
    ! dcop 2>/dev/null | grep -qx "$reg" || fail "$app did not quit"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

step "kwin, kicker, kdesktop, konsole, konqueror, kcontrol, kwrite start under Xvfb"
start kwin
start kdesktop
start kicker
start konsole konsole
start konqueror konqueror
start kcontrol
start kwrite

step "programs answer --help"
for app in kwin konsole konqueror kcontrol kate kdialog kfind khelpcenter \
           ksmserver kreadconfig kwriteconfig kxkb kdesu \
           ksysguard kmenuedit klipper; do
    out=$(timeout 20 "$app" --help 2>&1 </dev/null) || true
    grep -qi '^usage:' <<<"$out" || { echo "$out"; fail "$app --help"; }
    echo "$app: ok"
done
kdialog --title test --msgbox hello >/dev/null 2>&1 &
sleep 1
kill $! 2>/dev/null || fail "kdialog did not stay up"

step "kreadconfig"
kreadconfig --file kdeglobals --group General --key nonexisting --default fine | grep -qx fine ||
    fail "kreadconfig"

echo
echo "ALL TESTS PASSED"
