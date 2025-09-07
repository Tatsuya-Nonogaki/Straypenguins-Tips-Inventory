#!/bin/sh
# JRE securerandom source optimization for Oracle java 8 or older.
#
JREBASE=$1

if [ "x$JREBASE" = "x" ]; then
    echo "usage: $(basename $0) JREBASEPATH"
    echo "JREBASEPATH may be for example /usr/lib/jvm/java-1.8.0-oracle"
    exit 1
fi

if [ ! -d "$JREBASE" ]; then
    echo "No such directory '$JREBASE'"
    exit 1
fi

JRESEC="$JREBASE/lib/security/java.security"
if [ ! -f "$JRESEC" ]; then
    JRESEC="$JREBASE/jre/lib/security/java.security"
    if [ ! -f "$JRESEC" ]; then
        echo "No java.security file found under JREBASE nor JREBASE/jre"
        exit 1
    fi
fi

echo "Target file is '$JRESEC'"

if grep -qw "^securerandom.source=file:/dev/random" $JRESEC; then
    perl -pi'.bak' -e's!^(securerandom.source=file:/dev/)random!$1./urandom!' $JRESEC
    echo "/dev/random replaced with /dev/./urandom"
    echo "Original file was backed up as java.security.bak"
else
    echo "No /dev/random line found"
fi
