#!/bin/sh -x
releasever=9.4
newkernelver=5.14.0-427.18.1.el9_4
relopt="--releasever=$releasever"
excludeopt="-x redhat-release -x redhat-release-eula"

echo "===== installed packages related with kernel:"
rpm -q kernel{,-core,-modules,-tools,-tools-libs,-devel,-headers} linux-firmware python3-perf redhat-release{,-eula}

[ "x$1" = "x-l" ] && exit

echo

dnf --disableexcludes main $excludeopt $relopt install kernel{,-core,-modules,-tools,-tools-libs,-devel,-headers}-$newkernelver linux-firmware

rpm -q --whatrequires python3-perf
if [ $? -eq 0 ]; then
	dnf --disableexcludes main $relopt update python3-perf
fi
