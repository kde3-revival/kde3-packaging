#!/bin/bash
# Smoke test for the installed kde3-qt packages; run by "./build.sh test"
# as an unprivileged user in a login shell (so /etc/profile.d is sourced).
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }
step() { echo; echo "=== $*"; }

step "environment"
echo "QTDIR=${QTDIR:-}"
echo "PATH=$PATH"
[[ ${QTDIR:-} == /opt/kde3-qt ]] || fail "QTDIR not set by /etc/profile.d/kde3-qt.sh"
[[ :$PATH: == *:/opt/kde3-qt/bin:* ]] || fail "/opt/kde3-qt/bin not in PATH"

step "ldd of designer"
ldd "$QTDIR/bin/designer"
! ldd "$QTDIR/bin/designer" | grep -q 'not found' || fail "designer has unresolved libraries"

step "all ELF files resolve and have no build-tree RUNPATH"
n=0
while IFS= read -r -d '' f; do
    head -c4 "$f" | grep -q $'\x7fELF' || continue
    n=$((n + 1))
    if ldd "$f" 2>/dev/null | grep -q 'not found'; then
        ldd "$f" | grep 'not found'
        fail "$f has unresolved libraries"
    fi
    rp=$(readelf -d "$f" | sed -n 's/.*(\(RPATH\|RUNPATH\)).*\[\(.*\)\]/\2/p')
    for d in ${rp//:/ }; do
        [[ $d == '$ORIGIN'* ]] || fail "$f has a RUNPATH entry not relative to \$ORIGIN: $d"
        r=$(realpath -m "${d//\$ORIGIN/$(dirname "$f")}")
        [[ $r == /opt/kde3-qt/* ]] || fail "$f has RUNPATH entry $d ($r)"
    done
done < <(find /opt/kde3-qt -type f \( -name '*.so*' -o -perm -u+x \) -print0)
echo "$n ELF files checked"

step "installed files do not refer to the build tree"
[[ $(readlink "$QTDIR/mkspecs/default") == linux-g++ ]] || fail "mkspecs/default -> $(readlink "$QTDIR/mkspecs/default")"
[[ -z $(find "$QTDIR/mkspecs" -mindepth 2 -type l) ]] || fail "stray links in mkspecs: $(find "$QTDIR/mkspecs" -mindepth 2 -type l)"
[[ -z $(find "$QTDIR/lib" -name '*.la') ]] || fail "libtool archives installed"
! grep -rIl -e /builder/ -e /rpmbuild/ "$QTDIR/lib" "$QTDIR/mkspecs" || fail "build directory in the files above"
! grep -rIl X11R6 "$QTDIR/lib" "$QTDIR"/mkspecs/linux-* || fail "/usr/X11R6 in the files above"
echo ok

step "pkg-config"
pkg-config --modversion kde3-qt
pkg-config --cflags --libs kde3-qt
pkg-config --cflags kde3-qt | grep -q -- -DQT_TABLET_SUPPORT || fail "built without tablet (XInput) support"
[[ $(pkg-config --libs kde3-qt) == "-L/opt/kde3-qt/lib -lkde3-qt" ]] || fail "unexpected pkg-config --libs"

step "optional X11 features are linked in"
for lib in libXft libXrender libXrandr libXcursor libXinerama libXi libGL libSM; do
    ldd "$QTDIR/lib/libkde3-qt.so.3" | grep -q "$lib\.so" || fail "libkde3-qt is not linked to $lib"
done
echo ok

work=$(mktemp -d)
cd "$work"

cat >hello.h <<'EOF'
#include <qlabel.h>
class Hello : public QLabel
{
    Q_OBJECT
public:
    Hello(const QString &text) : QLabel(text, 0) {}
public slots:
    void done() { emit finished(); }
signals:
    void finished();
};
EOF

cat >main.cpp <<'EOF'
#include <qapplication.h>
#include <qtimer.h>
#include "hello.h"
#ifdef WITH_UI
#include "form.h"
#endif
int main(int argc, char **argv)
{
    QApplication app(argc, argv);
    Hello label("Hello from kde3-qt " QT_VERSION_STR);
    app.setMainWidget(&label);
    QObject::connect(&label, SIGNAL(finished()), &app, SLOT(quit()));
#ifdef WITH_UI
    Form form;
    form.show();
#endif
    label.show();
    QTimer::singleShot(200, &label, SLOT(done()));
    int rc = app.exec();
    qDebug("ran %s, thread support: %s", qVersion(),
#ifdef QT_THREAD_SUPPORT
           "yes"
#else
           "no"
#endif
          );
    return rc;
}
EOF

cat >form.ui <<'EOF'
<!DOCTYPE UI><UI version="3.3" stdsetdef="1">
<class>Form</class>
<widget class="QWidget">
    <property name="name"><cstring>Form</cstring></property>
    <vbox>
        <widget class="QPushButton">
            <property name="name"><cstring>button</cstring></property>
            <property name="text"><string>Button</string></property>
        </widget>
    </vbox>
</widget>
<layoutdefaults spacing="6" margin="11"/>
</UI>
EOF

cat >hello.pro <<'EOF'
TEMPLATE = app
CONFIG  += qt thread warn_on release
DEFINES += WITH_UI
HEADERS  = hello.h
SOURCES  = main.cpp
FORMS    = form.ui
TARGET   = hello
EOF

step "Xvfb"
Xvfb :42 -nolisten tcp >/dev/null 2>&1 &
xvfb=$!
trap 'kill $xvfb 2>/dev/null || true; rm -rf "$work"' EXIT
export DISPLAY=:42
for _ in $(seq 50); do [[ -e /tmp/.X11-unix/X42 ]] && break; sleep 0.1; done

step "qmake project (moc + uic)"
PATH=$QTDIR/bin:$PATH
qmake -v || true    # qmake 1.07 exits with 1 after -v
qmake hello.pro
make
readelf -d hello | grep -E 'NEEDED|RPATH|RUNPATH'
./hello

step "qmake project without CONFIG += thread (falls back to libkde3-qt)"
mkdir nothread
cp hello.h main.cpp nothread/
cat >nothread/nothread.pro <<'EOF'
TEMPLATE = app
CONFIG  += qt warn_on release
CONFIG  -= thread
HEADERS  = hello.h
SOURCES  = main.cpp
TARGET   = hello
EOF
(cd nothread && qmake nothread.pro && make && ./hello) 2>&1 | tee nothread.log
grep -q 'thread support: yes' nothread.log || fail "the non-thread project did not get QT_THREAD_SUPPORT from libkde3-qt.prl"

step "pkg-config build"
moc hello.h -o moc_hello.cpp
g++ -o hello-pc main.cpp moc_hello.cpp $(pkg-config --cflags --libs kde3-qt) \
    -Wl,-rpath,"$(pkg-config --variable=libdir kde3-qt)"
./hello-pc

step "designer, assistant, linguist and qtconfig start"
for app in designer assistant linguist qtconfig; do
    set +e
    timeout 5 "$QTDIR/bin/$app" >"$app.log" 2>&1
    rc=$?
    set -e
    # 124: still running after 5 s, i.e. it started and did not crash.
    [[ $rc == 124 ]] || { cat "$app.log"; fail "$app exited with $rc"; }
    echo "$app: ok, $(wc -l <"$app.log") lines of output"
    if [[ -s $app.log ]]; then sed 's/^/    /' "$app.log" | head -20; fi
done

step "man pages"
man -w moc 2>/dev/null || echo "(man not installed or moc(1) not found)"

echo
echo "ALL TESTS PASSED"
