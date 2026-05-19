#!/bin/sh
mv /etc/netplan/01-br0.yaml /etc/netplan/01-br0.yaml.disabled && \
netplan generate
netplan apply

sudo mv /etc/netplan/90-NM-5fb433e3-2b8b-3782-8190-77157417cfcb.yaml{.disabled,} && \
nmcli connection modify "Ethernet1" connection.autoconnect yes && \
nmcli connection up "Ethernet1"
