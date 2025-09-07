#!/bin/sh

if [ -z "$2" -a "$1" != "-h" ]; then
    echo "Usege: $(basename $0) [-s SERVERNAME -v COUNT] [-lh]"
    exit 1
fi

. /etc/profile.d/oracle.sh

. ${WL_HOME}/server/bin/setWLSEnv.sh >/dev/null

export WLST_PROPERTIES="-Dweblogic.security.SSL.ignoreHostnameVerification=true, -Dweblogic.security.TrustKeyStore=DemoTrust"

pushd $(dirname $0) >/dev/null

${ORACLE_HOME}/oracle_common/common/bin/wlst.sh set_maxreqparamcount.py -p $(dirname $0)/connection.properties ${1+"$@"}
