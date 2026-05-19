#!/bin/sh
nmcli connection modify "Ethernet1" connection.autoconnect no && \
nmcli connection down "Ethernet1" || true
mv /etc/netplan/90-NM-5fb433e3-2b8b-3782-8190-77157417cfcb.yaml{,.disabled}

mv /etc/netplan/01-br0.yaml.disabled /etc/netplan/01-br0.yaml && \
netplan generate
netplan apply
