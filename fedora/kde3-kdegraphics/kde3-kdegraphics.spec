# kdegraphics 3.5.10 as maintained by kde3-revival (KView, KSnapshot and
# KRuler only), installed in /opt/kde3.
# Snapshot of a fixed commit; run ../../bump.sh kde3-kdegraphics to move to
# the latest commit of the master branch (updates commit, date, Release,
# the changelog and the "sources" checksum file).
#
# kde3-qt and kde3-kdelibs are not in a repository: build them first
# (../../build.sh does that with the packages in out/).

%global commit     cb20689e741d52fad2d47937657c03a06db9aea4
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261121

%global kde3dir    /opt/kde3

Name:           kde3-kdegraphics
Version:        3.5.10+git%{date}
Release:        1%{?dist}
Summary:        KDE 3.5 graphics programs (KView, KSnapshot, KRuler) maintained for kde3-revival

License:        GPL-2.0-or-later AND LGPL-2.0-or-later AND GFDL-1.2-or-later
URL:            https://github.com/kde3-revival/kde3-kdegraphics
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-kdelibs-devel
# The Shape extension: KSnapshot cuts shaped windows to their shape.
BuildRequires:  libXext-devel

Requires:       kde3-kdelibs%{?_isa}
# kdebase's khotkeys binds the Print key to KSnapshot.
Recommends:     kde3-kdebase%{?_isa}

%description
kdegraphics 3.5.10 as maintained by the kde3-revival project, reduced to
three programs: the image viewer KView (with its embeddable viewer part
and the slide show, browser and effects plugins), the screenshot program
KSnapshot and the screen ruler KRuler.  The image formats are those of
kde3-qt and of the kimgio plugins of kde3-kdelibs.  It is installed in
%{kde3dir} and does not conflict with the graphics programs of KDE Gear.


%prep
%autosetup -n %{name}-%{commit}

%build
# The prefix, the library directory (/opt/kde3/lib) and the RUNPATH come
# from kdelibs' CMake package (CMAKE_INSTALL_PREFIX given to %%cmake is
# overridden here, the LIB_SUFFIX of %%cmake is not used).
# CMAKE_BUILD_TYPE=None: the distribution flags only.
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir} \
    -DKDEGRAPHICS_WITH_XSHAPE=ON
# Fail instead of silently building without an optional feature.
for have in HAVE_X11_EXTENSIONS_SHAPE_H; do
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

for f in bin/kview bin/ksnapshot bin/kruler lib/kde3/libkviewviewer.so \
         lib/kde3/libkviewcanvas.so; do
    [ -e $root/$f ] || { echo "not built: $f" >&2; exit 1; }
done

# libkimageviewer is only used by KView's parts and installs no headers:
# its unversioned link is of no use.
rm $root/lib/libkimageviewer.so

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
%doc README

%changelog
* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261121-1
- Snapshot of kde3-revival/kde3-kdegraphics commit cb20689
