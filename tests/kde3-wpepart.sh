#!/bin/bash
# Smoke test for the installed kde3-wpepart package; run by "./build.sh
# test" as an unprivileged user in a login shell (so /etc/profile.d is
# sourced).  Checks the ELF files and the service, then shows a local page
# with kwpeview under Xvfb (shared memory path: Xvfb has no DRI3) and
# checks the window title and the colour of the rendered page.
set -euo pipefail

. "$(dirname "$0")/common.sh"

KDEDIR=/opt/kde3
work=$(mktemp -d)
cd "$work"

step "all ELF files resolve, RUNPATH only into /opt/kde3 and /opt/kde3-qt"
check_elf $KDEDIR $KDEDIR/lib /opt/kde3-qt/lib
exports $KDEDIR/lib/kde3/libkwpepart.so init_libkwpepart ||
    fail "libkwpepart.so does not export init_libkwpepart"
# the XML GUI of the part, and of its app mode (KWhatsApp)
for f in kwpepart.rc kwpeapppart.rc; do
    [[ -f $KDEDIR/share/apps/kwpepart/$f ]] || fail "share/apps/kwpepart/$f missing"
done

step "Xvfb"
Xvfb :42 -nolisten tcp -screen 0 1024x768x24 >/dev/null 2>&1 &
xvfb=$!
cleanup() {
    [[ -n ${view:-} ]] && kill $view 2>/dev/null || true
    timeout 30 dcopserver_shutdown --wait >/dev/null 2>&1 || true
    kill $xvfb 2>/dev/null || true
    cd /; rm -rf "$work"
}
trap cleanup EXIT
export DISPLAY=:42
for _ in $(seq 50); do [[ -e /tmp/.X11-unix/X42 ]] && break; sleep 0.1; done

step "dcopserver and kbuildsycoca"
dcopserver --nosid
for _ in $(seq 50); do dcop >/dev/null 2>&1 && break; sleep 0.1; done
dcop >/dev/null || fail "dcop cannot reach dcopserver"
kbuildsycoca --noincremental >sycoca.log 2>&1 || { cat sycoca.log; fail "kbuildsycoca"; }

step "the part is the preferred text/html part"
cat >CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(wpetrader CXX)
find_package(KDE3Libs 3.5 REQUIRED)
kde3_add_executable(wpetrader SOURCES main.cpp LINK KDE3::kio NO_INSTALL)
EOF
cat >main.cpp <<'EOF'
#include <kinstance.h>
#include <ktrader.h>
#include <kservice.h>
#include <stdio.h>

int main()
{
    KInstance instance("wpetrader");
    int errors = 0;
    const char *types[] = { "text/html", "application/xhtml+xml", 0 };
    for (int i = 0; types[i]; i++) {
        KTrader::OfferList offers = KTrader::self()->query(types[i], "KParts/ReadOnlyPart", QString::null, QString::null);
        QString first = offers.isEmpty() ? QString("none") : offers.first()->library();
        printf("%s: %s\n", types[i], first.latin1());
        if (first != "libkwpepart")
            errors++;
    }
    return errors;
}
EOF
cmake -S . -B build -DCMAKE_BUILD_TYPE=None >cmake.log 2>&1 || { cat cmake.log; fail "cmake"; }
cmake --build build >make.log 2>&1 || { cat make.log; fail "build"; }
./build/wpetrader || fail "libkwpepart is not the preferred part"

step "kwpeview shows a local page"
cat >page.html <<'EOF'
<!DOCTYPE html>
<html><head><title>kwpe-smoke-ok</title></head>
<body style="margin:0; background:rgb(0,128,255)">
<p id="t"></p><script>document.getElementById("t").textContent = "script ran";</script>
</body></html>
EOF
# Containers usually do not allow the user namespaces bubblewrap needs.
if ! bwrap --unshare-user --ro-bind / / true 2>/dev/null; then
    echo "no user namespaces here: WebKit's sandbox off for this test"
    export WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1
fi
KWPE_DEBUG=1 kwpeview "file://$work/page.html" >kwpeview.log 2>&1 &
view=$!
title=
for _ in $(seq 300); do
    kill -0 $view 2>/dev/null || { cat kwpeview.log; fail "kwpeview exited"; }
    title=$(xwininfo -root -tree 2>/dev/null | grep -o '"kwpe-smoke-ok[^"]*"' | head -1 || true)
    [[ -n $title ]] && break
    sleep 0.1
done
[[ -n $title ]] || { cat kwpeview.log; fail "the page title never reached the window"; }
echo "window title: $title"
# the page's background in the middle of the window (kwpeview's window is
# at 0,0); give WebKit a moment for the first frame
ok=
for _ in $(seq 50); do
    px=$(xwd -root -silent | xwdtopnm 2>/dev/null | python3 -c '
import re, sys
d = sys.stdin.buffer.read()
m = re.match(rb"P6\s+(\d+)\s+(\d+)\s+\d+\s", d)
w, h = int(m[1]), int(m[2]); data = d[m.end():]
o = ((h // 2) * w + w // 2) * 3
print(*data[o:o + 3])')
    [[ $px == "0 128 255" ]] && { ok=1; break; }
    sleep 0.2
done
echo "pixel in the middle of the screen: $px"
[[ -n $ok ]] || { cat kwpeview.log; fail "the page was not drawn"; }
kill $view; wait $view 2>/dev/null || true
view=
echo "ok"
