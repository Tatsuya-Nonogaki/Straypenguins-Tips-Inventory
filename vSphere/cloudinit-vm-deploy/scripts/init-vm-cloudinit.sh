#!/bin/sh -x
subscription-manager clean
subscription-manager remove --all
cloud-init clean
rm -f /etc/ssh/ssh_host_*
truncate -s0 /etc/machine-id
rm -f /etc/cloud/cloud.cfg.d/99-template-maint.conf
echo "preserve_hostname: false" > /etc/cloud/cloud.cfg.d/99-override.conf
