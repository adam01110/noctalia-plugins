#!/bin/sh
# Resync after startup and monitor exits, including NetworkManager restarts.
while :; do
    printf 'resync\n'
    nmcli monitor
    sleep 5
done
