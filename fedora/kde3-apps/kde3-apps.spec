# kde3-apps (the applications of kdeutils and kdegraphics 3.5.10 as
# maintained by kde3-revival), installed in /opt/kde3: one source tree,
# one sub-package per application.  Snapshot of a fixed commit; run
# ../../bump.sh kde3-apps to move to the latest commit of the master branch
# (updates commit, date, Release, the changelog and the "sources" checksum
# file).
#
# kde3-qt and kde3-kdelibs are not in a repository: build them first
# (../../build.sh does that with the packages in out/).
#
# kde3-apps replaces the packages kde3-kdeutils and kde3-kdegraphics: the
# package kde3-apps itself (all applications) obsoletes them, so an
# upgrade installs every application they had; each application's
# package conflicts with the old package that held its files.

%global commit     210f071ba2a329762d39297ee8ba8f7ed1ad7be3
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261123

%global kde3dir    /opt/kde3
# The first version of kde3-apps; kde3-kdeutils and kde3-kdegraphics older
# than that are replaced.
%global replaced   3.5.10+git20261123

# <application directory>:<package>; the handbook in doc/<directory> goes
# with it (and doc/kinfocenter, the handbook of KDiskFree's module, with
# kdf).
%global apps ark:kde3-ark kcalc:kde3-kcalc kcharselect:kde3-kcharselect kdf:kde3-kdf khexedit:kde3-khexedit ktimer:kde3-ktimer kwallet:kde3-kwalletmanager kview:kde3-kview kruler:kde3-kruler ksnapshot:kde3-ksnapshot

Name:           kde3-apps
Version:        3.5.10+git%{date}
Release:        1%{?dist}
Summary:        KDE 3.5 applications (Ark, KCalc, KView, KSnapshot, ...) for kde3-revival

License:        GPL-2.0-or-later AND GPL-2.0-only AND LGPL-2.0-only AND LGPL-2.0-or-later AND GFDL-1.1-or-later
URL:            https://github.com/kde3-revival/kde3-apps
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-kdelibs-devel
# KCalc's arbitrary precision numbers
BuildRequires:  gmp-devel
# The Shape extension: KSnapshot cuts shaped windows to their shape.
BuildRequires:  libXext-devel

Requires:       kde3-ark%{?_isa} = %{version}-%{release}
Requires:       kde3-kcalc%{?_isa} = %{version}-%{release}
Requires:       kde3-kcharselect%{?_isa} = %{version}-%{release}
Requires:       kde3-kdf%{?_isa} = %{version}-%{release}
Requires:       kde3-khexedit%{?_isa} = %{version}-%{release}
Requires:       kde3-ktimer%{?_isa} = %{version}-%{release}
Requires:       kde3-kwalletmanager%{?_isa} = %{version}-%{release}
Requires:       kde3-kview%{?_isa} = %{version}-%{release}
Requires:       kde3-kruler%{?_isa} = %{version}-%{release}
Requires:       kde3-ksnapshot%{?_isa} = %{version}-%{release}
Obsoletes:      kde3-kdeutils < %{replaced}
Provides:       kde3-kdeutils = %{version}-%{release}
Obsoletes:      kde3-kdegraphics < %{replaced}
Provides:       kde3-kdegraphics = %{version}-%{release}

%description
The applications of the KDE 3.5 desktop maintained by the kde3-revival
project that are not part of kdelibs, kdebase or kdepim, from kdeutils
and kdegraphics 3.5.10: Ark, KCalc, KCharSelect, KDiskFree, KHexEdit,
KTimer, KWalletManager, KView, KRuler and KSnapshot.  This package
installs all of them; each is a package of its own.  They are installed
in %{kde3dir} and do not conflict with the applications of KDE Gear.

%package -n kde3-ark
Summary:        Archive manager for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}
# Ark drives command line tools: tar, gzip and bzip2 for its basic
# formats; the others are looked up when an archive of their kind is
# opened.
Requires:       tar
Requires:       gzip
Requires:       bzip2
Recommends:     xz
Recommends:     zstd
Recommends:     lz4
Recommends:     zip
Recommends:     unzip
Recommends:     7zip
# not in Fedora (RPM Fusion nonfree)
Suggests:       unrar
Suggests:       lzop

%description -n kde3-ark
Ark, the archive manager of KDE 3.5 as maintained by the kde3-revival
project: tar with gzip, bzip2, xz, zstd and lz4, zip, 7-Zip and RAR
through the usual command line tools, also as a KPart for Konqueror.
Installed in %{kde3dir}.

%package -n kde3-kcalc
Summary:        Scientific calculator for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND LGPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}

%description -n kde3-kcalc
KCalc, the scientific calculator of KDE 3.5 as maintained by the
kde3-revival project, with arbitrary precision (GMP).  Installed in
%{kde3dir}.

%package -n kde3-kcharselect
Summary:        Character selector for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}

%description -n kde3-kcharselect
KCharSelect of KDE 3.5 as maintained by the kde3-revival project: picks
special characters from any font and copies them to the clipboard.
Installed in %{kde3dir}.

%package -n kde3-kdf
Summary:        Disk space viewer for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}
# KDiskFree runs df, and mounts and unmounts through udisksctl.
Requires:       coreutils
Recommends:     udisks2

%description -n kde3-kdf
KDiskFree of KDE 3.5 as maintained by the kde3-revival project: the free
space of the mounted file systems, with KwikDisk (in the system tray) and
the disk usage module of the Control Center.  Installed in %{kde3dir}.

%package -n kde3-khexedit
Summary:        Binary file editor for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND LGPL-2.0-only AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}

%description -n kde3-khexedit
KHexEdit, the binary file editor of KDE 3.5 as maintained by the
kde3-revival project, with the KHexEdit2 widget library and its KPart.
Installed in %{kde3dir}.

%package -n kde3-ktimer
Summary:        Countdown launcher for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}

%description -n kde3-ktimer
KTimer of KDE 3.5 as maintained by the kde3-revival project: runs
programs after a countdown.  Installed in %{kde3dir}.

%package -n kde3-kwalletmanager
Summary:        Wallet manager for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdeutils < %{replaced}

%description -n kde3-kwalletmanager
KWalletManager of KDE 3.5 as maintained by the kde3-revival project:
manages the wallets of KWallet, with its Control Center module.
Installed in %{kde3dir}.

%package -n kde3-kview
Summary:        Image viewer for KDE 3.5 (kde3-revival)
License:        GPL-2.0-only AND GPL-2.0-or-later AND LGPL-2.0-only AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdegraphics < %{replaced}

%description -n kde3-kview
KView, the image viewer of KDE 3.5 as maintained by the kde3-revival
project, with its embeddable viewer part and the slide show, browser
and effects plugins.  The image formats are those of kde3-qt and of the
kimgio plugins of kde3-kdelibs.  Installed in %{kde3dir}.

%package -n kde3-kruler
Summary:        Screen ruler for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdegraphics < %{replaced}

%description -n kde3-kruler
KRuler of KDE 3.5 as maintained by the kde3-revival project: a screen
ruler in pixels, to measure distances on the screen.  Installed in
%{kde3dir}.

%package -n kde3-ksnapshot
Summary:        Screen capture program for KDE 3.5 (kde3-revival)
License:        GPL-2.0-or-later AND LGPL-2.0-or-later AND GFDL-1.1-or-later
Requires:       kde3-kdelibs%{?_isa}
Conflicts:      kde3-kdegraphics < %{replaced}
# KWin's screenshot shortcuts (Print, Shift+Print, Alt+Print) run KSnapshot.
Recommends:     kde3-kdebase%{?_isa}

%description -n kde3-ksnapshot
KSnapshot of KDE 3.5 as maintained by the kde3-revival project: screen
capture of the full screen, a window or a region.  Installed in
%{kde3dir}.


%prep
%autosetup -n %{name}-%{commit}

%build
# The prefix, the library directory (/opt/kde3/lib) and the RUNPATH come
# from kdelibs' CMake package (CMAKE_INSTALL_PREFIX given to %%cmake is
# overridden here, the LIB_SUFFIX of %%cmake is not used).
# CMAKE_BUILD_TYPE=None: the distribution flags only.  Every application
# is switched on explicitly (KDE3_APPS_KCALC and
# KDE3_APPS_KSNAPSHOT_XSHAPE fail without GMP and the Shape extension).
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir} \
    -DKDE3_APPS_ARK=ON \
    -DKDE3_APPS_KCALC=ON \
    -DKDE3_APPS_KCHARSELECT=ON \
    -DKDE3_APPS_KDF=ON \
    -DKDE3_APPS_KHEXEDIT=ON \
    -DKDE3_APPS_KTIMER=ON \
    -DKDE3_APPS_KWALLET=ON \
    -DKDE3_APPS_KVIEW=ON \
    -DKDE3_APPS_KRULER=ON \
    -DKDE3_APPS_KSNAPSHOT=ON \
    -DKDE3_APPS_KSNAPSHOT_XSHAPE=ON
for have in HAVE_GMP HAVE_LONG_DOUBLE HAVE_L_FUNCS HAVE_X11_EXTENSIONS_SHAPE_H; do
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
         bin/ktimer bin/kwalletmanager bin/kview bin/ksnapshot bin/kruler \
         lib/kde3/libarkpart.so lib/kde3/libkhexedit2part.so lib/kde3/kcm_kdf.so \
         lib/kde3/kcm_kwallet.so lib/kde3/libkviewviewer.so lib/kde3/libkviewcanvas.so; do
    [ -e $root/$f ] || { echo "not built: $f" >&2; exit 1; }
done

# libkhexeditcommon (the khexedit2 part) and libkimageviewer (KView's
# parts) install no headers: their unversioned links are of no use (and
# there is no -devel package).
unlinks="lib/libkhexeditcommon.so lib/libkimageviewer.so"
for f in $unlinks; do rm $root/$f; done

# The file list of each application: what the install script of its
# build directory and of its handbook's installs.  Directories that
# kde3-kdelibs has (installed for the build) are left to it.  Every
# installed file must be in exactly one list.
rm -rf apps && mkdir apps
for a in %{apps}; do
    dir=${a%%:*} pkg=${a#*:}
    dirs="$dir doc/$dir"
    [ $dir = kdf ] && dirs="$dirs doc/kinfocenter"
    for d in $dirs; do
        DESTDIR=$PWD/apps/$pkg cmake --install %{__cmake_builddir}/$d >/dev/null
    done
    for f in $unlinks; do rm -f apps/$pkg%{kde3dir}/$f; done
    (
        cd apps/$pkg
        find .%{kde3dir} -type d | sed 's|^\.||' | while read -r d; do
            [ -d "$d" ] || echo "%%dir \"$d\""
        done
        find .%{kde3dir} ! -type d | sed 's|^\.\(.*\)$|"\1"|'
    ) | sort >$pkg.list
done
(cd %{buildroot} && find .%{kde3dir} ! -type d | sed 's|^\.\(.*\)$|"\1"|' | sort) >all.list
cat kde3-*.list | grep -v '^%%dir' | sort >split.list
[ -z "$(uniq -d split.list)" ] || { echo "in more than one package:" >&2; uniq -d split.list >&2; exit 1; }
cmp -s all.list split.list || { echo "file lists differ from the installation:" >&2; diff all.list split.list >&2; exit 1; }


# The package of all applications (it replaces kde3-kdeutils and
# kde3-kdegraphics) has only the documentation of the source tree.
%files
%license COPYING COPYING-DOCS
%doc README.md AUTHORS

%files -n kde3-ark -f kde3-ark.list
%license COPYING COPYING-DOCS

%files -n kde3-kcalc -f kde3-kcalc.list
%license COPYING COPYING-DOCS

%files -n kde3-kcharselect -f kde3-kcharselect.list
%license COPYING COPYING-DOCS

%files -n kde3-kdf -f kde3-kdf.list
%license COPYING COPYING-DOCS

%files -n kde3-khexedit -f kde3-khexedit.list
%license COPYING COPYING-DOCS

%files -n kde3-ktimer -f kde3-ktimer.list
%license COPYING COPYING-DOCS

%files -n kde3-kwalletmanager -f kde3-kwalletmanager.list
%license COPYING COPYING-DOCS

%files -n kde3-kview -f kde3-kview.list
%license COPYING COPYING-DOCS

%files -n kde3-kruler -f kde3-kruler.list
%license COPYING COPYING-DOCS

%files -n kde3-ksnapshot -f kde3-ksnapshot.list
%license COPYING COPYING-DOCS

%changelog
* Mon Nov 23 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261123-1
- Snapshot of kde3-revival/kde3-apps commit 210f071
- New package: kdeutils and kdegraphics merged into one source tree, one
  sub-package per application; replaces kde3-kdeutils and kde3-kdegraphics
