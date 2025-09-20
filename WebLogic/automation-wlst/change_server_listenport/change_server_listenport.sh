#!/bin/sh
## Changes non-ssl listen port of a Server
## [Caution] Stop all Managed and Admin Servers before run.

if [ -z "$2" -a "$1" != "-h" ]; then
    echo "Usage: $(basename $0) [-s SERVERNAME --port LISTENPORT] [-lh]"
    echo "*Domain Home is retrieved from env DOMAIN_HOME"
    exit 1
fi

. /etc/profile.d/oracle.sh

if [ -z "$DOMAIN_HOME" ]; then
    echo "Usage: $(basename $0) [-s SERVERNAME --port LISTENPORT] [-lh]"
    echo "*Domain Home is retrieved from env DOMAIN_HOME"
    exit 1
fi

. ${WL_HOME}/server/bin/setWLSEnv.sh >/dev/null

export WLST_PROPERTIES="-Dweblogic.security.SSL.ignoreHostnameVerification=true, -Dweblogic.security.TrustKeyStore=DemoTrust"

pushd $(dirname $0) >/dev/null

${ORACLE_HOME}/oracle_common/common/bin/wlst.sh change_server_listenport.py --domain $DOMAIN_HOME ${1+"$@"}
