#!/bin/sh
# JRE securerandom source optimization for Oracle jdk 11 or later.
#
JREBASE=$1

if [ "x$JREBASE" = "x" ]; then
    echo "usage: $(basename $0) JREBASEPATH"
    echo "JREBASEPATH may be for example /usr/lib/jvm/jdk-11.0.11"
    exit 1
fi

if [ ! -d "$JREBASE" ]; then
    echo "No such directory '$JREBASE'"
    exit 1
fi

JRESEC="$JREBASE/conf/security/java.security"
if [ ! -f "$JRESEC" ]; then
    echo "No java.security file found under JREBASE/conf"
    exit 1
fi

echo "Target file is '$JRESEC'"

if grep -qw "^securerandom.source=file:/dev/random" $JRESEC; then
    perl -pi'.bak' -e's!^(securerandom.source=file:/dev/)random!$1urandom!' $JRESEC
    echo "/dev/random replaced with /dev/urandom"
    echo "Original file was backed up as java.security.bak"
else
    echo "No /dev/random line found"
fi
