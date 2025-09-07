#!/bin/bash
KEYFILE=$1
CRTFILE=$2

if [ -z "$KEYFILE" -o -z "$CRTFILE" ]; then
    echo "Usage: $(basename $0) KEYFILE CRTFILE"
    exit 1
fi

if [ ! -r "$KEYFILE" -o ! -r "$CRTFILE" ]; then
    echo "Keyfile or certfile does not exist or unreadable!"
    exit 1
fi

HASH_KEY=$(openssl rsa -modulus -noout -in "$KEYFILE" |openssl md5 |cut -d' ' -f 2)

HASH_CRT=$(openssl x509 -modulus -noout -in "$CRTFILE" |openssl md5 |cut -d' ' -f 2)

diff <(echo $HASH_KEY) <(echo $HASH_CRT)
if [ $? -eq 0 ]; then
    echo "$KEYFILE and $CRTFILE are a correct pair"
else
    echo "$KEYFILE and $CRTFILE are NOT a pair"
fi
