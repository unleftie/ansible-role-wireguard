#!/bin/bash
# Wireguard interface doesn`t start automatically after a system reboot

while getopts i: option; do
    case "${option}" in
    i) INTERFACE=${OPTARG} ;;
    esac
done

if [ -z "$INTERFACE" ]; then
    echo "Not enough arguments [-i INTERFACE]"
    exit 1
fi

if [ ! -f "/etc/wireguard/$INTERFACE.conf" ]; then
    echo "Wireguard interface config does not exist"
    exit 1
fi

wg-quick down $INTERFACE || true

while ! wg show $INTERFACE >/dev/null 2>&1; do
    wg-quick up $INTERFACE && break
    sleep 10
    echo "Wireguard interface /etc/wireguard/$INTERFACE.conf is down. Trying again..."
done

echo "Wireguard interface is up and running"

exit 0
