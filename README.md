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

Results (packages, `build.log`, `namcap.log`/`rpmlint.log`, `test.log`) go
to `out/<distro>/<package>/`.  The build runs rootless as an unprivileged
user inside the container; `JOBS` sets the parallelism (default `nproc`).

## Versions

Packages are snapshots of a fixed upstream commit, versioned
`3.3.8b+git<YYYYMMDD>` (committer date of the commit, UTC).  To move to the
current head of master (or a given commit):

    ./bump.sh kde3-qt [commit]

This updates the commit, date, checksums and pkgrel/Release (back to 1, or
+1 when the new commit has the same date) in both recipes and adds a Fedora
changelog entry; review with `git diff` and commit.

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
