#! /bin/sh

OUTPUT_DIR="${1:-$PWD}"

for HOST in $OPENWRT_HOSTS; do
    echo "Backing up $HOST..."
    ssh root@$HOST "sysupgrade -b /tmp/backup.tar.gz"
    if [ $? -ne 0 ]; then
        echo "Failed to backup $HOST"
        exit 1
    fi

    echo "Exporting backup from $HOST..."
    scp -O root@$HOST:/tmp/backup.tar.gz $OUTPUT_DIR/$HOST.tar.gz
    if [ $? -ne 0 ]; then
        echo "Failed to export backup from $HOST"
        exit 1
    fi

    echo "Removing backup from $HOST..."
    ssh root@$HOST "rm /tmp/backup.tar.gz"
    if [ $? -ne 0 ]; then
        echo "Failed to remove backup from $HOST"
        exit 1
    fi
done
echo "Export complete..."
