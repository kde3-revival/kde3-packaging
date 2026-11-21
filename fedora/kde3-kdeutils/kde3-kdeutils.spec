# kdeutils 3.5.10 as maintained by kde3-revival, installed in /opt/kde3.
# Snapshot of a fixed commit; run ../../bump.sh kde3-kdeutils to move to the
# latest commit of the master branch (updates commit, date, Release, the
# changelog and the "sources" checksum file).
#
# kde3-qt and kde3-kdelibs are not in a repository: build them first
# (../../build.sh does that with the packages in out/).

%global commit     66caeb3d93312dbc73a381e1dd8b0c833048012f
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261121

%global kde3dir    /opt/kde3

Name:           kde3-kdeutils
Version:        3.5.10+git%{date}
Release:        1%{?dist}
Summary:        KDE 3.5 utilities (Ark, KCalc, KHexEdit, ...) for kde3-revival

License:        GPL-2.0-or-later AND LGPL-2.0-only AND LGPL-2.0-or-later AND GFDL-1.2-or-later
URL:            https://github.com/kde3-revival/kde3-kdeutils
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-kdelibs-devel
BuildRequires:  gmp-devel

Requires:       kde3-kdelibs%{?_isa}
# Ark drives command line tools: tar, gzip and bzip2 for its basic
# formats; the others are looked up when an archive of their kind is
# opened.  KDiskFree runs df.
Requires:       tar
Requires:       gzip
Requires:       bzip2
Requires:       coreutils
Recommends:     xz
Recommends:     zstd
Recommends:     lz4
Recommends:     zip
Recommends:     unzip
Recommends:     7zip
Recommends:     udisks2
# not in Fedora (RPM Fusion nonfree)
Suggests:       unrar
Suggests:       lzop

%description
kdeutils 3.5.10 as maintained by the kde3-revival project: the archive
manager Ark (tar with gzip, bzip2, xz, zstd and lz4, zip, 7-Zip, RAR
through the usual command line tools), the scientific calculator KCalc,
the character selector KCharSelect, the disk space viewer KDiskFree
(with KwikDisk and its KControl module), the binary editor KHexEdit
(with its KPart), the countdown launcher KTimer and the KDE Wallet
Manager.  It is installed in %{kde3dir} and does not conflict with the
utilities of KDE Gear.


%prep
%autosetup -n %{name}-%{commit}

%build
# The prefix, the library directory (/opt/kde3/lib) and the RUNPATH come
# from kdelibs' CMake package (CMAKE_INSTALL_PREFIX given to %%cmake is
# overridden here, the LIB_SUFFIX of %%cmake is not used).
# CMAKE_BUILD_TYPE=None: the distribution flags only.  KCalc needs GMP
# (KDEUTILS_BUILD_KCALC fails without it).
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir} \
    -DKDEUTILS_BUILD_KCALC=ON
for have in HAVE_GMP HAVE_LONG_DOUBLE HAVE_L_FUNCS; do
    grep -q "^#define $have 1" %{__cmake_builddir}/config.h || { echo "configure: $have not set" >&2; exit 1; }
done
%cmake_build

%install
# The RUNPATHs have, besides $ORIGIN, the absolute /opt/kde3/lib and
# /opt/kde3-qt/lib, which check-rpaths calls "invalid" (anything outside
# /usr/lib*).
export QA_RPATHS=$((0x0002))
%cmake_install

root=%{buildroot}%{kde3dir}

for f in bin/ark bin/kcalc bin/kcharselect bin/kdf bin/kwikdisk bin/khexedit \
         bin/ktimer bin/kwalletmanager lib/kde3/libarkpart.so \
         lib/kde3/libkhexedit2part.so lib/kde3/kcm_kdf.so lib/kde3/kcm_kwallet.so; do
    [ -e $root/$f ] || { echo "not built: $f" >&2; exit 1; }
done

# libkhexeditcommon is private to the khexedit2 part: no headers are
# installed, so the unversioned link is of no use (and no -devel package).
rm $root/lib/libkhexeditcommon.so

# The file list of the tree in /opt/kde3.  Directories that kde3-kdelibs
# has (installed for the build) are left to it.
(
    cd %{buildroot}
    find .%{kde3dir} -type d | sed 's|^\.||' | while read -r d; do
        [ -d "$d" ] || echo "%%dir \"$d\""
    done
    find .%{kde3dir} ! -type d | sed 's|^\.\(.*\)$|"\1"|'
) | sort >main.list


%files -f main.list
%license COPYING COPYING-DOCS
%doc README AUTHORS

%changelog
* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261121-1
- Snapshot of kde3-revival/kde3-kdeutils commit 66caeb3

