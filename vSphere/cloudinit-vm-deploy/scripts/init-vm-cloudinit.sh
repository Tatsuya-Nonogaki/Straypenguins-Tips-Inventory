#!/bin/sh -x
subscription-manager clean
subscription-manager remove --all
cloud-init clean
rm -f /etc/ssh/ssh_host_*
truncate -s0 /etc/machine-id
