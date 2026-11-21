# WPE WebKit for kde3-revival: the engine of kde3-wpepart, the Konqueror
# web browser part.  Fedora retired its wpewebkit package in 2020 (last
# version 2.26.1, orphaned), so this is built from the upstream release.
#
# Adapted from Fedora's webkitgtk.spec (same WebKit source tree, F44
# branch, 2.54.2): the same toolchain (clang), BuildRequires and build
# flags, reduced to what the WPE port with the WPEPlatform API needs:
#
#   * WPEPlatform (wpe-platform-2.0) with its DRM, headless and Wayland
#     platforms (upstream defaults); kde3-wpepart brings its own X11
#     platform on Qt's X connection.  No libwpe/wpebackend-fdo: the legacy
#     API is off (as in Arch's wpewebkit).
#   * Bubblewrap sandbox on (upstream default).
#   * No documentation, GObject introspection, WebDriver, MiniBrowser or
#     speech synthesis (Flite): kde3-wpepart uses none of them and they
#     cost build time.
#   * No LTO (Fedora builds webkitgtk with ThinLTO): linking the library
#     with LTO needs far more memory and time than our build machines have
#     to spare.  Linked with lld, one link job at a time.
#   * No debuginfo packages by default (WebKit's are several GB to build);
#     "rpmbuild --with debuginfo" builds them.
#
# Fedora's two webkitgtk patches are not needed: one fixes a race in
# Source/WebKit/PlatformGTK.cmake (GTK port only), the other is for s390x.

%bcond_with debuginfo

# Clang is preferred: https://skia.org/docs/user/build/#supported-and-preferred-compilers
%global toolchain clang

%global _lto_cflags %{nil}

%if %{without debuginfo}
%global debug_package %{nil}
%global _enable_debug_packages 0
# the last -g option wins
%global optflags %{optflags} -g0
%else
# from webkitgtk.spec
%global _dwz_max_die_limit_x86_64 250000000
%global _dwz_max_die_limit_aarch64 250000000
%global _find_debuginfo_opts %limit_build -m 32768
%endif

# JIT is broken on ARM systems with new ARMv8.5 BTI extension at the moment
# (from webkitgtk.spec)
%ifarch aarch64
%global optflags %(echo %{optflags} | sed 's/-mbranch-protection=standard /-mbranch-protection=pac-ret /')
%endif

# Filter out provides for private libraries
%global __provides_exclude_from ^%{_libdir}/wpe-webkit-2\\.0/.*\\.so$

%global apiver 2.0

Name:           wpewebkit
Version:        2.54.3
Release:        1%{?dist}
Summary:        WPE WebKit web content engine library

# The license tag and the comment in webkitgtk.spec (same source tree)
# apply unchanged.
License:        LGPL-2.1-only AND BSD-2-Clause AND BSD-3-Clause AND ISC AND bzip2-1.0.6 AND NCSA AND MIT AND GPL-2.0-only AND MPL-1.1 AND SunPro AND Apache-2.0 AND GPL-3.0-or-later WITH Bison-exception-2.2 AND GPL-3.0-or-later WITH Autoconf-exception-3.0 AND MPL-2.0 AND OFL-1.1 AND (AFL-2.0 OR GPL-2.0-or-later) AND BSD-Source-Code AND BSD-2-Clause-Views AND LGPL-2.1-or-later AND (NCSA OR MIT) AND Apache-2.0 WITH LLVM-exception AND ICU AND BSL-1.0
URL:            https://wpewebkit.org/
Source0:        https://wpewebkit.org/releases/wpewebkit-%{version}.tar.xz

BuildRequires:  bison
BuildRequires:  bubblewrap
BuildRequires:  clang
BuildRequires:  cmake
BuildRequires:  flex
BuildRequires:  gettext
BuildRequires:  gperf
BuildRequires:  hyphen-devel
BuildRequires:  libatomic
BuildRequires:  lld
BuildRequires:  ninja-build
BuildRequires:  perl(English)
BuildRequires:  perl(File::Compare)
BuildRequires:  perl(File::Copy)
BuildRequires:  perl(File::Find)
BuildRequires:  perl(FindBin)
BuildRequires:  perl(JSON::PP)
BuildRequires:  perl(bigint)
BuildRequires:  perl(lib)
BuildRequires:  python3
BuildRequires:  ruby
BuildRequires:  rubygems
BuildRequires:  rubygem(getoptlong)
BuildRequires:  rubygem-json
BuildRequires:  unifdef
BuildRequires:  xdg-dbus-proxy

BuildRequires:  pkgconfig(atk)
BuildRequires:  pkgconfig(atk-bridge-2.0)
BuildRequires:  pkgconfig(cairo)
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(enchant-2)
BuildRequires:  pkgconfig(epoxy)
BuildRequires:  pkgconfig(expat)
BuildRequires:  pkgconfig(fontconfig)
BuildRequires:  pkgconfig(freetype2)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(glib-2.0)
BuildRequires:  pkgconfig(gstreamer-1.0)
BuildRequires:  pkgconfig(gstreamer-plugins-bad-1.0)
BuildRequires:  pkgconfig(gstreamer-plugins-base-1.0)
BuildRequires:  pkgconfig(harfbuzz)
BuildRequires:  pkgconfig(icu-uc)
BuildRequires:  pkgconfig(lcms2)
BuildRequires:  pkgconfig(libavif)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(libgcrypt)
BuildRequires:  pkgconfig(libinput)
BuildRequires:  pkgconfig(libjpeg)
BuildRequires:  pkgconfig(libjxl)
BuildRequires:  pkgconfig(libpng)
BuildRequires:  pkgconfig(libseccomp)
BuildRequires:  pkgconfig(libsoup-3.0)
BuildRequires:  pkgconfig(libsystemd)
BuildRequires:  pkgconfig(libtasn1)
BuildRequires:  pkgconfig(libudev)
BuildRequires:  pkgconfig(libwebp)
BuildRequires:  pkgconfig(libwoff2dec)
BuildRequires:  pkgconfig(libxml-2.0)
BuildRequires:  pkgconfig(libxslt)
BuildRequires:  pkgconfig(manette-0.2)
BuildRequires:  pkgconfig(sqlite3)
BuildRequires:  pkgconfig(sysprof-capture-4)
BuildRequires:  pkgconfig(wayland-client)
BuildRequires:  pkgconfig(wayland-cursor)
BuildRequires:  pkgconfig(wayland-egl)
BuildRequires:  pkgconfig(wayland-protocols)
BuildRequires:  pkgconfig(wayland-server)
BuildRequires:  pkgconfig(xkbcommon)
BuildRequires:  pkgconfig(zlib)

Requires:       bubblewrap
Requires:       libGLES
Requires:       xdg-dbus-proxy
Recommends:     geoclue2
Recommends:     gstreamer1-plugins-bad-free
Recommends:     gstreamer1-plugins-good
Provides:       bundled(angle)
Provides:       bundled(pdfjs)
Provides:       bundled(simde)
Provides:       bundled(simdutf)
Provides:       bundled(skia)
Provides:       bundled(xdgmime)

%description
WPE WebKit is a port of the WebKit web content engine for embedded and
other non-GTK uses: it has no toolkit dependency and draws through the
WPEPlatform API, for which the embedding application can provide its own
platform implementation.  This package has the WPE WebKit 2.0 API with
WPEPlatform (DRM, headless and Wayland platforms), built for kde3-wpepart,
the KDE 3 Konqueror web browser part.

%package        devel
Summary:        Development files for WPE WebKit
Requires:       %{name}%{?_isa} = %{version}-%{release}
# Included by the public headers but missing from the pkg-config files:
# wpe-platform.h includes xkbcommon.h, the DRM and Wayland platforms'
# headers gbm.h and wayland-client.h.
Requires:       pkgconfig(xkbcommon)
Requires:       pkgconfig(gbm)
Requires:       pkgconfig(wayland-client)

%description    devel
Headers, libraries and pkg-config files (wpe-webkit-2.0, wpe-platform-2.0
and its platforms, wpe-web-process-extension-2.0) for developing
applications that use WPE WebKit.


%prep
%autosetup -p1 -n wpewebkit-%{version}

%build
# lld: much less memory than ld.bfd for libWPEWebKit; one link at a time.
%cmake \
  -GNinja \
  -DPORT=WPE \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_EXE_LINKER_FLAGS="%{build_ldflags} -fuse-ld=lld" \
  -DCMAKE_SHARED_LINKER_FLAGS="%{build_ldflags} -fuse-ld=lld" \
  -DCMAKE_MODULE_LINKER_FLAGS="%{build_ldflags} -fuse-ld=lld" \
  -DCMAKE_JOB_POOLS="link=1" \
  -DCMAKE_JOB_POOL_LINK=link \
  -DENABLE_WPE_PLATFORM=ON \
  -DENABLE_WPE_LEGACY_API=OFF \
  -DENABLE_BUBBLEWRAP_SANDBOX=ON \
  -DENABLE_DOCUMENTATION=OFF \
  -DENABLE_INTROSPECTION=OFF \
  -DENABLE_WEBDRIVER=OFF \
  -DENABLE_MINIBROWSER=OFF \
  -DENABLE_SPEECH_SYNTHESIS=OFF \
  -DUSE_FLITE=OFF \
  -DUSE_LIBBACKTRACE=OFF \
  %{nil}

export NINJA_STATUS="[%f/%t %es] "
%cmake_build %limit_build -m 3072

%install
%cmake_install

## Lots of files in various subdirectories have the same name (such as
## "LICENSE"): prefix them with their directory names (from webkitgtk.spec).
%global add_to_license_files() \
        mkdir -p _license_files ; \
        cp -p %1 _license_files/$(echo '%1' | sed -e 's!/!.!g')
%add_to_license_files Source/JavaScriptCore/COPYING.LIB
%add_to_license_files Source/ThirdParty/ANGLE/LICENSE
%add_to_license_files Source/ThirdParty/ANGLE/src/third_party/libXNVCtrl/LICENSE
%add_to_license_files Source/WebCore/LICENSE-APPLE
%add_to_license_files Source/WebCore/LICENSE-LGPL-2
%add_to_license_files Source/WebCore/LICENSE-LGPL-2.1
%add_to_license_files Source/WebInspectorUI/UserInterface/External/CodeMirror/LICENSE
%add_to_license_files Source/WebInspectorUI/UserInterface/External/Esprima/LICENSE
%add_to_license_files Source/WebInspectorUI/UserInterface/External/three.js/LICENSE
%add_to_license_files Source/WTF/icu/LICENSE
%add_to_license_files Source/WTF/wtf/dtoa/COPYING
%add_to_license_files Source/WTF/wtf/dtoa/LICENSE


%files
%license _license_files/*
%doc NEWS
%{_libdir}/libWPEWebKit-%{apiver}.so.1*
%{_libdir}/wpe-webkit-%{apiver}/
%{_libexecdir}/wpe-webkit-%{apiver}/
%{_datadir}/wpe-webkit-%{apiver}/

%files devel
%{_includedir}/wpe-webkit-%{apiver}/
%{_libdir}/libWPEWebKit-%{apiver}.so
%{_libdir}/pkgconfig/wpe-webkit-%{apiver}.pc
%{_libdir}/pkgconfig/wpe-web-process-extension-%{apiver}.pc
%{_libdir}/pkgconfig/wpe-platform-%{apiver}.pc
%{_libdir}/pkgconfig/wpe-platform-drm-%{apiver}.pc
%{_libdir}/pkgconfig/wpe-platform-headless-%{apiver}.pc
%{_libdir}/pkgconfig/wpe-platform-wayland-%{apiver}.pc

%changelog
* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 2.54.3-1
- WPE WebKit 2.54.3 for kde3-wpepart, adapted from Fedora's webkitgtk.spec
