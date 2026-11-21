#!/bin/bash
# Smoke test for the installed kde3-kdegraphics package; run by "./build.sh
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

if command -v pacman >/dev/null; then
    files=$(pacman -Qlq kde3-kdegraphics)
else
    files=$(rpm -ql kde3-kdegraphics)
fi

step "every X-KDE-Library of kdegraphics' services is installed and exports its entry point"
# KCModules (KView's configuration pages): kcm_<library>.so; KView's
# have an X-KDE-FactoryName and are loaded through KLibLoader::factory()
# (init_kcm_<library>), others with create_<library>.  The parts are
# loaded through KLibLoader::factory() as well: init_<library>.
n=0 errors=0
while read -r desktop; do
    lib=$(sed -n 's/^X-KDE-Library=//p' "$desktop" | head -1)
    [[ -n $lib ]] || continue
    types=$(sed -n 's/^\(X-KDE-\)\{0,1\}ServiceTypes=//p' "$desktop" | head -1)
    n=$((n + 1))
    case ,$types, in
        *,KCModule,*)
            cands=kcm_$lib sym="init_kcm_$lib|create_$lib" ;;
        *)
            cands=$lib sym=init_$lib ;;
    esac
    found=
    so=$KDEDIR/lib/kde3/$cands.so
    [[ -f $so ]] && found=$so
    if [[ -z $found ]]; then
        echo "$desktop: X-KDE-Library=$lib: no $cands.so"
        errors=$((errors + 1))
    elif ! nm -D --defined-only "$found" | grep -Eq " T ($sym)$"; then
        echo "$desktop: $found does not export $sym"
        errors=$((errors + 1))
    fi
done < <(grep -l '^X-KDE-Library=' $(grep '\.desktop$' <<<"$files"))
echo "$n services checked"
[[ $n -ge 6 ]] || fail "only $n services with a library"
[[ $errors == 0 ]] || fail "$errors services cannot be loaded"

work=$(mktemp -d)
cd "$work"
export KDEHOME=$work/kdehome HOME=$work
mkdir -p "$KDEHOME" "$HOME/Pictures"

step "programs answer --help"
for app in kview ksnapshot kruler; do
    # KCmdLineArgs exits with 254 after --help
    out=$(timeout 20 "$app" --help 2>&1 </dev/null) || true
    grep -qi '^usage:' <<<"$out" || { echo "$out"; fail "$app --help"; }
    echo "$app: ok"
done

step "Xvfb with two screens"
Xvfb :42 -nolisten tcp +xinerama -screen 0 1024x768x24 -screen 1 800x600x24 >/dev/null 2>&1 &
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

step "kdeinit (dcopserver, klauncher, kded) and ksycoca"
kdeinit >kdeinit.log 2>&1 || true
for _ in $(seq 100); do dcop 2>/dev/null | grep -q '^kded$' && break; sleep 0.1; done
dcop | grep -q '^klauncher$' || { cat kdeinit.log; fail "klauncher not running"; }
kbuildsycoca --noincremental >sycoca.log 2>&1 || { cat sycoca.log; fail "kbuildsycoca"; }

step "KView's parts are in ksycoca"
cat >CMakeLists.txt <<'CMAKE'
cmake_minimum_required(VERSION 3.20)
project(kvtrader CXX)
find_package(KDE3Libs 3.5 REQUIRED)
kde3_add_executable(kvtrader SOURCES main.cpp LINK KDE3::kio NO_INSTALL)
kde3_add_executable(desktopsize SOURCES desktopsize.cpp LINK KDE3::kdecore NO_INSTALL)
CMAKE
cat >desktopsize.cpp <<'CPP'
#include <qapplication.h>
#include <qdesktopwidget.h>
#include <stdio.h>

// the size of the whole desktop and the number of screens, as Qt sees them
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    QDesktopWidget *d = QApplication::desktop();
    printf("%dx%d %d\n", d->width(), d->height(), d->numScreens());
    return 0;
}
CPP
cat >main.cpp <<'CPP'
#include <kinstance.h>
#include <ktrader.h>
#include <kservice.h>
#include <qstringlist.h>
#include <stdio.h>

static int errors = 0;

static void expect(const char *type, const char *constraint, const char *lib)
{
    KTrader::OfferList offers = KTrader::self()->query(type, constraint);
    QStringList found;
    for (KTrader::OfferList::ConstIterator it = offers.begin(); it != offers.end(); ++it)
        found << (*it)->library();
    printf("%s %s: %s\n", type, constraint, found.join(" ").latin1());
    if (!found.contains(lib)) {
        printf("  missing: %s\n", lib);
        errors++;
    }
}

int main()
{
    KInstance instance("kvtrader");
    expect("KImageViewer/Viewer", "", "libkviewviewer");
    expect("KImageViewer/Canvas", "", "libkviewcanvas");
    expect("image/png", "'KParts/ReadWritePart' in ServiceTypes", "libkviewviewer");
    expect("KCModule", "[X-KDE-ParentApp] == 'kview'", "kviewgeneralconfig");
    const char *apps[] = { "kview", "ksnapshot", "kruler", 0 };
    for (int i = 0; apps[i]; i++) {
        KService::Ptr s = KService::serviceByDesktopName(apps[i]);
        printf("service %s: %s\n", apps[i], s ? s->exec().latin1() : "MISSING");
        if (!s)
            errors++;
    }
    return errors ? 1 : 0;
}
CPP
cmake -S . -B build >cmake.log 2>&1 || { cat cmake.log; fail "cmake"; }
cmake --build build >make.log 2>&1 || { cat make.log; fail "build of the KTrader client"; }
./build/kvtrader 2>kvtrader.err || { cat kvtrader.err; fail "kdegraphics services missing in ksycoca"; }

# png_size <file>: the width and height in the IHDR chunk of a PNG
png_size() {
    [[ $(head -c8 "$1" | od -An -tx1 | tr -d ' \n') == 89504e470d0a1a0a ]] || return 1
    local w h
    w=$(od -An -j16 -N4 -tu1 "$1" | awk '{ print $1*16777216 + $2*65536 + $3*256 + $4 }')
    h=$(od -An -j20 -N4 -tu1 "$1" | awk '{ print $1*16777216 + $2*65536 + $3*256 + $4 }')
    echo "${w}x$h"
}

# wait_dcop <name> <pid> <log>: wait until a program registers with DCOP;
# prints the registered name
wait_dcop() {
    local name=$1 pid=$2 log=$3
    for _ in $(seq 300); do
        dcop 2>/dev/null | grep -q "^$name" && break
        kill -0 "$pid" 2>/dev/null || { cat "$log" >&2; fail "$name exited"; }
        sleep 0.1
    done
    dcop 2>/dev/null | grep "^$name" | head -1 | grep . || { cat "$log" >&2; fail "$name did not register with DCOP"; }
}

# quit <reg> <pid>
quit() {
    timeout 10 dcop "$1" MainApplication-Interface quit >/dev/null 2>&1 || true
    for _ in $(seq 100); do dcop 2>/dev/null | grep -qx "$1" || break; sleep 0.1; done
    ! dcop 2>/dev/null | grep -qx "$1" || fail "$1 did not quit"
    kill "$2" 2>/dev/null || true
    wait "$2" 2>/dev/null || true
}

step "ksnapshot grabs the whole desktop and saves PNG"
ksnapshot >ksnapshot.log 2>&1 &
pid=$!
reg=$(wait_dcop ksnapshot $pid ksnapshot.log)
echo "ksnapshot: registered as $reg"
[[ $(dcop "$reg" interface save "$work/shot.png") == true ]] || fail "ksnapshot: save failed"
size=$(png_size "$work/shot.png") || fail "ksnapshot: shot.png is not a PNG"
echo "shot.png: $size"
read -r desk screens < <(./build/desktopsize)
echo "desktop: $desk, $screens screens"
[[ $size == "$desk" ]] || fail "ksnapshot: the snapshot is $size, not the whole desktop ($desk)"
# the first quick save goes to ~/Pictures
dcop "$reg" interface slotSave >/dev/null
for _ in $(seq 50); do [[ -e $HOME/Pictures/snapshot1.png ]] && break; sleep 0.1; done
[[ -e $HOME/Pictures/snapshot1.png ]] || fail "ksnapshot: no ~/Pictures/snapshot1.png"
[[ $(dcop "$reg" interface grabMode) == 0 ]] || fail "ksnapshot: grabMode"
dcop "$reg" interface setGrabMode 4 >/dev/null
[[ $(dcop "$reg" interface grabMode) == 4 ]] || fail "ksnapshot: Current Screen mode (4) not accepted"
quit "$reg" $pid

step "kview opens the snapshot"
kview "$work/shot.png" >kview.log 2>&1 &
pid=$!
reg=$(wait_dcop kview $pid kview.log)
echo "kview: registered as $reg"
grep -q "Unknown image format" kview.log && { cat kview.log; fail "kview: cannot read PNG"; }
sleep 1
quit "$reg" $pid

step "kruler starts"
kruler >kruler.log 2>&1 &
pid=$!
reg=$(wait_dcop kruler $pid kruler.log)
echo "kruler: registered as $reg"
quit "$reg" $pid

echo
echo "ALL TESTS PASSED"
