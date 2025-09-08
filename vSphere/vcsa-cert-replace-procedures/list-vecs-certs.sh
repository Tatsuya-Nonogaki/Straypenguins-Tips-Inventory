#!/bin/sh
# This is exactly equivalent to so-called "one-liner" in the vccert-replace documentation
for store in $(/usr/lib/vmware-vmafd/bin/vecs-cli store list | grep -v TRUSTED_ROOT_CRLS); do
    echo "[*] Store :" $store
    /usr/lib/vmware-vmafd/bin/vecs-cli entry list --store $store --text | grep -ie "Alias" -ie "Not Before" -ie "Not After"
done

