#! /bin/bash
# version: 3.0

print_error() {
    printf '%sERROR: %s%s\n' "$(printf '\033[31m')" "$*" "$(printf '\033[m')" >&2
    exit 1
}

print_success() {
    printf '%s# %s%s\n' "$(printf '\033[32m')" "$*" "$(printf '\033[m')" >&2
}

configure_directories() {
    [ ! -d "/etc/wireguard" ] && print_error "main directory /etc/wireguard does not exists"
    mkdir -p /etc/wireguard/client-config
    mkdir -p /etc/wireguard/keys
    mkdir -p /etc/wireguard/psk
    mkdir -p /etc/wireguard/pub
}

configure_variables() {
    HOSTNAME=$(hostname)
    NIC=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    WG_PORT="{{ wg_port }}"
    WG_INTERFACE="{{ wg_interface }}"
    WG_IP_POOL_PART="{{ wg_ip_pool_part }}"
    INTERNAL_IP=$(hostname -I | awk '{print $1}')
    INTERNAL_IP_POOL=${INTERNAL_IP%.*}.0/24
    SERVER_ENDPOINT=$(curl -s checkip.amazonaws.com || curl -s ifconfig.co)
}

configure_new_octet() {
    NEW_OCTET_COUNT=$(($(cat /etc/wireguard/octet.count) + 1))
    echo $NEW_OCTET_COUNT >/etc/wireguard/octet.count
    OCTET_COUNT=$(cat /etc/wireguard/octet.count)
    TAG=$OCTET_COUNT
}

check_input() {
    while getopts t: option; do
        case "${option}" in
        t) TAG=${OPTARG} ;;
        esac
    done
}

generate_client_secrets() {
    wg genpsk >/etc/wireguard/psk/$HOSTNAME-client$OCTET_COUNT.psk 2>/dev/null
    wg genkey >/etc/wireguard/keys/$HOSTNAME-client$OCTET_COUNT.key 2>/dev/null
    wg genkey | tee /etc/wireguard/keys/$HOSTNAME-client$OCTET_COUNT.key |
        wg pubkey >/etc/wireguard/pub/$HOSTNAME-client$OCTET_COUNT-pub.key
}

generate_client_config() {
    echo "
    [Peer]
    PublicKey = CLIENT_PUB_KEY
    PresharedKey = CLIENT_PSK
    AllowedIPs = $WG_IP_POOL_PART.$OCTET_COUNT/32
    PersistentKeepalive = 30" | sed 's/^[ \t]*//' >>/etc/wireguard/$WG_INTERFACE.conf

    sed -i "s,CLIENT_PUB_KEY,$(cat /etc/wireguard/pub/$HOSTNAME-client$OCTET_COUNT-pub.key),g" /etc/wireguard/$WG_INTERFACE.conf
    sed -i "s,CLIENT_PSK,$(cat /etc/wireguard/psk/$HOSTNAME-client$OCTET_COUNT.psk),g" /etc/wireguard/$WG_INTERFACE.conf

    echo "# config for client $TAG
    [Interface]
    PrivateKey = CLIENT_KEY
    Address = $WG_IP_POOL_PART.$OCTET_COUNT/24
    DNS = 1.1.1.1, 8.8.8.8

    [Peer]
    PublicKey = SERVER_PUB_KEY
    PresharedKey = CLIENT_PSK
    Endpoint = $SERVER_ENDPOINT:$WG_PORT
    AllowedIPs = $INTERNAL_IP_POOL" | sed 's/^[ \t]*//' >/etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf

    sed -i "s,SERVER_PUB_KEY,$(cat /etc/wireguard/pub/$HOSTNAME-server-pub.key),g" \
        /etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf
    sed -i "s,CLIENT_PSK,$(cat /etc/wireguard/psk/$HOSTNAME-client$OCTET_COUNT.psk),g" \
        /etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf
    sed -i "s,CLIENT_KEY,$(cat /etc/wireguard/keys/$HOSTNAME-client$OCTET_COUNT.key),g" \
        /etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf
}

check_permissions() {
    chmod 600 /etc/wireguard/*
}

interface_reload() {
    wg syncconf $WG_INTERFACE <(wg-quick strip $WG_INTERFACE)
}

print_config() {
    echo -e "\nClient config path: /etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf"
    echo -e "\nClient config QR code:\n"
    cat /etc/wireguard/client-config/$HOSTNAME-client$OCTET_COUNT-$WG_INTERFACE.conf | qrencode -t ansiutf8
}

print_success "configure directories" && configure_directories || print_error "configure directories"
print_success "configure variables" && configure_variables || print_error "configure variables"
print_success "configure new octet" && configure_new_octet || print_error "configure new octet"
print_success "check input" && check_input || print_error "check input"
print_success "generate client secrets" && generate_client_secrets || print_error "generate client secrets"
print_success "generate client config" && generate_client_config || print_error "generate client config"
print_success "check permissions" && check_permissions || print_error "check permissions"
print_success "interface reload" && interface_reload || print_error "interface reload"
print_success "print config" && print_config || print_error "print config"
