# Forwards find_package(KDE3Libs) to the package in /opt/kde3, so that it is
# found without CMAKE_PREFIX_PATH (or /opt/kde3/bin in PATH).  A symbolic
# link would not do: KDE3LibsConfig.cmake computes the prefix from its own
# location.
include("/opt/kde3/lib/cmake/KDE3Libs/KDE3LibsConfig.cmake")
