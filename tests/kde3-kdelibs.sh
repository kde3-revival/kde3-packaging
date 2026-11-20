#!/bin/bash
# Smoke test for the installed kde3-kdelibs packages; run by "./build.sh
# test" as an unprivileged user in a login shell (so /etc/profile.d is
# sourced).
set -euo pipefail

. "$(dirname "$0")/common.sh"

KDEDIR=/opt/kde3

step "environment"
echo "PATH=$PATH"
[[ :$PATH: == *:$KDEDIR/bin:* ]] || fail "$KDEDIR/bin not in PATH"

step "kde-config"
kde-config --version
[[ $(kde-config --prefix) == "$KDEDIR" ]] || fail "kde-config --prefix: $(kde-config --prefix)"
[[ $(kde-config --expandvars --exec-prefix) == "$KDEDIR" ]] || fail "kde-config --exec-prefix: $(kde-config --expandvars --exec-prefix)"
services=$(kde-config --path services)
echo "services: $services"
[[ :$services: == *:$KDEDIR/share/services/:* ]] || fail "$KDEDIR/share/services/ not in the services path"
for res in lib module exe config data mime xdgconf-menu; do
    echo "$res: $(kde-config --path $res)"
done
[[ :$(kde-config --path module): == *:$KDEDIR/lib/kde3/:* ]] || fail "modules are not looked for in $KDEDIR/lib/kde3/"

step "all ELF files resolve, RUNPATH only into /opt/kde3 and /opt/kde3-qt"
check_elf $KDEDIR $KDEDIR/lib /opt/kde3-qt/lib
readelf -d $KDEDIR/bin/kded | grep -E 'NEEDED|RUNPATH'

step "setuid helpers"
for f in kgrantpty start_kdeinit kpac_dhcp_helper; do
    ls -l $KDEDIR/bin/$f
    [[ -u $KDEDIR/bin/$f && $(stat -c %U $KDEDIR/bin/$f) == root ]] || fail "$f is not setuid root"
done

[[ ! -u $KDEDIR/bin/fileshareset ]] || fail "fileshareset (a script) is setuid"

step "files outside /opt/kde3"
for f in /etc/profile.d/kde3.sh /etc/profile.d/kde3.csh /usr/share/cups/model/postscript.ppd.gz; do
    [[ -f $f ]] || fail "$f missing"
done
ls -d /usr/lib*/cmake/KDE3Libs
[[ -z $(find $KDEDIR -name '*.la') ]] || fail "libtool archives installed"
! grep -rIl -e /builder/ -e /rpmbuild/ -e /redhat-linux-build/ $KDEDIR/lib/cmake $KDEDIR/include | head ||
    fail "build directory in the files above"
echo ok

work=$(mktemp -d)
cd "$work"
export KDEHOME=$work/kdehome
mkdir -p "$KDEHOME"

step "Xvfb"
Xvfb :42 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
cleanup() {
    dcopserver_shutdown --wait >/dev/null 2>&1 || true
    kill $xvfb 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT
export DISPLAY=:42
for _ in $(seq 50); do [[ -e /tmp/.X11-unix/X42 ]] && break; sleep 0.1; done

step "dcopserver start and stop"
dcopserver --nosid
for _ in $(seq 50); do dcop >/dev/null 2>&1 && break; sleep 0.1; done
dcop || fail "dcop cannot reach dcopserver"
ls "$HOME"/.DCOPserver_* "$HOME/.ICEauthority"
timeout 30 dcopserver_shutdown --wait || fail "dcopserver_shutdown"
! timeout 10 dcop >/dev/null 2>&1 || fail "dcopserver still running"
echo ok

step "kbuildsycoca"
kbuildsycoca --noincremental 2>&1 | tail -5
ls -l "$KDEHOME"/cache-*/ksycoca || ls -l /var/tmp/kdecache-"$USER"/ksycoca
ktradertest 'KParts/ReadOnlyPart' 2>/dev/null | head -3 || true

step "kdeinit (dcopserver, klauncher, kded)"
kdeinit +kcminit_startup >kdeinit.log 2>&1 || true
for _ in $(seq 100); do dcop 2>/dev/null | grep -q '^kded$' && break; sleep 0.1; done
dcop | tee dcop.log
grep -q '^klauncher$' dcop.log || { cat kdeinit.log; fail "klauncher not running"; }
grep -q '^kded$' dcop.log || { cat kdeinit.log; fail "kded not running"; }
dcop kded kded loadedModules
timeout 30 kdeinit_shutdown || true
timeout 30 dcopserver_shutdown --wait || fail "dcopserver_shutdown"

step "CMake consumer (find_package(KDE3Libs), .ui, .skel, moc)"
cat >CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(kde3test CXX)
find_package(KDE3Libs 3.5 REQUIRED)
message(STATUS "KDE3Libs ${KDE3_VERSION} in ${KDE3_PREFIX}, RUNPATH ${CMAKE_INSTALL_RPATH}")
kde3_add_executable(kde3test
  SOURCES
    main.cpp
    form.ui
    greeter.skel
  MOC
    window.h
  LINK
    KDE3::kdeui
  NO_INSTALL
)
EOF
cat >greeter.h <<'EOF'
#ifndef GREETER_H
#define GREETER_H
#include <dcopobject.h>
#include <qstring.h>
class Greeter : virtual public DCOPObject
{
    K_DCOP
k_dcop:
    virtual QString greet(const QString &name) = 0;
    virtual void quit() = 0;
};
#endif
EOF
cat >window.h <<'EOF'
#ifndef WINDOW_H
#define WINDOW_H
#include <kmainwindow.h>
#include "greeter.h"
class Window : public KMainWindow, public Greeter
{
    Q_OBJECT
public:
    Window();
    QString greet(const QString &name);
    void quit();
public slots:
    void timeout();
};
#endif
EOF
cat >main.cpp <<'EOF'
#include <kapplication.h>
#include <kaboutdata.h>
#include <kcmdlineargs.h>
#include <klocale.h>
#include <dcopclient.h>
#include <qtimer.h>
#include "window.h"
#include "form.h"

Window::Window() : DCOPObject("greeter")
{
    setCentralWidget(new Form(this));
    QTimer::singleShot(30000, this, SLOT(timeout()));
}
QString Window::greet(const QString &name) { return "hello " + name; }
void Window::quit() { kapp->quit(); }
void Window::timeout() { qWarning("timeout"); kapp->exit(1); }

int main(int argc, char **argv)
{
    KAboutData about("kde3test", I18N_NOOP("kde3test"), "1.0");
    KCmdLineArgs::init(argc, argv, &about);
    KApplication app;
    app.dcopClient()->registerAs("kde3test", false);
    Window *w = new Window;
    app.setMainWidget(w);
    w->show();
    return app.exec();
}
#include "window.moc"
EOF
cat >form.ui <<'EOF'
<!DOCTYPE UI><UI version="3.3" stdsetdef="1">
<class>Form</class>
<widget class="QWidget">
    <property name="name"><cstring>Form</cstring></property>
    <vbox>
        <widget class="KPushButton">
            <property name="name"><cstring>button</cstring></property>
            <property name="text"><string>Button</string></property>
        </widget>
        <widget class="KLineEdit">
            <property name="name"><cstring>edit</cstring></property>
        </widget>
    </vbox>
</widget>
<includes>
    <include location="global" impldecl="in implementation">kpushbutton.h</include>
    <include location="global" impldecl="in implementation">klineedit.h</include>
</includes>
<layoutdefaults spacing="6" margin="11"/>
</UI>
EOF
# Without /etc/profile.d (PATH without /opt/kde3/bin, no QTDIR): found
# through /usr/lib*/cmake/KDE3Libs and kde3-qt.pc.
env -i HOME="$HOME" PATH=/usr/bin:/bin cmake -S . -B build
env -i HOME="$HOME" PATH=/usr/bin:/bin cmake --build build
readelf -d build/kde3test | grep -E 'NEEDED|RUNPATH'

dcopserver --nosid
./build/kde3test >kde3test.log 2>&1 &
app=$!
for _ in $(seq 100); do dcop kde3test >/dev/null 2>&1 && break; sleep 0.1; done
answer=$(dcop kde3test greeter greet world) || { cat kde3test.log; fail "DCOP call failed"; }
echo "dcop kde3test greeter greet world: $answer"
[[ $answer == "hello world" ]] || fail "unexpected DCOP answer"
dcop kde3test greeter quit
wait $app || { cat kde3test.log; fail "kde3test exited with $?"; }
timeout 30 dcopserver_shutdown --wait || fail "dcopserver_shutdown"

step "programs start"
for app in kde-config meinproc kcmshell kconfig_compiler; do
    # KCmdLineArgs exits with 254 after --help
    out=$(timeout 20 "$app" --help 2>&1) || true
    grep -qi '^usage:' <<<"$out" || { echo "$out"; fail "$app --help"; }
    echo "$app: ok"
done

echo
echo "ALL TESTS PASSED"
