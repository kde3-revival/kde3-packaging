# kde3: KDE 3.5 of kde3-revival, installed in /opt/kde3.
# The bin directory is appended, not prepended, so that the programs of the
# distribution with the same names (konsole, kate, konqueror, ... of KDE
# Plasma/Gear) keep their meaning in a normal shell.  KDE 3 finds its
# installation through the prefix compiled into kdelibs; KDEDIRS is not
# needed.
case ":${PATH}:" in
    *:/opt/kde3/bin:*) ;;
    *) PATH="${PATH:+${PATH}:}/opt/kde3/bin"; export PATH ;;
esac
