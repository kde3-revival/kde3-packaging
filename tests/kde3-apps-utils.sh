#!/bin/bash
# Smoke test for the applications of kde3-apps that were kdeutils
# (kde3-ark, kde3-kcalc, kde3-kcharselect, kde3-kdf, kde3-khexedit,
# kde3-ktimer, kde3-kwalletmanager); run by tests/kde3-apps.sh ("./build.sh
# test") as an unprivileged user in a login shell (so /etc/profile.d is
# sourced).  build.sh installs the optional archivers Ark drives (xz,
# zstd, lz4, zip, unzip, 7zip, unrar where the distribution has them);
# the Ark round trips are run for each format whose tool is there.
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
    files=$(pacman -Qlq kde3-ark kde3-kcalc kde3-kcharselect kde3-kdf kde3-khexedit kde3-ktimer kde3-kwalletmanager)
else
    files=$(rpm -ql kde3-ark kde3-kcalc kde3-kcharselect kde3-kdf kde3-khexedit kde3-ktimer kde3-kwalletmanager)
fi

step "every X-KDE-Library of kdeutils' services is installed and exports its entry point"
# KCModules: kcm_<library>.so with create_<X-KDE-FactoryName, default
# library> or, failing that, a KLibFactory (init_kcm_<library>, which
# KCModuleLoader falls back to); everything else is loaded through
# KLibLoader::factory(): init_<library>.
n=0 errors=0
while read -r desktop; do
    lib=$(sed -n 's/^X-KDE-Library=//p' "$desktop" | head -1)
    [[ -n $lib ]] || continue
    types=$(sed -n 's/^\(X-KDE-\)\{0,1\}ServiceTypes=//p' "$desktop" | head -1)
    # control modules in applications/ (kcmshell <name>) say so with
    # X-KDE-ModuleType=Library instead of ServiceTypes=KCModule
    grep -qx 'X-KDE-ModuleType=Library' "$desktop" && types=$types,KCModule
    n=$((n + 1))
    case ,$types, in
        *,KCModule,*)
            fac=$(sed -n 's/^X-KDE-FactoryName=//p' "$desktop" | head -1)
            cands="kcm_$lib libkcm_$lib" sym="create_${fac:-$lib}|init_kcm_$lib" ;;
        *)
            cands=$lib sym=init_$lib ;;
    esac
    found=
    for c in $cands; do
        for so in $KDEDIR/lib/kde3/$c.so $KDEDIR/lib/$c.so; do
            [[ -f $so ]] && { found=$so; break 2; }
        done
    done
    if [[ -z $found ]]; then
        echo "$desktop: X-KDE-Library=$lib: no ${cands// /.so or }.so"
        errors=$((errors + 1))
    elif ! nm -D --defined-only "$found" | grep -Eq " T ($sym)$"; then
        echo "$desktop: $found does not export $sym"
        errors=$((errors + 1))
    fi
done < <(grep -l '^X-KDE-Library=' $(grep '\.desktop$' <<<"$files"))
echo "$n services checked"
[[ $n -ge 4 ]] || fail "expected at least 4 services (ark part, khexedit2 part, kcm_kdf, kcm_kwallet)"
[[ $errors == 0 ]] || fail "$errors services cannot be loaded"

work=$(mktemp -d)
cd "$work"
export KDEHOME=$work/kdehome
mkdir -p "$KDEHOME/share/config"

step "programs answer --help"
for app in ark kcalc kcharselect kdf kwikdisk khexedit ktimer kwalletmanager; do
    # KCmdLineArgs exits with 254 after --help
    out=$(HOME=$work timeout 20 "$app" --help 2>&1 </dev/null) || true
    grep -qi '^usage:' <<<"$out" || { echo "$out"; fail "$app --help"; }
    echo "$app: ok"
done

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

step "dcopserver and kbuildsycoca"
dcopserver --nosid
for _ in $(seq 50); do dcop >/dev/null 2>&1 && break; sleep 0.1; done
dcop >/dev/null || fail "dcop cannot reach dcopserver"
kbuildsycoca --noincremental >sycoca.log 2>&1 || { cat sycoca.log; fail "kbuildsycoca"; }
grep -i -e error -e warning sycoca.log | head -20 || true

step "the parts, programs and control modules of kdeutils are in ksycoca"
cat >CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(utilstrader CXX)
find_package(KDE3Libs 3.5 REQUIRED)
kde3_add_executable(utilstrader SOURCES main.cpp LINK KDE3::kio NO_INSTALL)
EOF
cat >main.cpp <<'EOF'
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
    KInstance instance("utilstrader");
    expect("KParts/ReadOnlyPart", "'application/x-tgz' in ServiceTypes", "libarkpart");
    expect("KParts/ReadOnlyPart", "'application/x-zip' in ServiceTypes", "libarkpart");
    expect("KParts/ReadOnlyPart", "'application/octet-stream' in ServiceTypes", "libkhexedit2part");
    // the control modules are applications run by kcmshell, which loads
    // their X-KDE-Library
    const char *kcms[][2] = { { "kcmdf", "kdf" }, { "kwalletconfig", "kwallet" }, { 0, 0 } };
    for (int i = 0; kcms[i][0]; i++) {
        KService::Ptr s = KService::serviceByDesktopName(kcms[i][0]);
        printf("control module %s: %s\n", kcms[i][0], s ? s->library().latin1() : "MISSING");
        if (!s || s->library() != kcms[i][1])
            errors++;
    }
    const char *apps[] = { "ark", "kcalc", "KCharSelect", "kdf", "kwikdisk", "khexedit",
                           "ktimer", "kwalletmanager", 0 };
    for (int i = 0; apps[i]; i++) {
        KService::Ptr s = KService::serviceByDesktopName(apps[i]);
        printf("service %s: %s\n", apps[i], s ? s->exec().latin1() : "MISSING");
        if (!s)
            errors++;
    }
    return errors ? 1 : 0;
}
EOF
cmake -S . -B build >cmake.log 2>&1 || { cat cmake.log; fail "cmake"; }
cmake --build build >make.log 2>&1 || { cat make.log; fail "build of the KTrader client"; }
./build/utilstrader 2>utilstrader.err || { cat utilstrader.err; fail "kdeutils services missing in ksycoca"; }
timeout 30 dcopserver_shutdown --wait || fail "dcopserver_shutdown"

step "kdeinit (dcopserver, klauncher, kded)"
kdeinit +kcminit_startup >kdeinit.log 2>&1 || true
for _ in $(seq 100); do dcop 2>/dev/null | grep -q '^kded$' && break; sleep 0.1; done
dcop | grep -q '^klauncher$' || { cat kdeinit.log; fail "klauncher not running"; }

# start <app> [args...]: start a program and wait until it registers with
# DCOP (under its own name), then quit it again
start() {
    local app=$1; shift
    "$app" "$@" >"$app.log" 2>&1 &
    local pid=$!
    for _ in $(seq 300); do
        dcop 2>/dev/null | grep -q "^$app" && break
        kill -0 $pid 2>/dev/null || { cat "$app.log"; fail "$app exited"; }
        sleep 0.1
    done
    dcop 2>/dev/null | grep -q "^$app" || { cat "$app.log"; fail "$app did not register with DCOP"; }
    local reg
    reg=$(dcop | grep "^$app" | head -1)
    echo "$app: running, registered as $reg"
    timeout 10 dcop "$reg" MainApplication-Interface quit >/dev/null 2>&1 || true
    for _ in $(seq 100); do dcop 2>/dev/null | grep -qx "$reg" || break; sleep 0.1; done
    ! dcop 2>/dev/null | grep -qx "$reg" || fail "$app did not quit"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

step "the programs start under Xvfb"
echo hello >sample.bin
start kcalc
start kcharselect
start ktimer
start khexedit sample.bin
start kdf
start kwalletmanager --show
start ark

step "Ark: create, list and extract archives (ark --add-to, ark --extract-to)"
# Ark asks once before creating a single compressed file; answer it here.
printf '[Notification Messages]\nCreatingCompressedArchive=false\n' >"$KDEHOME/share/config/arkrc"
mkdir -p in/"dir ü"
printf 'hello\n' >in/"dir ü"/"fïle 1.txt"
head -c 100000 /dev/urandom >in/rand.bin
arkpids() {   # the running ark processes (no procps in Fedora's base image)
    local p
    for p in /proc/[0-9]*; do
        [[ $(cat "$p/comm" 2>/dev/null) == ark ]] && echo "${p#/proc/}"
    done
    return 0
}
waitark() {   # ark --add-to/--extract-to return at once, the work goes on in the background
    for _ in $(seq 300); do [[ -z $(arkpids) ]] && return 0; sleep 0.1; done
    kill $(arkpids) 2>/dev/null || true
    return 1
}
mime() { [[ -f $KDEDIR/share/mimelnk/application/$1.desktop ]]; }
same() { [[ -f $2 && $(sha256sum <"$1") == "$(sha256sum <"$2")" ]]; }   # no diffutils
sametree() {   # sametree <dir1> <dir2>: same names, same file contents
    local f
    [[ $(cd "$1" && find . | sort) == "$(cd "$2" && find . | sort)" ]] || return 1
    while IFS= read -r -d '' f; do same "$1/$f" "$2/$f" || return 1; done \
        < <(cd "$1" && find . -type f -print0)
}
tested=() skipped=()
roundtrip() {   # roundtrip <extension> <tool> [mime type]
    local ext=$1 tool=$2 mt=${3:-}
    if ! command -v "$tool" >/dev/null; then skipped+=("$ext (no $tool)"); return; fi
    if [[ -n $mt ]] && ! mime "$mt"; then skipped+=("$ext (no $mt in kdelibs)"); return; fi
    local a=$work/test.$ext
    rm -rf "$a" out && mkdir out
    (cd in && timeout 60 ark --add-to "dir ü" rand.bin "$a" >"$work/add-$ext.log" 2>&1) || true
    waitark || { cat "add-$ext.log"; fail "ark --add-to $ext hangs"; }
    timeout 60 ark --extract-to "$work/out" "$a" >"$work/extract-$ext.log" 2>&1 || true
    waitark || { cat "extract-$ext.log"; fail "ark --extract-to $ext hangs"; }
    sametree in out || { tail -n 30 "add-$ext.log" "extract-$ext.log"; fail "$ext: extracted tree differs"; }
    echo "$ext: ok ($(du -b "$a" | cut -f1) bytes)"
    tested+=("$ext")
}
roundtrip tar tar
roundtrip tar.gz gzip
roundtrip tar.bz2 bzip2
roundtrip tar.xz xz application/x-xz-compressed-tar
roundtrip tar.zst zstd application/x-zstd-compressed-tar
roundtrip tar.lz4 lz4 application/x-lz4-compressed-tar
roundtrip zip zip
roundtrip 7z 7z

single() {   # single <extension> <tool> [mime type]: one compressed file
    local ext=$1 tool=$2 mt=${3:-}
    if ! command -v "$tool" >/dev/null; then skipped+=("$ext (no $tool)"); return; fi
    if [[ -n $mt ]] && ! mime "$mt"; then skipped+=("$ext (no $mt in kdelibs)"); return; fi
    local a=$work/rand.bin.$ext
    rm -rf "$a" out && mkdir out
    (cd in && timeout 60 ark --add-to rand.bin "$a" >"$work/add-$ext.log" 2>&1) || true
    waitark || { cat "add-$ext.log"; fail "ark --add-to $ext hangs"; }
    timeout 60 ark --extract-to "$work/out" "$a" >"$work/extract-$ext.log" 2>&1 || true
    waitark || { cat "extract-$ext.log"; fail "ark --extract-to $ext hangs"; }
    same in/rand.bin out/rand.bin || fail "$ext: extracted file differs"
    echo "$ext: ok"
    tested+=("$ext")
}
single gz gzip
single bz2 bzip2
single xz xz application/x-xz
single zst zstd application/zstd
single lz4 lz4 application/x-lz4

# RAR can only be read (unrar): the stored-file RAR 5 sample of libarchive's
# test suite (test_read_format_rar5_stored.rar, BSD-2-Clause).
if command -v unrar >/dev/null; then
    base64 -d >sample.rar <<'EOF'
UmFyIRoHAQAzkrXlCgEFBgAFAQGAgAA4MAZjLAIDC50ABJ0ApIMCtEOglYAAAQ5oZWxsb3dvcmxk
LnR4dAoDE34Oq1tW6Q4aaGVsbG8gbGliYXJjaGl2ZSB0ZXN0IHN1aXRlIQodd1ZRAwUEAA==
EOF
    rm -rf out && mkdir out
    timeout 60 ark --extract-to "$work/out" "$work/sample.rar" >extract-rar.log 2>&1 || true
    waitark || { cat extract-rar.log; fail "ark --extract-to rar hangs"; }
    [[ $(cat out/helloworld.txt 2>/dev/null) == "hello libarchive test suite!" ]] ||
        { cat extract-rar.log; fail "rar: helloworld.txt not extracted"; }
    echo "rar: ok"
    tested+=(rar)
else
    skipped+=("rar (no unrar)")
fi

echo "Ark formats tested: ${tested[*]}"
[[ ${#skipped[@]} == 0 ]] || printf 'skipped: %s\n' "${skipped[@]}"

echo
echo "ALL TESTS PASSED"
