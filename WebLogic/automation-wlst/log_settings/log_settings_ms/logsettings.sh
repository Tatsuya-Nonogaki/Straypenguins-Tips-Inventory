#!/bin/sh

if [ -z "$1" ]; then
    echo "Usege: $(basename $0) [PROPERTIES_FILE_NAME] [-lh]"
    exit 1
fi

. /etc/profile.d/oracle.sh

. ${WL_HOME}/server/bin/setWLSEnv.sh >/dev/null

export WLST_PROPERTIES="-Dweblogic.security.SSL.ignoreHostnameVerification=true, -Dweblogic.security.TrustKeyStore=DemoTrust"

pushd $(dirname $0) >/dev/null

${ORACLE_HOME}/oracle_common/common/bin/wlst.sh logsettings_ms.py -p ${1+"$@"}
