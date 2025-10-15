#!/bin/sh -x
subscription-manager clean
subscription-manager remove --all
cloud-init clean
truncate -s0 /etc/machine-id
rm -f /etc/cloud/cloud.cfg.d/99-template-maint.cfg /etc/cloud/cloud-init.disabled
# Create /etc/cloud/cloud.cfg.d/99-override.cfg for the clone
cat <<EOM >/etc/cloud/cloud.cfg.d/99-override.cfg
preserve_hostname: false
manage_etc_hosts: false
EOM
