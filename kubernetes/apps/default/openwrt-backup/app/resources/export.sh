#!/bin/sh

OUTPUT_DIR="${1:-$PWD}"

for HOST in $OPENWRT_HOSTS; do
    echo "Backing up $HOST..."
    if ! ssh root@"$HOST" "sysupgrade -b /tmp/backup.tar.gz"; then
        echo "Failed to backup $HOST"
        exit 1
    fi

    echo "Exporting backup from $HOST..."
    if ! scp -O root@"$HOST":/tmp/backup.tar.gz "$OUTPUT_DIR/$HOST.tar.gz"; then
        echo "Failed to export backup from $HOST"
        exit 1
    fi

    echo "Removing backup from $HOST..."
    if ! ssh root@"$HOST" "rm /tmp/backup.tar.gz"; then
        echo "Failed to remove backup from $HOST"
        exit 1
    fi
done
echo "Export complete..."