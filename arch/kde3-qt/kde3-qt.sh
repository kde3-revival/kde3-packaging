# kde3-qt: Qt 3.3.8b for kde3-revival, installed in /opt/kde3-qt.
# QTDIR is used by qmake (mkspecs, include and lib paths) and by KDE 3.
# The bin directory is appended, not prepended, so that the distribution's
# qmake/moc/uic/designer (Qt 5/6) keep their meaning in a normal shell;
# build scripts for Qt 3 programs must put "$QTDIR/bin" first themselves.
QTDIR=/opt/kde3-qt
export QTDIR
case ":${PATH}:" in
    *:/opt/kde3-qt/bin:*) ;;
    *) PATH="${PATH:+${PATH}:}/opt/kde3-qt/bin"; export PATH ;;
esac
