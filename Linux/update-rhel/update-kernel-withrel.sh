#!/bin/sh -x
newkernelver=5.14.0-427.18.1.el9_4

echo "===== installed packages related with kernel:"
rpm -q kernel{,-core,-modules,-tools,-tools-libs,-devel,-headers} linux-firmware python3-perf redhat-release{,-eula}

[ "x$1" = "x-l" ] && exit

echo

dnf --disableexcludes main $relopt install kernel{,-core,-modules,-tools,-tools-libs}-$newkernelver linux-firmware redhat-release{,-eula}

rpm -q --whatrequires python3-perf
if [ $? -eq 0 ]; then
	dnf --disableexcludes main $relopt update python3-perf
fi
