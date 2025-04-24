#!/usr/bin/env bash

printf "Cleaning subtitles for '%s' ...\n" "$1"
python3 /subcleaner/subcleaner/subcleaner.py "$1" -s

case $1 in
    *movies*) section="1";;
    *shows*) section="2";;
esac

if [[ -n "$section" ]]; then
    printf "Refreshing Jellyfin...\n"
    /usr/bin/curl -I -X POST -G \
        -H "Authorization: MediaBrowser Token=${JELLYFIN_TOKEN}" \
        --no-progress-meter \
            "http://jellyfin.media.svc.cluster.local:8096/Library/Refresh"
fi
