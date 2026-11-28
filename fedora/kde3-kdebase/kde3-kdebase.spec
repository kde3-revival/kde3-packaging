# kdebase 3.5.10 as maintained by kde3-revival, installed in /opt/kde3.
# Snapshot of a fixed commit; run ../../bump.sh kde3-kdebase to move to the
# latest commit of the master branch (updates commit, date, Release, the
# changelog and the "sources" checksum file).
#
# kde3-qt and kde3-kdelibs are not in a repository: build them first
# (../../build.sh does that with the packages in out/).

# the GitHub repository; its tarballs unpack to kde3-base-<commit>
%global repo       kde3-base
%global commit     cad5e683913b673ae72f74e5bd1ef700ff03200c
%global shortcommit %(c=%{commit}; echo ${c:0:7})
%global date       20261128

%global kde3dir    /opt/kde3

Name:           kde3-kdebase
Version:        3.5.10+git%{date}
Release:        4%{?dist}
Summary:        KDE 3.5 desktop maintained for kde3-revival

License:        GPL-2.0-or-later AND LGPL-2.0-or-later AND GFDL-1.2-or-later
URL:            https://github.com/kde3-revival/%{repo}
Source0:        %{url}/archive/%{commit}.tar.gz#/%{name}-%{commit}.tar.gz
Source1:        kde3.pam
Source2:        kde3-np.pam
Source3:        kde3.desktop
Source4:        kde3-kdm.service

BuildRequires:  cmake
BuildRequires:  ninja-build
BuildRequires:  gcc-c++
BuildRequires:  kde3-kdelibs-devel
BuildRequires:  perl-interpreter
BuildRequires:  bdftopcf
BuildRequires:  mkfontscale
BuildRequires:  systemd-rpm-macros
BuildRequires:  avahi-compat-libdns_sd-devel
BuildRequires:  bzip2-devel
BuildRequires:  cyrus-sasl-devel
BuildRequires:  fontconfig-devel
BuildRequires:  freetype-devel
BuildRequires:  glib2-devel
BuildRequires:  libsmbclient-devel
BuildRequires:  libusb-compat-0.1-devel
BuildRequires:  libX11-devel
BuildRequires:  libXau-devel
BuildRequires:  libXcomposite-devel
BuildRequires:  libxcrypt-devel
BuildRequires:  libXcursor-devel
BuildRequires:  libXdamage-devel
BuildRequires:  libXdmcp-devel
BuildRequires:  libXext-devel
BuildRequires:  libXfixes-devel
BuildRequires:  libXft-devel
BuildRequires:  libXinerama-devel
BuildRequires:  libxkbfile-devel
BuildRequires:  libXrandr-devel
BuildRequires:  libXrender-devel
BuildRequires:  libXScrnSaver-devel
BuildRequires:  libXtst-devel
BuildRequires:  lm_sensors-devel
BuildRequires:  mesa-libGL-devel
BuildRequires:  mesa-libGLU-devel
BuildRequires:  NetworkManager-libnm-devel
BuildRequires:  openexr-devel
BuildRequires:  openldap-devel
BuildRequires:  openssl-devel
BuildRequires:  pam-devel
BuildRequires:  pulseaudio-libs-devel
BuildRequires:  upower-devel
# The KWin compositor (kdebase 53f9ecd and later; kompmgr is gone): the
# GLES 3 backend draws with EGL on GBM and shares its buffers with the X
# server as DMA-BUFs through DRI3 (KWIN_HAVE_GLES, else XRender only);
# Xpresent for tear-free frames; XInput 2.3 and RandR 1.5 for the
# overview's Super key and hot corner barrier, and the touchpad settings
# (kded_touchpad, the Touchpad tab of kcm_input; kdebase 33ef100).
BuildRequires:  pkgconfig(egl)
BuildRequires:  pkgconfig(glesv2)
BuildRequires:  pkgconfig(gbm)
BuildRequires:  pkgconfig(libdrm)
BuildRequires:  pkgconfig(xcb)
BuildRequires:  pkgconfig(xcb-dri3)
BuildRequires:  pkgconfig(xcb-sync)
BuildRequires:  pkgconfig(x11-xcb)
BuildRequires:  pkgconfig(xshmfence)
BuildRequires:  pkgconfig(xpresent)
BuildRequires:  pkgconfig(xi)

Requires:       kde3-kdelibs%{?_isa}
# The media manager lists, mounts and ejects the storage devices through
# UDisks2; the power applet of kicker asks UPower.
Requires:       udisks2
Requires:       upower
# The network applet of kicker talks to NetworkManager (libnm) and opens
# its settings editor for what it does not set up itself (802.1X, WEP).
Recommends:     NetworkManager
Recommends:     nm-connection-editor
# The session is XDG_CURRENT_DESKTOP=KDE3:GNOME: kde3-portals.conf makes
# xdg-desktop-portal use the GTK backend (file chooser, settings, ...) and
# the GNOME keyring (secret portal), which Chromium and the Electron
# applications also keep their passwords in (libsecret).
Recommends:     xdg-desktop-portal-gtk
Recommends:     gnome-keyring
# startkde gives the session a dconf (GSettings) database of its own, which
# kded_xsettings fills with KDE's fonts and colours for GTK and libadwaita.
Recommends:     dconf
# Run by startkde (xrdb) and kcontrol (xrdb, setxkbmap).  mkfontdir only
# makes fonts.dir files for core X fonts installed with kfontinst.
Recommends:     mkfontscale
Requires:       setxkbmap
Requires:       xrdb
Suggests:       kde3-kdm
# KWin's screenshot shortcuts (Print, Shift+Print, Alt+Print) run KSnapshot.
Suggests:       kde3-ksnapshot
# DrKonqi runs gdb for the backtrace of a crashed program.
Suggests:       gdb

%description
kdebase 3.5.10 as maintained by the kde3-revival project: the KDE 3.5
desktop with the window manager kwin, the panel kicker, kdesktop,
ksmserver, the file manager and web browser konqueror, konsole, kate,
the control center kcontrol, khelpcenter, kdesu and the ioslaves of the
desktop.  It is installed in %{kde3dir} and does not conflict with KDE
Plasma.  Display managers list the session as "KDE 3.5".

%package devel
Summary:        Development files for kde3-kdebase
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       kde3-kdelibs-devel%{?_isa}

%description devel
Headers and the unversioned links of the shared libraries of kdebase
(libkonq, the kicker and taskbar libraries, kwin decorations, kate
interfaces, ksysguard, ksplash themes, the DCOP interfaces of kdesktop,
kwin and konqueror) for building plugins and add-ons such as
kdeaddons.

%package -n kde3-kdm
Summary:        KDE 3.5 display manager (kdm) for kde3-revival
Requires:       %{name}%{?_isa} = %{version}-%{release}
Requires:       xorg-x11-xauth
# kdm's Xsession shows its errors with xmessage.
Requires:       xmessage
Recommends:     xorg-x11-server-Xorg

%description -n kde3-kdm
kdm, the display manager of KDE 3.5, with its themes and its control
center module.  It is installed as the systemd service kde3-kdm, which
is not enabled: "systemctl enable kde3-kdm" makes it the display
manager.  It uses the PAM services kde3 and kde3-np.


%prep
%autosetup -p1 -n %{repo}-%{commit}

%build
# The prefix, the library directory (/opt/kde3/lib) and the RUNPATH come
# from kdelibs' CMake package (CMAKE_INSTALL_PREFIX given to %%cmake is
# overridden here, the LIB_SUFFIX of %%cmake is not used).
# CMAKE_BUILD_TYPE=None: the distribution flags only.  PAM service "kde3"
# (and "kde3-np" for logins without password) instead of the default
# "kde", which is KDE Plasma's.  GENKDMCONF_FLAGS stays empty: genkdmconf
# gets --no-old in a DESTDIR installation, so that the kdm configuration
# does not take over the build machine's.
%cmake \
    -DCMAKE_BUILD_TYPE=None \
    -DCMAKE_INSTALL_PREFIX=%{kde3dir} \
    -DKDE3_PAM=kde3 \
    -DKDE3_WITH_SENSORS=ON \
    -DKDE3_WITH_SAMBA=ON \
    -DKDE3_WITH_OPENEXR=ON \
    -DKDE3_WITH_LIBUSB=ON \
    -DKDEBASE_KONSOLE_FONTS=ON \
    -DKDEBASE_VOLUME_APPLET=ON \
    -DKDEBASE_LOGIND_SLEEP=ON \
    -DKDEBASE_UDISKS2=ON \
    -DKDEBASE_POWER_APPLET=ON \
    -DKDEBASE_NETWORK_APPLET=ON \
    -DKDEBASE_SYSTRAY_SNI=ON \
    -DKDEBASE_SETTINGS_PORTAL=ON
# Fail instead of silently building without an optional feature.
for have in HAVE_PAM HAVE_SSL HAVE_XCOMPOSITE HAVE_XINERAMA HAVE_DPMS \
            HAVE_LIBSASL2 HAVE_XSCREENSAVER HAVE_DNSSD HAVE_SENSORS_SENSORS_H \
            HAVE_LIBUSB HAVE_XKB HAVE_XFT HAVE_XRENDER HAVE_XCURSOR HAVE_XTEST \
            HAVE_XFIXES HAVE_LOGIND_SLEEP COMPILE_UDISKS2BACKEND \
            HAVE_XDAMAGE HAVE_XPRESENT KWIN_PANORAMIX_CHECK KWIN_OVERVIEW_XI2 \
            KWIN_HAVE_GLES HAVE_STATUSNOTIFIER; do
    grep -q "^#define $have 1" %{__cmake_builddir}/config.h || { echo "configure: $have not set" >&2; exit 1; }
done
grep -q '^#define KDM_PAM_SERVICE "kde3"' %{__cmake_builddir}/config.h || { echo "configure: PAM service" >&2; exit 1; }
%cmake_build

%install
# The RUNPATHs have, besides $ORIGIN, the absolute /opt/kde3/lib (for
# setuid programs, where ld.so ignores $ORIGIN) and /opt/kde3-qt/lib, which
# check-rpaths calls "invalid" (anything outside /usr/lib*).
export QA_RPATHS=$((0x0002))
%cmake_install

root=%{buildroot}%{kde3dir}

# Parts that are only built when their dependencies are found.
for f in bin/kdm bin/kxkb bin/kfontinst bin/ksysguardd \
         lib/kde3/kio_smb.so lib/kde3/kio_ldap.so lib/kde3/exrthumbnail.so \
         lib/kde3/volume_panelapplet.so share/apps/kicker/applets/volumeapplet.desktop \
         lib/kde3/kpowermanager_panelapplet.so share/apps/kicker/applets/kpowermanager.desktop \
         lib/kde3/network_panelapplet.so share/apps/kicker/applets/networkapplet.desktop \
         bin/xdg-desktop-portal-kde3 share/xdg-desktop-portal/portals/kde3.portal \
         lib/kde3/kded_touchpad.so share/services/kded/touchpad.desktop \
         share/dbus-1/services/org.freedesktop.impl.portal.desktop.kde3.service \
         share/apps/konsole/fonts/fonts.dir \
         share/fontconfig/conf.avail/60-kde3-konsole-fonts.conf; do
    [ -e $root/$f ] || { echo "not built: $f" >&2; exit 1; }
done

# PAM services (the install hooks run mkpamserv only without DESTDIR).
install -D -p -m644 %{SOURCE1} %{buildroot}%{_sysconfdir}/pam.d/kde3
install -D -p -m644 %{SOURCE2} %{buildroot}%{_sysconfdir}/pam.d/kde3-np

# Konsole's console fonts ("Linux", "Unicode") for fontconfig and so Xft:
# fontconfig does not search the KDE data directory.
install -d %{buildroot}%{_sysconfdir}/fonts/conf.d
ln -s ../../..%{kde3dir}/share/fontconfig/conf.avail/60-kde3-konsole-fonts.conf \
    %{buildroot}%{_sysconfdir}/fonts/conf.d/60-kde3-konsole-fonts.conf

# "KDE 3.5" in the session list of display managers; kdm as a systemd
# service.  The session file's DesktopNames=KDE3;GNOME; becomes
# XDG_CURRENT_DESKTOP=KDE3:GNOME.
install -D -p -m644 %{SOURCE3} %{buildroot}%{_datadir}/xsessions/kde3.desktop
install -D -p -m644 %{SOURCE4} %{buildroot}%{_unitdir}/kde3-kdm.service

# xdg-desktop-portal's backends for that desktop (kde3 and gtk for the
# settings, gtk for the rest, gnome-keyring for secrets, none for what
# needs GNOME Shell) instead of the gnome-portals.conf of the fallback
# desktop, and KDE 3's own Settings backend xdg-desktop-portal-kde3 (its
# kde3.portal and the session bus' service file): xdg-desktop-portal and
# dbus-daemon do not search /opt/kde3.  Copies of what kdebase installs
# in /opt/kde3/share.
install -D -p -m644 $root/share/xdg-desktop-portal/kde3-portals.conf \
    %{buildroot}%{_datadir}/xdg-desktop-portal/kde3-portals.conf
install -D -p -m644 $root/share/xdg-desktop-portal/portals/kde3.portal \
    %{buildroot}%{_datadir}/xdg-desktop-portal/portals/kde3.portal
install -D -p -m644 $root/share/dbus-1/services/org.freedesktop.impl.portal.desktop.kde3.service \
    %{buildroot}%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.kde3.service

# The file lists of the tree in /opt/kde3: kdm and its control center
# module go into kde3-kdm, the headers and the unversioned links of the
# shared libraries into -devel, everything else into the main package.
# Directories that kde3-kdelibs has (installed for the build) are left to
# it.  kcheckpass (password checks of kdesktop_lock) is setuid root and
# kdesud (password cache of kdesu) setgid nobody: the install hooks only
# set the modes when installing as root.
(
    cd %{buildroot}
    find .%{kde3dir} -type d | sed 's|^\.||' | while read -r d; do
        [ -d "$d" ] || echo "%%dir \"$d\""
    done
    find .%{kde3dir} ! -type d | sed 's|^\.\(.*\)$|"\1"|'
) | awk -v k=%{kde3dir} -v kdm=kdm.list -v devel=devel.list -v main=main.list \
        -v solinks="$(cd %{buildroot} && find .%{kde3dir}/lib -maxdepth 1 -name 'lib*.so' -type l | sed 's|^\.||' | tr '\n' ' ')" '
    BEGIN {
        n = split("bin/kdm bin/kdm_config bin/kdm_greet bin/krootimage bin/genkdmconf " \
                  "bin/kdmctl lib/kde3/kcm_kdm.so share/apps/kdm share/config/kdm " \
                  "share/doc/kdm share/applications/kde/kdm.desktop " \
                  "share/doc/HTML/en/kdm share/doc/HTML/en/kcontrol/kdm", p, " ")
        m = split(solinks, s, " "); for (i = 1; i <= m; i++) so[s[i]] = 1
    }
    {
        path = $0; sub(/^%%dir /, "", path); gsub(/"/, "", path)
        out = main
        for (i = 1; i <= n; i++)
            if (path == k "/" p[i] || index(path, k "/" p[i] "/") == 1) { out = kdm; break }
        if (index(path, k "/include/") == 1 || path in so) out = devel
        line = $0
        if (path == k "/bin/kcheckpass") { line = "%%attr(4755,root,root) " line; suid++ }
        if (path == k "/bin/kdesud") { line = "%%attr(2755,root,nobody) " line; suid++ }
        if (out == kdm && index(path, k "/share/config/kdm/") == 1 && $0 !~ /^%%dir/ && path !~ /README$/)
            line = "%%config(noreplace) " line
        print line >out
    }
    END { if (suid != 2) { print "kcheckpass or kdesud missing" >"/dev/stderr"; exit 1 } }'
sort -o main.list main.list
sort -o kdm.list kdm.list
sort -o devel.list devel.list


%post -n kde3-kdm
%systemd_post kde3-kdm.service

%preun -n kde3-kdm
%systemd_preun kde3-kdm.service

%postun -n kde3-kdm
%systemd_postun kde3-kdm.service


%files -f main.list
%license COPYING COPYING-DOCS
%doc README.md AUTHORS README.pam
%config(noreplace) %{_sysconfdir}/pam.d/kde3
%config(noreplace) %{_sysconfdir}/fonts/conf.d/60-kde3-konsole-fonts.conf
%{_datadir}/xsessions/kde3.desktop
%dir %{_datadir}/xdg-desktop-portal
%dir %{_datadir}/xdg-desktop-portal/portals
%{_datadir}/xdg-desktop-portal/kde3-portals.conf
%{_datadir}/xdg-desktop-portal/portals/kde3.portal
%{_datadir}/dbus-1/services/org.freedesktop.impl.portal.desktop.kde3.service

%files devel -f devel.list

%files -n kde3-kdm -f kdm.list
%config(noreplace) %{_sysconfdir}/pam.d/kde3-np
%{_unitdir}/kde3-kdm.service

%changelog
* Sat Nov 28 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261128-4
- Snapshot of kde3-revival/kde3-base commit cad5e68: startkde keeps the settings
  in ~/.kde3 (or in an older ~/.kde as long as there is no ~/.kde3)

* Sat Nov 28 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261128-3
- Snapshot of kde3-revival/kde3-base commit 3af59d9: kdm logins work again
  (no setlogin() of glibc's stub), kdm lists the users of UID_MIN..UID_MAX
  of /etc/login.defs, antialiased greeter fonts by default, tap-to-click and
  the other touchpad settings also in the greeter

* Sat Nov 28 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261128-2
- Snapshot of kde3-revival/kde3-base commit b872db2

* Sat Nov 28 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261128-1
- Snapshot of kde3-revival/kde3-base commit aae9801

* Wed Nov 25 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261124-1
- Snapshot of kde3-revival/kde3-base commit 33b54f7
- Repository renamed kde3-base; README is README.md

* Mon Nov 23 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261123-2
- Snapshot of kde3-revival/kde3-kdebase commit 33ef100
- touchpad settings (kded_touchpad, XInput 2) checked

* Mon Nov 23 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261123-1
- Snapshot of kde3-revival/kde3-kdebase commit 5c2b1ea
- KWin composites itself: BuildRequires EGL, GLESv2, GBM, libdrm, xcb
  (dri3, sync), x11-xcb, xshmfence, Xpresent and XInput 2; kompmgr is gone
- xdg-desktop-portal-kde3 (Settings portal backend): kde3.portal and its
  D-Bus service in /usr/share; kde3-portals.conf taken from kdebase
- the network applet, the StatusNotifierItem tray icons and the settings
  portal enabled and checked explicitly; Recommends dconf
- drop the OpenEXR header patch (upstream e9c1b2b)

* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261121-2
- Snapshot of kde3-revival/kde3-kdebase commit 16a5a87

* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261121-1
- Snapshot of kde3-revival/kde3-kdebase commit 369a706

* Sat Nov 21 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-3
- Snapshot of kde3-revival/kde3-kdebase commit f85b546

* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-2
- Snapshot of kde3-revival/kde3-kdebase commit 4e8abea

* Fri Nov 20 2026 Serghei Amelian <serghei.amelian@gmail.com> - 3.5.10+git20261120-1
- Snapshot of kde3-revival/kde3-kdebase commit 332d849
