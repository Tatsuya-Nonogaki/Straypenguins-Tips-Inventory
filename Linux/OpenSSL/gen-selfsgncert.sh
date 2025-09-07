#!/bin/sh
# Generates a private key and self-signed certificate pair. Set SSLCONF to your tailored SSL conf,
# or comment it out if you want the system's standard openssl.cnf to be used.
# Attached openssl sample.cnf includes CN altName attributes. When the extension is needless, comment
# out those below:
#    copy_extensions = copy   in section [CA_default]
#    subjectAltName = @alt_names   in [v3_ca]
#  You can leave [alt_names] section which is ignored when above are deactivated.

KEYOUT="/etc/pki/tls/private/myserver.key"
CERTOUT="/etc/pki/tls/certs/myserver.crt"
SSLCONF="/path/to/openssl.cnf"

DAYS=3650
KEYLENGTH=2048
#OPTS=

# Defaults
: ${SSLCONF:="/etc/pki/tls/openssl.cnf"}

if [ -e "$KEYOUT" ]; then
    read -p "Private key \"$KEYOUT\" already exists. Overwrite? ([n]/y): " OWKEY
    echo
    : ${OWKEY:=n}

    if [ "$OWKEY" != "y" -a "$OWKEY" != "Y" ]; then
        echo "Operation aborted, nothing done."
        exit
    fi
fi

openssl req -new -days $DAYS -x509 -nodes -newkey rsa:$KEYLENGTH -out $CERTOUT -keyout $KEYOUT -config $SSLCONF $OPTS
