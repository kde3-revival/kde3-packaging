# kde3-qt: Qt 3.3.8b for kde3-revival, installed in /opt/kde3-qt.
# See kde3-qt.sh for why the bin directory is appended to PATH.
setenv QTDIR /opt/kde3-qt
if ( "${path}" !~ */opt/kde3-qt/bin* ) then
    set path = ( ${path} /opt/kde3-qt/bin )
endif
