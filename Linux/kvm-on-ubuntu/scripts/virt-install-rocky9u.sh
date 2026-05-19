#!/bin/bash
# Argument (mandatory): VM_Name
# Version: 1.1.1
dir=$(dirname $0)
ME=$(basename $0)
LOGDIR="$dir/log"

###----- Virtual Machine Settings -BEGIN -----
NAME=$1
VARIANT=rocky9
RAM=3072
CPU=2
IMAGE=/work/data/media/linux/Rocky-9.7-x86_64-dvd.iso
DISK0=/dev/mapper/vg_vm-rocky9u
# DISKSIZE0=40G
DISK1=/dev/mapper/vg_vm-rocky9u_swap
DISK2=/dev/mapper/vg_vm-rocky9u_kdump
VNC_ADDR=127.0.0.1
VNC_PORT=5908
###----- Virtual Machine Settings -END -----

if [ -f $dir/qemu-install-common.sh ]; then
    . $dir/qemu-install-common.sh
else
    echo "Required include file '$dir/qemu-install-common.sh' not found, operation aborted"
    exit 1
fi

if [ ! -d $LOGDIR ]; then
    mkdir $LOGDIR
    if [ ! -d $LOGDIR ]; then
        echo "Failed to create log directory '$LOGDIR', operation aborted"
        exit 1
    fi
fi
me_noext=${ME%.*}
LOGFILE="$LOGDIR/${me_noext}.log"

log "$ME started.."

if [ -z "$NAME" ]; then
    log_error "ARG0 (VM_Name) is not passed, operation aborted"
    exit 1
fi

# Generate random MAC addresses within the KVM vendor ID. If multiple vNICs are required, 
# add "mac_gen $NAME 1", "mac_gen $NAME 2" ...
mac_gen $NAME 0

log "Open VNC to $VNC_ADDR:$VNC_PORT to interact with the VM '$NAME'"

CMD="virt-install --connect qemu:///system --arch=x86_64 -n $NAME --memory $RAM --vcpus $CPU \
 --boot uefi \
 --cdrom $IMAGE \
 --disk path=$DISK0,bus=virtio \
 --disk path=$DISK1,bus=virtio \
 --disk path=$DISK2,bus=virtio \
 --os-variant $VARIANT \
 --virt-type kvm \
 --network bridge=br0,model=virtio,mac=$newmac0 \
 --graphics vnc,listen=$VNC_ADDR,port=$VNC_PORT,keymap=ja \
 --noautoconsole"

log "Executing command: $CMD"
eval "$CMD" 2>&1 | tee -a "$LOGFILE"

