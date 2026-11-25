#!/bin/bash
# Smoke test for the installed kde3-kdepim packages; run by "./build.sh
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

# The files of the kde3-kdepim package (main package on Fedora).
if command -v pacman >/dev/null; then
    files=$(pacman -Qlq kde3-kdepim)
else
    files=$(rpm -ql kde3-kdepim)
fi

step "every X-KDE-Library of kdepim's services is installed and exports its entry point"
# KCModules: kcm_<library>.so (or libkcm_<library>.so) with
# create_<X-KDE-FactoryName, default library>; thumbnail creators:
# new_creator; KMail's body part formatters:
# <library>_create_bodypart_formatter_plugin; everything else is loaded
# through KLibLoader::factory(): init_<library>.
n=0 errors=0
while read -r desktop; do
    lib=$(sed -n 's/^X-KDE-Library=//p' "$desktop" | head -1)
    [[ -n $lib ]] || continue
    types=$(sed -n 's/^\(X-KDE-\)\{0,1\}ServiceTypes=//p' "$desktop" | head -1)
    n=$((n + 1))
    case ,$types, in
        *,KCModule,*)
            fac=$(sed -n 's/^X-KDE-FactoryName=//p' "$desktop" | head -1)
            cands="kcm_$lib libkcm_$lib" sym=create_${fac:-$lib} ;;
        *,ThumbCreator,*)
            cands=$lib sym=new_creator ;;
        *)
            if [[ $lib == libkmail_bodypartformatter_* ]]; then
                cands=$lib sym=${lib}_create_bodypart_formatter_plugin
            else
                cands=$lib sym=init_$lib
            fi ;;
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
    elif ! exports "$found" "$sym"; then
        echo "$desktop: $found does not export $sym"
        errors=$((errors + 1))
    fi
done < <(grep -l '^X-KDE-Library=' $(grep '\.desktop$' <<<"$files"))
echo "$n services checked"
[[ $errors == 0 ]] || fail "$errors services cannot be loaded"

work=$(mktemp -d)
cd "$work"
export KDEHOME=$work/kdehome
mkdir -p "$KDEHOME"

step "programs answer --help"
for app in kmail korganizer kaddressbook kontact kleopatra kwatchgnupg kmailcvt \
           korgac; do
    HOME=$work answers_help "$app"
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

step "the services, service types and protocols of kdepim are in ksycoca"
# A KTrader client: the services KMail, KOrganizer, KAddressBook and
# Kontact look up at run time, and the ioslaves KMail uses (pop3, smtp
# and ldap come from kde3-kdebase).
cat >CMakeLists.txt <<'EOF'
cmake_minimum_required(VERSION 3.20)
project(pimtrader CXX)
find_package(KDE3Libs 3.5 REQUIRED)
kde3_add_executable(pimtrader SOURCES main.cpp LINK KDE3::kio NO_INSTALL)
EOF
cat >main.cpp <<'EOF'
#include <kinstance.h>
#include <ktrader.h>
#include <kservice.h>
#include <kservicetype.h>
#include <kprotocolinfo.h>
#include <qstringlist.h>
#include <stdio.h>

static int errors = 0;

static void expect(const char *type, const char *constraint, const QStringList &libs)
{
    KTrader::OfferList offers = KTrader::self()->query(type, constraint);
    QStringList found;
    for (KTrader::OfferList::ConstIterator it = offers.begin(); it != offers.end(); ++it)
        found << (*it)->library();
    printf("%s %s: %s\n", type, constraint, found.join(" ").latin1());
    for (QStringList::ConstIterator it = libs.begin(); it != libs.end(); ++it)
        if (!found.contains(*it)) {
            printf("  missing: %s\n", (*it).latin1());
            errors++;
        }
}

int main()
{
    KInstance instance("pimtrader");
    const char *types[] = { "Kontact/Plugin", "KAddressBook/View", "KAddressBook/XXPort",
                            "KAddressBook/Extension", "KAddressBook/ContactEditorWidget",
                            "Calendar/Plugin", "KOrganizer/Part", "KResources/Plugin", 0 };
    for (int i = 0; types[i]; i++)
        if (!KServiceType::serviceType(types[i])) {
            printf("service type %s unknown\n", types[i]);
            errors++;
        }
    expect("Kontact/Plugin", "", QStringList()
           << "libkontact_kmailplugin" << "libkontact_korganizerplugin"
           << "libkontact_kaddressbookplugin" << "libkontact_summaryplugin"
           << "libkontact_todoplugin" << "libkontact_journalplugin"
           << "libkontact_specialdatesplugin");
    expect("KResources/Plugin", "[X-KDE-ResourceFamily] == 'calendar'", QStringList()
           << "kcal_local" << "kcal_localdir" << "kcal_remote" << "kcal_kabc");
    expect("KAddressBook/View", "", QStringList()
           << "libkaddrbk_cardview" << "libkaddrbk_iconview" << "libkaddrbk_tableview");
    expect("KAddressBook/XXPort", "", QStringList()
           << "libkaddrbk_vcard_xxport" << "libkaddrbk_csv_xxport" << "libkaddrbk_ldif_xxport");
    expect("Browser/View", "", QStringList()
           << "libkorganizerpart" << "libkaddressbookpart");
    expect("KCModule", "", QStringList() << "kmail" << "korganizer" << "kleopatra");
    const char *apps[] = { "kmail", "korganizer", "kaddressbook", "Kontact", "kleopatra_import", 0 };
    for (int i = 0; apps[i]; i++) {
        KService::Ptr s = KService::serviceByDesktopName(apps[i]);
        printf("service %s: %s\n", apps[i], s ? s->exec().latin1() : "MISSING");
        if (!s)
            errors++;
    }
    const char *protocols[] = { "imap", "imaps", "sieve", "mbox", "pop3", "pop3s", "smtp",
                                "smtps", "ldap", 0 };
    for (int i = 0; protocols[i]; i++) {
        bool known = KProtocolInfo::isKnownProtocol(QString(protocols[i]));
        printf("protocol %s: %s\n", protocols[i], known ? "ok" : "MISSING");
        if (!known)
            errors++;
    }
    return errors ? 1 : 0;
}
EOF
cmake -S . -B build >cmake.log 2>&1 || { cat cmake.log; fail "cmake"; }
cmake --build build >make.log 2>&1 || { cat make.log; fail "build of the KTrader client"; }
./build/pimtrader 2>pimtrader.err || { cat pimtrader.err; fail "kdepim services missing in ksycoca"; }
timeout 30 dcopserver_shutdown --wait || fail "dcopserver_shutdown"

step "kdeinit (dcopserver, klauncher, kded)"
kdeinit +kcminit_startup >kdeinit.log 2>&1 || true
for _ in $(seq 100); do dcop 2>/dev/null | grep -q '^kded$' && break; sleep 0.1; done
dcop | grep -q '^klauncher$' || { cat kdeinit.log; fail "klauncher not running"; }

# start <app> [name]: start a program and wait until it registers with DCOP
# (under its own name), then quit it again
start() {
    local app=$1 name=${2:-$1}
    "$app" >"$app.log" 2>&1 &
    local pid=$!
    for _ in $(seq 300); do
        dcop 2>/dev/null | grep -q "^$name" && break
        kill -0 $pid 2>/dev/null || { cat "$app.log"; fail "$app exited"; }
        sleep 0.1
    done
    dcop 2>/dev/null | grep -q "^$name" || { cat "$app.log"; fail "$app did not register with DCOP"; }
    local reg
    reg=$(dcop | grep "^$name" | head -1)
    echo "$app: running, registered as $reg"
    timeout 10 dcop "$reg" MainApplication-Interface quit >/dev/null 2>&1 || true
    for _ in $(seq 100); do dcop 2>/dev/null | grep -qx "$reg" || break; sleep 0.1; done
    ! dcop 2>/dev/null | grep -qx "$reg" || fail "$app did not quit"
    kill $pid 2>/dev/null || true
    wait $pid 2>/dev/null || true
}

step "kmail, korganizer, kaddressbook, kontact, kleopatra start under Xvfb"
start kmail
start korganizer
start kaddressbook
start kontact
start kleopatra

echo
echo "ALL TESTS PASSED"
