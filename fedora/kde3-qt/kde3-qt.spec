# Qt 3.3.8b as maintained by kde3-revival, installed in /opt/kde3-qt.
# Snapshot of a fixed commit; run ../../bump.sh kde3-qt to move to the
# latest commit of the master branch (updates commit, date, Release, the
# changelog and the "sources" checksum file).

%global commit     e3806fb2e4e4ececd37d5c8abfc26a1f2323712f
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261120

%global qtdir      /opt/kde3-qt

Name:           kde3-qt
Version:        3.3.8b+git%{date}
Release:        2%{?dist}
Summary:        Qt 3 toolkit maintained for kde3-revival

License:        GPL-2.0-only OR GPL-3.0-only OR QPL-1.0
URL:            https://github.com/kde3-revival/kde3-qt
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz
Source1:        kde3-qt.sh
Source2:        kde3-qt.csh

BuildRequires:  gcc-c++
BuildRequires:  make
BuildRequires:  cups-devel
BuildRequires:  fontconfig-devel
BuildRequires:  freetype-devel
BuildRequires:  libICE-devel
BuildRequires:  libjpeg-turbo-devel
BuildRequires:  libmng-devel
BuildRequires:  libpng-devel
BuildRequires:  libSM-devel
BuildRequires:  libX11-devel
BuildRequires:  libXcursor-devel
BuildRequires:  libXext-devel
BuildRequires:  libXft-devel
BuildRequires:  libXi-devel
BuildRequires:  libXinerama-devel
BuildRequires:  libXmu-devel
BuildRequires:  libXrandr-devel
BuildRequires:  libXrender-devel
BuildRequires:  mesa-libGL-devel
BuildRequires:  mesa-libGLU-devel
BuildRequires:  zlib-devel

%description
Qt 3.3.8b (qt-x11-free) as maintained by the kde3-revival project as the
base for running KDE 3.5 on current systems.  It is installed in
%{qtdir} and does not conflict with the Qt packages of the
distribution.

This package contains the shared libraries, the image format plugins, the
translations and the Qt settings tool.

%package devel
Summary:        Development files for kde3-qt
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       pkgconfig
# qmake links these libraries explicitly into every Qt program (the mkspec's
# QMAKE_LIBS_X11, QMAKE_LIBS_OPENGL etc. and the .prl files of the static
# libraries); kde3-qt.pc lists them in Libs.private.
Requires:       fontconfig-devel
Requires:       freetype-devel
Requires:       libICE-devel
Requires:       libpng-devel
Requires:       libSM-devel
Requires:       libX11-devel
Requires:       libXcursor-devel
Requires:       libXext-devel
Requires:       libXft-devel
Requires:       libXi-devel
Requires:       libXinerama-devel
Requires:       libXmu-devel
Requires:       libXrandr-devel
Requires:       libXrender-devel
Requires:       mesa-libGL-devel
Requires:       mesa-libGLU-devel
Requires:       zlib-devel
# libqassistantclient, libdesignercore and libeditor are only built as
# static libraries.
Provides:       %{name}-static = %{version}-%{release}

%description devel
Headers, qmake with its mkspecs, moc, uic, lupdate and lrelease, the
pkg-config file and the static libraries (the Qt Assistant client and the
Qt Designer core) for building programs against kde3-qt.

%package designer
Summary:        Qt Designer, Qt Assistant and Qt Linguist for kde3-qt
Requires:       %{name}%{?_isa} = %{version}-%{release}

%description designer
The GUI development tools of kde3-qt: Qt Designer (with its plugins and
templates), Qt Assistant (the documentation browser, install
%{name}-doc for the documentation) and Qt Linguist.

%package doc
Summary:        Documentation for kde3-qt
BuildArch:      noarch

%description doc
The HTML reference documentation of kde3-qt (read with Qt Assistant or a
web browser) and the class reference man pages.


%prep
%autosetup -n %{name}-%{commit}

%build
# Build with the distribution flags and without qmake's own stripping (rpm
# extracts the debug info).  The flags go into the base variables, which
# are also used for the bootstrap qmake.  The pristine qmake.conf is
# installed, so that programs built later against this Qt do not inherit
# them.
cp -p mkspecs/linux-g++/qmake.conf qmake.conf.pristine
setvar() { sed -i "s|^\($1[[:space:]]*\)=.*|\1= $2|" mkspecs/linux-g++/qmake.conf; }
setvar QMAKE_CFLAGS           "%{build_cflags}"
setvar QMAKE_CXXFLAGS         "%{build_cxxflags}"
setvar QMAKE_CFLAGS_RELEASE   ""
setvar QMAKE_CXXFLAGS_RELEASE ""
setvar QMAKE_LFLAGS           "%{build_ldflags}"
setvar QMAKE_STRIP            ""

# configure asks to accept the license (GPL 2/3 or QPL); there is no option
# for that, so answer on stdin.
echo yes | ./configure -prefix %{qtdir}
# Fail instead of silently building a reduced library.
for feature in opengl cups xinerama xcursor xrandr xrender xftfreetype tablet; do
    grep -q "^CONFIG +=.* $feature\b" .qmake.cache || { echo "configure: $feature not enabled" >&2; exit 1; }
done

# The library, plugins and tools; "make" alone would also build the
# tutorial and the examples, which are not packaged.
%make_build sub-tools

%install
make INSTALL_ROOT=%{buildroot} install

root=%{buildroot}%{qtdir}

install -p -m644 qmake.conf.pristine $root/mkspecs/linux-g++/qmake.conf

# Man pages are not installed by "make install"; /opt/kde3-qt/man is found
# by man(1) through PATH.
install -d $root/man/man1 $root/man/man3
install -p -m644 doc/man/man1/*.1 $root/man/man1/
install -p -m644 doc/man/man3/*.3qt $root/man/man3/

# Environment and pkg-config (a relative link, so that it also resolves
# inside a chroot or an image mounted elsewhere).
install -D -p -m644 %{SOURCE1} %{buildroot}%{_sysconfdir}/profile.d/kde3-qt.sh
install -D -p -m644 %{SOURCE2} %{buildroot}%{_sysconfdir}/profile.d/kde3-qt.csh
install -d %{buildroot}%{_libdir}/pkgconfig
ln -s ../../..%{qtdir}/lib/pkgconfig/kde3-qt.pc %{buildroot}%{_libdir}/pkgconfig/kde3-qt.pc


%files
%license LICENSE.GPL2 LICENSE.GPL3 LICENSE.QPL
%doc README changes-3.3.8 changes-3.3.8b
%config(noreplace) %{_sysconfdir}/profile.d/kde3-qt.sh
%config(noreplace) %{_sysconfdir}/profile.d/kde3-qt.csh
%dir %{qtdir}
%dir %{qtdir}/bin
%dir %{qtdir}/lib
%dir %{qtdir}/man
%dir %{qtdir}/plugins
%dir %{qtdir}/translations
%{qtdir}/bin/qtconfig
%{qtdir}/lib/libkde3-qt.so.3*
%{qtdir}/lib/libkde3-qui.so.1*
%{qtdir}/plugins/imageformats
%{qtdir}/translations/qt_*.qm

%files devel
%{qtdir}/bin/lrelease
%{qtdir}/bin/lupdate
%{qtdir}/bin/moc
%{qtdir}/bin/qm2ts
%{qtdir}/bin/qmake
%{qtdir}/bin/uic
%{qtdir}/include
%{qtdir}/mkspecs
%{qtdir}/lib/libkde3-qt.so
%{qtdir}/lib/libkde3-qui.so
%{qtdir}/lib/libkde3-qt.prl
%{qtdir}/lib/libkde3-qui.prl
%{qtdir}/lib/libqassistantclient.a
%{qtdir}/lib/libqassistantclient.prl
%{qtdir}/lib/libdesignercore.a
%{qtdir}/lib/libdesignercore.prl
%{qtdir}/lib/libeditor.a
%{qtdir}/lib/libeditor.prl
%{qtdir}/lib/pkgconfig
%{_libdir}/pkgconfig/kde3-qt.pc
%{qtdir}/man/man1

%files designer
%{qtdir}/bin/assistant
%{qtdir}/bin/designer
%{qtdir}/bin/linguist
%{qtdir}/phrasebooks
%{qtdir}/plugins/designer
%{qtdir}/templates
%{qtdir}/translations/assistant_*.qm

%files doc
%license LICENSE.GPL2 LICENSE.GPL3 LICENSE.QPL
%dir %{qtdir}
%dir %{qtdir}/man
%{qtdir}/doc
%{qtdir}/man/man3

%changelog
* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.3.8b+git20261120-2
- Snapshot of kde3-revival/kde3-qt commit e3806fb

* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.3.8b+git20261120-1
- Snapshot of kde3-revival/kde3-qt commit b2b4572
