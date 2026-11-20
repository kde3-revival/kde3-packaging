#!/bin/bash
# Build and test kde3-revival packages in clean podman containers.
#
#   ./build.sh <distro> <package>        build in a fresh container and lint;
#                                        packages and logs go to out/<distro>/
#   ./build.sh test <distro> <package>   install the packages from out/<distro>/
#                                        in a fresh container and run
#                                        tests/<package>.sh in it
#
#   <package>: kde3-qt, kde3-kdelibs (needs kde3-qt), kde3-kdebase (needs
#              kde3-qt and kde3-kdelibs).  The packages a package needs are
#              not taken from a repository: build them first; their
#              packages in out/<distro>/ are installed into the container
#              before the build or the test.
#
#   <distro>:  arch (archlinux:latest, makepkg)
#              fedora (fedora:latest, rpmbuild)
#
# Environment:
#   JOBS       parallel make jobs (default: nproc)
#   ARCH_IMAGE, FEDORA_IMAGE   override the base images
#
# Source tarballs found in out/sources/ (put there by "CLONE=... ./bump.sh"
# for a repository that cannot be downloaded) are used instead of
# downloading them; their checksums are verified as usual.
#
# The containers run rootless; inside them the build runs as an unprivileged
# user "builder".  Nothing is installed on the host.

set -euo pipefail

top=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-$(nproc)}
ARCH_IMAGE=${ARCH_IMAGE:-docker.io/library/archlinux:latest}
FEDORA_IMAGE=${FEDORA_IMAGE:-registry.fedoraproject.org/fedora:latest}

usage() {
    sed -n '2,27p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

# The kde3-revival packages each package is built and tested with.
declare -A deps=(
    [kde3-qt]=""
    [kde3-kdelibs]="kde3-qt"
    [kde3-kdebase]="kde3-qt kde3-kdelibs"
)

# --init: an init process that reaps orphans; without it, daemons that
# exit (dcopserver) stay zombies and "dcopserver_shutdown --wait" waits
# for them forever.
run() {   # run <image> <script> [extra podman args...]
    local image=$1 script=$2; shift 2
    podman run --rm -i --init --security-opt label=disable \
        -e JOBS="$JOBS" -e PKG="$pkg" -e DEPS="${deps[$pkg]}" \
        -v "$top:/src:ro" -v "$out:/out" -v "$top/out/$distro:/deps:ro" \
        -v "$top/out/sources:/sources:ro" "$@" \
        "$image" bash -euo pipefail -c "$script"
}

# --------------------------------------------------------------------------
# Arch Linux
# --------------------------------------------------------------------------

# The packages (without the debug ones) of the packages in $DEPS, from /deps.
arch_deps='
deps=()
for d in $DEPS; do
    deps+=($(ls /deps/$d/*.pkg.tar.zst | grep -v -- -debug-))
done
if [[ ${#deps[@]} -gt 0 ]]; then
    printf "installing %s\n" "${deps[@]##*/}"
    pacman -U --noconfirm "${deps[@]}" >/dev/null
fi
'

arch_build='
pacman -Syu --noconfirm --needed base-devel namcap sudo >/dev/null
'$arch_deps'
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
cp -r /src/arch/$PKG /home/builder/pkg
cp /sources/$PKG-* /home/builder/pkg/ 2>/dev/null || true
chown -R builder: /home/builder/pkg
cd /home/builder/pkg
sudo -u builder MAKEFLAGS="-j$JOBS" makepkg --syncdeps --noconfirm --cleanbuild
for p in PKGBUILD *.pkg.tar.zst; do
    echo "=== namcap $p"
    namcap "$p" || true
done 2>&1 | tee namcap.log
rm -f /out/*.pkg.tar.zst
cp *.pkg.tar.zst namcap.log /out/
'

arch_test='
pacman -Syu --noconfirm --needed gcc make cmake pkgconf xorg-server-xvfb >/dev/null
DEPS="$DEPS $PKG"
'$arch_deps'
useradd -m tester
cp /src/tests/$PKG.sh /src/tests/common.sh /home/tester/
su - tester -c "bash -l ./$PKG.sh"
'

# --------------------------------------------------------------------------
# Fedora
# --------------------------------------------------------------------------

# The binary packages of the packages in $DEPS, from /deps.
fedora_deps='
deps=()
for d in $DEPS; do
    deps+=($(ls /deps/$d/*.rpm | grep -v -e "\.src\.rpm$" -e -debuginfo- -e -debugsource-))
done
if [[ ${#deps[@]} -gt 0 ]]; then
    printf "installing %s\n" "${deps[@]##*/}"
    dnf -y -q install "${deps[@]}" >/dev/null
fi
'

fedora_build='
dnf -y -q install rpm-build rpmdevtools rpmlint "dnf-command(builddep)" >/dev/null
'$fedora_deps'
dnf -y -q builddep /src/fedora/$PKG/$PKG.spec >/dev/null
useradd -m builder
su - builder -c "
    set -euo pipefail
    rpmdev-setuptree
    cp /src/fedora/$PKG/* rpmbuild/SOURCES/
    cp /sources/$PKG-* rpmbuild/SOURCES/ 2>/dev/null || true
    mv rpmbuild/SOURCES/$PKG.spec rpmbuild/SPECS/
    spectool -g -S -C rpmbuild/SOURCES rpmbuild/SPECS/$PKG.spec
    (cd rpmbuild/SOURCES && sha256sum -c sources)
    rpmbuild -ba --define \"_smp_build_ncpus $JOBS\" rpmbuild/SPECS/$PKG.spec
    cd rpmbuild
    rpmlint SPECS/$PKG.spec SRPMS/*.rpm RPMS/*/*.rpm 2>&1 | tee rpmlint.log || true
"
rm -f /out/*.rpm
cp /home/builder/rpmbuild/RPMS/*/*.rpm /home/builder/rpmbuild/SRPMS/*.rpm \
   /home/builder/rpmbuild/rpmlint.log /out/
'

fedora_test='
dnf -y -q install gcc-c++ make cmake pkgconf-pkg-config xorg-x11-server-Xvfb >/dev/null
DEPS="$DEPS $PKG"
'$fedora_deps'
useradd -m tester
cp /src/tests/$PKG.sh /src/tests/common.sh /home/tester/
su - tester -c "bash -l ./$PKG.sh"
'

# --------------------------------------------------------------------------

mode=build
if [[ ${1:-} == test ]]; then mode=test; shift; fi
[[ $# -eq 2 ]] || usage
distro=$1 pkg=$2

case $distro in
    arch)   image=$ARCH_IMAGE;   recipe=$top/arch/$pkg/PKGBUILD ;;
    fedora) image=$FEDORA_IMAGE; recipe=$top/fedora/$pkg/$pkg.spec ;;
    *) usage ;;
esac
[[ -f $recipe ]] || { echo "no such recipe: $recipe" >&2; exit 1; }

[[ -v deps[$pkg] ]] || { echo "unknown package $pkg" >&2; exit 1; }
for d in ${deps[$pkg]}; do
    compgen -G "$top/out/$distro/$d/*.$([[ $distro == arch ]] && echo pkg.tar.zst || echo rpm)" >/dev/null ||
        { echo "$pkg needs $d: run ./build.sh $distro $d first" >&2; exit 1; }
done

out=$top/out/$distro/$pkg
mkdir -p "$out" "$top/out/sources"
log=$out/$mode.log
script_var=${distro}_${mode}

echo "$mode $pkg on $distro ($image), log: $log"
run "$image" "${!script_var}" 2>&1 | tee "$log"
