# kde3-packaging

Distribution packages for the kde3-revival projects.

    arch/<package>/PKGBUILD          Arch Linux (split packages)
    fedora/<package>/<package>.spec  Fedora (sub-packages)
    fedora/<package>/sources         SHA-256 of the source tarball
    tests/<package>.sh               smoke test run on the installed packages
    build.sh                         build/test in clean podman containers
    bump.sh                          move a package to a newer upstream commit

## Building

    ./build.sh arch kde3-qt           # archlinux:latest, makepkg + namcap
    ./build.sh fedora kde3-qt         # fedora:latest, rpmbuild + rpmlint
    ./build.sh test arch kde3-qt      # install out/arch/kde3-qt/* in a fresh
    ./build.sh test fedora kde3-qt    # container and run tests/kde3-qt.sh

The packages are built in dependency order: kde3-qt, kde3-kdelibs,
kde3-kdebase, kde3-kdepim, kde3-kdegraphics.  A package's kde3-revival dependencies are not taken from a
repository but installed into the container from `out/<distro>/`, so
build those first:

    for p in kde3-qt kde3-kdelibs kde3-kdebase kde3-kdepim kde3-kdegraphics; do
        ./build.sh arch $p && ./build.sh test arch $p
    done

Results (packages, `build.log`, `namcap.log`/`rpmlint.log`, `test.log`) go
to `out/<distro>/<package>/`.  The build runs rootless as an unprivileged
user inside the container; `JOBS` sets the parallelism (default `nproc`).

## Versions

Packages are snapshots of a fixed upstream commit, versioned
`<version>+git<YYYYMMDD>` (3.3.8b for kde3-qt, 3.5.10 for kdelibs,
kdebase, kdepim and kdegraphics; committer date of the commit, UTC).  To move to the current head
of master (or a given commit):

    ./bump.sh <package> [commit]

This updates the commit, date, checksums and pkgrel/Release (back to 1, or
+1 when the new commit has the same date) in both recipes and adds a Fedora
changelog entry; review with `git diff` and commit.

A repository that cannot be downloaded (kde3-kdepim and kde3-kdegraphics
are private for now) is taken from a local clone:

    CLONE=../kde3-kdepim ./bump.sh kde3-kdepim

The tarball is made with `git archive` and `gzip -n`, which gives the
same file (and checksum) as GitHub's `/archive/<commit>.tar.gz`; a copy
goes to `out/sources/`, which build.sh uses instead of downloading.

## kde3-qt

Installed in `/opt/kde3-qt` (the configure default kde3-revival uses), so
it does not conflict with any distribution package.  Besides that tree the
packages own only:

* `/etc/profile.d/kde3-qt.{sh,csh}`: `QTDIR=/opt/kde3-qt`, and
  `/opt/kde3-qt/bin` *appended* to `PATH` (so `qmake`, `designer` etc. of
  the distribution's Qt 5/6 are not shadowed in normal shells; Qt 3 build
  scripts put `$QTDIR/bin` first themselves).
* `/usr/lib/pkgconfig/kde3-qt.pc` (Fedora: `/usr/lib64/pkgconfig`), a
  symlink to `/opt/kde3-qt/lib/pkgconfig/kde3-qt.pc`, so that
  `pkg-config kde3-qt` works without `PKG_CONFIG_PATH`, also in clean build
  chroots that do not read `/etc/profile.d`.

No `ld.so.conf.d` entry: all Qt binaries and plugins find their libraries
through an `$ORIGIN`-relative RUNPATH.  Programs built against kde3-qt need
a RUNPATH of their own: qmake adds `-Wl,-rpath,$(QTDIR)/lib`; with
pkg-config add `-Wl,-rpath,$(pkg-config --variable=libdir kde3-qt)`.

| Arch               | Fedora             | contents |
|--------------------|--------------------|----------|
| kde3-qt            | kde3-qt            | libkde3-qt, libkde3-qui, image format plugins, Qt translations, qtconfig, profile.d |
|                    | kde3-qt-devel      | headers, qmake + mkspecs, moc, uic, lupdate, lrelease, qm2ts, .prl, kde3-qt.pc, static libqassistantclient/libdesignercore/libeditor, man1 |
| kde3-qt-designer   | kde3-qt-designer   | designer (+ plugins, templates), assistant, linguist (+ phrasebooks) |
| kde3-qt-doc        | kde3-qt-doc        | HTML documentation, class man pages (man3) |

On Arch the development files stay in the main package, as usual there.

## kde3-kdelibs, kde3-kdebase, kde3-kdepim, kde3-kdegraphics

Installed in `/opt/kde3` (the default prefix of kdelibs' CMake build), with
the libraries in `/opt/kde3/lib` also on 64-bit Fedora: /opt trees are not
multilib, kde3-qt uses `lib` as well, and KStandardDirs looks for libraries
and modules in `lib${KDELIBSUFF}` of every KDE prefix, so the suffix is
fixed by kdelibs (KDELIBSUFF empty) and inherited by kdebase and every
other module through the KDE3Libs CMake package.  The system configuration
directory stays `/opt/kde3/etc` (kderc, xdg/menus), so KDE 3 menus do not
mix with the ones of KDE Plasma in `/etc/xdg`.

No `ld.so.conf.d` entry: every binary has the RUNPATH
`$ORIGIN/<rel>/lib:/opt/kde3/lib:/opt/kde3-qt/lib` (the absolute entries
for setuid programs, where ld.so ignores `$ORIGIN`, and for kde3-qt).

Files outside `/opt/kde3`:

* kde3-kdelibs: `/etc/profile.d/kde3.{sh,csh}` (`/opt/kde3/bin`
  *appended* to `PATH`, like kde3-qt: konsole, kate, konqueror etc. of
  KDE Plasma/Gear keep their meaning in a normal shell; KDEDIRS is not
  needed), `/usr/lib/cmake/KDE3Libs/` (Fedora: `/usr/lib64/cmake`; two
  files that include the real package in `/opt/kde3/lib/cmake/KDE3Libs`,
  so that `find_package(KDE3Libs 3.5)` works without
  `CMAKE_PREFIX_PATH`; a symbolic link would not do, the package
  computes its prefix from its location), and kdeprint's
  `/usr/share/cups/model/postscript.ppd.gz`.
* kde3-kdebase: the PAM services `/etc/pam.d/kde3` (kdm, kcheckpass) and
  `kde3-np` (kdm logins without password) -- kdebase's default service
  name "kde" belongs to KDE Plasma (kscreenlocker); the install hooks only
  create services with mkpamserv when installing without DESTDIR;
  `/usr/share/xsessions/kde3.desktop` ("KDE 3.5" in the session list of
  display managers) and the systemd unit `kde3-kdm.service` (not enabled;
  not "kdm.service", which Fedora's kdm-settings has), and the link
  `/etc/fonts/conf.d/60-kde3-konsole-fonts.conf` to the fontconfig file
  kdebase installs in `/opt/kde3/share/fontconfig/conf.avail`, so that
  fontconfig (and so Konsole through Xft) finds Konsole's console fonts
  ("Misc Console", "Misc Fixed" 9x15).

Setuid/setgid programs (set by the recipes, as the install hooks only
work as root): kgrantpty, start_kdeinit, kpac_dhcp_helper (setuid root,
kdelibs), kcheckpass (setuid root) and kdesud (setgid nobody, kdebase).
fileshareset is a Perl script and stays 0755 (Linux ignores the setuid
bit of scripts).

| Arch               | Fedora              | contents |
|--------------------|---------------------|----------|
| kde3-kdelibs       | kde3-kdelibs        | libraries, kdeinit, dcopserver, kded, klauncher, ioslaves, meinproc, kde-config, data |
|                    | kde3-kdelibs-devel  | headers, CMake package KDE3Libs, .so links, dcopidl, dcopidl2cpp, dcopidlng, kconfig_compiler, makekdewidgets |
| kde3-kdebase       | kde3-kdebase        | the desktop: kwin, kicker, kdesktop, ksmserver, konqueror, konsole, kate, kcontrol, ... |
|                    | kde3-kdebase-devel  | headers and .so links of libkonq, libkickermain, libtaskmanager, libkdecorations, ... |
|                    | kde3-kdm            | kdm, its configuration and themes, kcm_kdm, PAM service kde3-np, kde3-kdm.service |
| kde3-kdepim        | kde3-kdepim         | KMail, KOrganizer, KAddressBook, Kontact, Kleopatra, KWatchGnuPG, KMailCvt, imap4/sieve/mbox ioslaves, libraries |
|                    | kde3-kdepim-devel   | headers and .so links of libkcal, libkmime, mimelib, libkdepim, gpgme++, Kleo, ... |
| kde3-kdegraphics   | kde3-kdegraphics    | KView (+ viewer part and plugins), KSnapshot, KRuler, their handbooks |

On Fedora kdm is a sub-package of its own, so that installing the desktop
for a session started from GDM/SDDM does not install a second display
manager.  libpcre (PCRE 1) is not in Fedora any more: kjs is built there
without it and uses the POSIX regular expressions of glibc.

kde3-kdepim requires kde3-kdebase: KMail sends and fetches mail through
its pop3 and smtp ioslaves, and KAddressBook's LDAP search uses kio_ldap
(imap4, sieve and mbox are kdepim's own).  gnupg (gpg, gpgsm,
gpg-agent) is a dependency as well: the crypto backends run it through
gpgme and, for KMail's classic OpenPGP support, directly.  kdepim is
built with cyrus-sasl (required: sieve, imap4 authentication), without
gnokii (mobile phones in KAddressBook; its service file is removed, as
the filter is not built), without the experimental full-text index
of KMail (indexlib) and with logind support (GIO: KMail disconnects
before the machine sleeps).

kde3-kdegraphics is only KView, KSnapshot and KRuler; it needs no more
than kdelibs.  The image formats KView reads and KSnapshot writes are
those of kde3-qt and of kdelibs' kimgio plugins.  The Print key starts
KSnapshot through khotkeys of kde3-kdebase (an optional dependency /
Recommends).  The unversioned link of libkimageviewer (used only by
KView's parts, no headers) is not packaged, so there is no -devel
package.

kde3-qt runs its event loop on GLib's main context (QT_GLIB_EVENTLOOP,
the configure default), which the GIO/GDBus code of kdebase (sleep and
hibernate in the logout dialog, through systemd-logind) and kdepim
needs.  kdebase's volume applet of kicker uses libpulse (PulseAudio, or
PipeWire's PulseAudio server).
