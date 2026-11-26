# kde3-wpepart: a WPE WebKit browser part for Konqueror (KDE 3.5,
# kde3-revival), installed in /opt/kde3.  Snapshot of a fixed commit; run
# ../../bump.sh kde3-wpepart to move to the latest commit of the master
# branch (updates commit, date, Release, the changelog and the "sources"
# checksum file).
#
# The repository is not public yet: the tarball comes from a local clone
# (CLONE=../kde3-wpepart ../../bump.sh kde3-wpepart puts it in
# out/sources/, where build.sh takes it from).
#
# kde3-qt, kde3-kdelibs and kde3-kdebase (Konqueror) are not in a
# repository, nor is wpewebkit in Fedora: build them first (../../build.sh
# does that with the packages in out/).

# the GitHub repository; its tarballs unpack to kde3-webpart-<commit>
%global repo       kde3-webpart
%global commit     db00b7f41f044ac0e3f7e054bf9e40dce223f808
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261126

%global kde3dir    /opt/kde3

Name:           kde3-wpepart
Version:        0.1.0+git%{date}
Release:        1%{?dist}
Summary:        WPE WebKit browser part for Konqueror (kde3-revival)

License:        LGPL-2.1-or-later
URL:            https://github.com/kde3-revival/%{repo}
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-kdelibs-devel
BuildRequires:  pkgconfig(wpe-webkit-2.0) >= 2.50
BuildRequires:  pkgconfig(wpe-platform-2.0) >= 2.50
BuildRequires:  pkgconfig(x11)
BuildRequires:  pkgconfig(x11-xcb)
BuildRequires:  pkgconfig(xext)
BuildRequires:  pkgconfig(xfixes)
BuildRequires:  pkgconfig(xpresent)
BuildRequires:  pkgconfig(xrandr)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-dri3)
BuildRequires:  pkgconfig(libdrm)
# the HTML sanitizer of the mail mode (KMail's reader) parses with Gumbo
# (kde3-wpepart c6f0c15 and later)
BuildRequires:  pkgconfig(gumbo) >= 0.10

Requires:       kde3-kdelibs%{?_isa}
Requires:       wpewebkit%{?_isa} >= 2.54
# the part is meant for Konqueror (kwpeview shows it in a window of its own)
Recommends:     kde3-kdebase%{?_isa}

%description
A browser part for Konqueror (KDE 3.5 as maintained by kde3-revival) that
shows web pages with WPE WebKit instead of KHTML: rendering on the GPU
(DRI3/Present DMA-BUF) or through shared memory, Konqueror's history,
downloads through KDE's save dialog, context menus, find, zoom,
persistent cookies, HTTP authentication.  It is preferred over KHTML for
text/html and application/xhtml+xml.  kwpeview shows the part in a window
of its own.  Installed in %{kde3dir}.


%prep
%autosetup -n %{repo}-%{commit}

%build
# The prefix, the library directory (/opt/kde3/lib) and the RUNPATH come
# from kdelibs' CMake package.  CMAKE_BUILD_TYPE=None: the distribution
# flags only.
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir}
%cmake_build

%install
# RUNPATHs into /opt/kde3/lib and /opt/kde3-qt/lib (see kde3-kdelibs.spec)
export QA_RPATHS=$((0x0002))
%cmake_install

root=%{buildroot}%{kde3dir}
for f in lib/kde3/libkwpepart.so share/services/kwpepart.desktop \
         share/apps/kwpepart/kwpepart.rc bin/kwpeview bin/kwpe-filterconv; do
    [ -e $root/$f ] || { echo "not built: $f" >&2; exit 1; }
done

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
%license COPYING.LIB
%doc README.md

%changelog
* Thu Nov 26 2026 Serghei Amelian <serghei.amelian@gmail.com> - 0.1.0+git20261126-1
- Snapshot of kde3-revival/kde3-webpart commit db00b7f

* Thu Nov 26 2026 Serghei Amelian <serghei.amelian@gmail.com> - 0.1.0+git20261125-1
- Snapshot of kde3-revival/kde3-webpart commit 0183514

* Wed Nov 25 2026 Serghei Amelian <serghei.amelian@gmail.com> - 0.1.0+git20261124-1
- Snapshot of kde3-revival/kde3-webpart commit d67f840
- Repository renamed kde3-webpart; the app mode's XML GUI file kwpeapppart.rc

* Mon Nov 23 2026 Serghei Amelian <serghei.amelian@gmail.com> - 0.1.0+git20261123-1
- Snapshot of kde3-revival/kde3-wpepart commit cb71e12
- BuildRequires gumbo-parser (the mail mode's HTML sanitizer); kwpe-filterconv
  (content filter lists) checked; tests/render-only is not built

* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 0.1.0+git20261121-1
- Snapshot of kde3-revival/kde3-wpepart commit 4eafdb5
