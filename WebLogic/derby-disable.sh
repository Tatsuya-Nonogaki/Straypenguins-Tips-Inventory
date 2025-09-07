#!/bin/sh
if [ -z "$WL_HOME" ]; then
    echo "Error, variable WL_HOME is empty, unable to continue"
    exit 1
fi

if [ -f ${WL_HOME}/common/derby/lib/derby.jar ]; then
    echo "Renaming derby.jar to derby.jar.old"
    mv ${WL_HOME}/common/derby/lib/derby.jar{,.old}
    if [ $? -eq 0 ]; then
        echo "Success"
    else
        echo "Error"
        exit 1
    fi
fi
exit 0
