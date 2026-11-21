# kdelibs 3.5.10 as maintained by kde3-revival, installed in /opt/kde3.
# Snapshot of a fixed commit; run ../../bump.sh kde3-kdelibs to move to the
# latest commit of the master branch (updates commit, date, Release, the
# changelog and the "sources" checksum file).
#
# kde3-qt is not in a repository: build it first (../../build.sh does that
# with the packages in out/).

%global commit     bff1f449ec1abd03ba2a2b2fb2206ec79b975a46
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261121

%global kde3dir    /opt/kde3
%global qtdir      /opt/kde3-qt

Name:           kde3-kdelibs
Version:        3.5.10+git%{date}
Release:        1%{?dist}
Summary:        KDE 3.5 core libraries maintained for kde3-revival

License:        LGPL-2.0-or-later AND GPL-2.0-or-later AND BSD-2-Clause AND GFDL-1.2-or-later
URL:            https://github.com/kde3-revival/kde3-kdelibs
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz
Source1:        kde3.sh
Source2:        kde3.csh
Source3:        KDE3LibsConfig.cmake
Source4:        KDE3LibsConfigVersion.cmake

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-qt-devel
BuildRequires:  perl-interpreter
BuildRequires:  avahi-compat-libdns_sd-devel
BuildRequires:  bzip2-devel
BuildRequires:  cairo-devel
BuildRequires:  cups-devel
BuildRequires:  fontconfig-devel
BuildRequires:  freetype-devel
BuildRequires:  krb5-devel
BuildRequires:  libacl-devel
BuildRequires:  libattr-devel
BuildRequires:  libICE-devel
BuildRequires:  libidn-devel
BuildRequires:  libjpeg-turbo-devel
BuildRequires:  libpng-devel
BuildRequires:  libpsl-devel
BuildRequires:  librsvg2-devel
BuildRequires:  libSM-devel
BuildRequires:  libsndfile-devel
BuildRequires:  libthai-devel
BuildRequires:  libtiff-devel
# kimgio's WebP plugin (kdelibs b825f3c and later)
BuildRequires:  libwebp-devel
# kimgio's HEIF, AVIF and JPEG XL plugins (kdelibs 6d08268, aa51ef9,
# 2c4e2b1 and later).  Fedora's libheif has no HEVC decoder: HEIC images
# need libheif-freeworld from RPM Fusion; AVIF is read with libavif.
BuildRequires:  libheif-devel
BuildRequires:  libavif-devel
BuildRequires:  libjxl-devel
BuildRequires:  libutempter-devel
BuildRequires:  libX11-devel
BuildRequires:  libXext-devel
BuildRequires:  libXft-devel
BuildRequires:  libxml2
BuildRequires:  libxml2-devel
BuildRequires:  libXrender-devel
BuildRequires:  libxslt-devel
BuildRequires:  brotli-devel
BuildRequires:  libzstd-devel
BuildRequires:  lz4-devel
BuildRequires:  openssl-devel
BuildRequires:  xz-devel
BuildRequires:  pulseaudio-libs-devel
BuildRequires:  zlib-devel

# dcopserver runs iceauth.
Requires:       iceauth
Requires:       kde3-qt%{?_isa}
Suggests:       aspell

%description
kdelibs 3.5.10 as maintained by the kde3-revival project: the core
libraries of KDE 3.5 (kdecore, kdeui, kio, kparts, khtml, kjs, kdeprint,
...), DCOP, kdeinit, kded, the ioslaves and the base data (mime types,
service types, icons).  It is installed in %{kde3dir} and does not
conflict with KDE Plasma or the KDE Frameworks of the distribution.

%package devel
Summary:        Development files for kde3-kdelibs
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       kde3-qt-devel%{?_isa}
Requires:       cmake-filesystem
# find_dependency() of KDE3LibsConfig.cmake and the INTERFACE_LINK_LIBRARIES
# of the exported targets.
Requires:       libICE-devel
Requires:       libpng-devel
Requires:       libSM-devel
Requires:       libX11-devel
Requires:       libXext-devel
Requires:       zlib-devel

%description devel
Headers, the CMake package KDE3Libs (find_package(KDE3Libs 3.5) with the
kde3_add_* functions) and the code generators run when building KDE 3
programs: dcopidl, dcopidl2cpp, dcopidlng, kconfig_compiler and
makekdewidgets.


%prep
%autosetup -n %{name}-%{commit}

%build
# CMAKE_BUILD_TYPE=None: the distribution flags only (the KDE build types
# add -O2 -g or -DNDEBUG -DNO_DEBUG).  The libraries go into
# /opt/kde3/lib (KDELIBSUFF empty), as kde3-qt's do into /opt/kde3-qt/lib:
# /opt trees are not multilib, and kdebase and every other module built
# against this kdelibs inherit the suffix from its CMake package.
# sysconfdir stays /opt/kde3/etc (kderc, xdg/menus), so nothing clashes
# with the /etc/xdg of KDE Plasma.  The PPD for CUPS is installed below.
# libpcre (PCRE 1) is not in Fedora any more: kjs falls back to the POSIX
# regex functions of glibc.
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir} \
    -DCMAKE_INSTALL_LIBDIR=lib \
    -DKDELIBSUFF= \
    -DKDE3_QT_RPATH=%{qtdir}/lib \
    -DKDE_DISTRIBUTION_TEXT="kde3-revival Fedora package" \
    -DKDE3_INSTALL_CUPS_PPD=OFF \
    -DKDE3_WITH_FAM=OFF \
    -DKDE3_WITH_PCRE=OFF \
    -DKDE3_WITH_LIBTHAI=ON
# Fail instead of silently building without an optional feature.
for have in HAVE_SSL HAVE_LIBIDN HAVE_LIBPSL HAVE_LIBGSSAPI HAVE_DNSSD \
            HAVE_PULSEAUDIO HAVE_LIBTIFF HAVE_UTEMPTER USE_POSIX_ACL \
            HAVE_LIBTHAI HAVE_INOTIFY HAVE_CUPS HAVE_LIBRSVG; do
    grep -q "^#define $have 1" %{__cmake_builddir}/config.h || { echo "configure: $have not set" >&2; exit 1; }
done
%cmake_build

%install
# The RUNPATHs have, besides $ORIGIN, the absolute /opt/kde3/lib (for
# setuid programs, where ld.so ignores $ORIGIN) and /opt/kde3-qt/lib, which
# check-rpaths calls "invalid" (anything outside /usr/lib*).
export QA_RPATHS=$((0x0002))
%cmake_install

# The PostScript driver for CUPS ("install-data-local" of kdeprint/cups).
install -D -p -m644 kdeprint/cups/postscript.ppd.gz \
    %{buildroot}%{_datadir}/cups/model/postscript.ppd.gz

# Environment and CMake package (see the files).
install -D -p -m644 %{SOURCE1} %{buildroot}%{_sysconfdir}/profile.d/kde3.sh
install -D -p -m644 %{SOURCE2} %{buildroot}%{_sysconfdir}/profile.d/kde3.csh
install -D -p -m644 -t %{buildroot}%{_libdir}/cmake/KDE3Libs %{SOURCE3} %{SOURCE4}

# The file lists of the tree in /opt/kde3: everything goes into the main
# package except the development files in devel.list; the setuid root
# helpers get their mode here (the install hooks only set it when
# installing as root): kgrantpty (pty ownership), start_kdeinit (OOM
# protection of kdeinit) and kpac_dhcp_helper (binds the DHCP port for
# proxy autoconfiguration).  Not fileshareset: it is a Perl script, and
# Linux ignores the setuid bit of scripts.
root=%{buildroot}%{kde3dir}
{
    echo %{kde3dir}/include
    echo %{kde3dir}/lib/cmake
    echo %{kde3dir}/share/apps/dcopidlng
    for f in dcopidl dcopidl2cpp dcopidlng kconfig_compiler makekdewidgets; do
        echo %{kde3dir}/bin/$f
    done
    # the unversioned links of the shared libraries (libkdeinit_*.so and the
    # modules are real files, loaded at run time)
    find $root/lib -maxdepth 1 -name 'lib*.so' -type l | sed "s|^%{buildroot}||"
} | sort >devel.list
(
    cd %{buildroot}
    echo .%{kde3dir} | sed 's|^\.\(.*\)$|%%dir "\1"|'
    find .%{kde3dir} -mindepth 1 -type d | sed 's|^\.\(.*\)$|%%dir "\1"|'
    find .%{kde3dir} ! -type d | sed 's|^\.\(.*\)$|"\1"|'
) | awk -v setuid="kgrantpty start_kdeinit kpac_dhcp_helper" '
    BEGIN { n = split(setuid, s, " "); for (i = 1; i <= n; i++) suid["%{kde3dir}/bin/" s[i]] = 1 }
    NR == FNR { devel[$0] = 1; next }
    {
        p = $0; sub(/^%%dir /, "", p); gsub(/"/, "", p)
        for (d in devel) if (p == d || index(p, d "/") == 1) next
        if (p in suid) { print "%%attr(4755,root,root) " $0; found++; next }
        print
    }
    END { if (found != n) { print "setuid helpers missing" >"/dev/stderr"; exit 1 } }' \
    devel.list - | sort >main.list
sed -i 's|^\(.*\)$|"\1"|' devel.list

%files -f main.list
%license COPYING COPYING.LIB COPYING.BSD COPYING-DOCS
%doc README AUTHORS
%config(noreplace) %{_sysconfdir}/profile.d/kde3.sh
%config(noreplace) %{_sysconfdir}/profile.d/kde3.csh
%{_datadir}/cups/model/postscript.ppd.gz

%files devel -f devel.list
%{_libdir}/cmake/KDE3Libs

%changelog
* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261121-1
- Snapshot of kde3-revival/kde3-kdelibs commit bff1f44

* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-3
- Snapshot of kde3-revival/kde3-kdelibs commit be0b03a

* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-2
- Snapshot of kde3-revival/kde3-kdelibs commit 5da9f12

* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-1
- Snapshot of kde3-revival/kde3-kdelibs commit 7b25238
