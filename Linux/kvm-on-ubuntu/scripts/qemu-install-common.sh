#!/bin/bash

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$ME] $*" | tee -a "$LOGFILE"
}

log_error() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$ME] [ERROR] $*" | tee -a "$LOGFILE"
}

function mac_gen() {
    # Usage: mac_gen VM_NAME [INDEX]
    if [ ! -x $dir/qemumacgen.py ]; then
        log_error "Required tool '$dir/qemumacgen.py' not found or non-executable, operation aborted"
        exit 1
    fi
    newmac=$($dir/qemumacgen.py)

    echo $newmac > /var/tmp/${ME}-${1}-mac${2}.txt
    log "Guest MAC is $newmac. Reminder written to /var/tmp/${ME}-${1}-mac${2}.txt"
    eval "newmac$2=\$newmac"
}

