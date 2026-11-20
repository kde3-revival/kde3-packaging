# kde3: KDE 3.5 of kde3-revival, installed in /opt/kde3.
# See kde3.sh for why the bin directory is appended to PATH.
if ( "${path}" !~ */opt/kde3/bin* ) then
    set path = ( ${path} /opt/kde3/bin )
endif
