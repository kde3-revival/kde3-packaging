#!/bin/bash
# Build and test kde3-revival packages in clean podman containers.
#
#   ./build.sh <distro> <package>        build in a fresh container and lint;
#                                        packages and logs go to out/<distro>/
#   ./build.sh test <distro> <package>   install the packages from out/<distro>/
#                                        in a fresh container and run
#                                        tests/<package>.sh in it
#
#   <distro>:  arch (archlinux:latest, makepkg)
#              fedora (fedora:latest, rpmbuild)
#
# Environment:
#   JOBS       parallel make jobs (default: nproc)
#   ARCH_IMAGE, FEDORA_IMAGE   override the base images
#
# The containers run rootless; inside them the build runs as an unprivileged
# user "builder".  Nothing is installed on the host.

set -euo pipefail

top=$(cd "$(dirname "$0")" && pwd)
JOBS=${JOBS:-$(nproc)}
ARCH_IMAGE=${ARCH_IMAGE:-docker.io/library/archlinux:latest}
FEDORA_IMAGE=${FEDORA_IMAGE:-registry.fedoraproject.org/fedora:latest}

usage() {
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
}

run() {   # run <image> <script> [extra podman args...]
    local image=$1 script=$2; shift 2
    podman run --rm -i --security-opt label=disable \
        -e JOBS="$JOBS" -e PKG="$pkg" \
        -v "$top:/src:ro" -v "$out:/out" "$@" \
        "$image" bash -euo pipefail -c "$script"
}

# --------------------------------------------------------------------------
# Arch Linux
# --------------------------------------------------------------------------

arch_build='
pacman -Syu --noconfirm --needed base-devel namcap sudo >/dev/null
useradd -m builder
echo "builder ALL=(ALL) NOPASSWD: ALL" >/etc/sudoers.d/builder
cp -r /src/arch/$PKG /home/builder/pkg
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
pacman -Syu --noconfirm --needed gcc make pkgconf xorg-server-xvfb >/dev/null
pacman -U --noconfirm $(ls /out/*.pkg.tar.zst | grep -v -- -debug-) >/dev/null
useradd -m tester
cp /src/tests/$PKG.sh /home/tester/
su - tester -c "bash -l ./$PKG.sh"
'

# --------------------------------------------------------------------------
# Fedora
# --------------------------------------------------------------------------

fedora_build='
dnf -y -q install rpm-build rpmdevtools rpmlint "dnf-command(builddep)" >/dev/null
dnf -y -q builddep /src/fedora/$PKG/$PKG.spec >/dev/null
useradd -m builder
su - builder -c "
    set -euo pipefail
    rpmdev-setuptree
    cp /src/fedora/$PKG/* rpmbuild/SOURCES/
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
dnf -y -q install gcc-c++ make pkgconf-pkg-config xorg-x11-server-Xvfb >/dev/null
dnf -y -q install $(ls /out/*.rpm | grep -v -e "\.src\.rpm$" -e -debuginfo- -e -debugsource-) >/dev/null
useradd -m tester
cp /src/tests/$PKG.sh /home/tester/
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

out=$top/out/$distro/$pkg
mkdir -p "$out"
log=$out/$mode.log
script_var=${distro}_${mode}

echo "$mode $pkg on $distro ($image), log: $log"
run "$image" "${!script_var}" 2>&1 | tee "$log"
