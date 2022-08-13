#! /bin/bash
# version: 3.1

set -eo pipefail

# TODO: AllowedIPs = 0.0.0.0/0
while getopts "n:" option; do
    case "${option}" in
    n) CLIENT_NAME=${OPTARG} ;;
    esac
done

print_error() {
    printf '%sERROR: %s%s\n' "$(printf '\033[31m')" "$*" "$(printf '\033[m')" >&2
    exit 1
}

print_success() {
    printf '%s# %s%s\n' "$(printf '\033[32m')" "$*" "$(printf '\033[m')" >&2
}

configure_variables() {
    HOSTNAME=$(hostname)
    NIC=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    WG_PORT="{{ wg_port }}"
    WG_INTERFACE="{{ wg_interface }}"
    WG_IP_POOL_PART="{{ wg_ip_pool_part }}"
    INTERNAL_IP=$(hostname -I | awk '{print $1}')
    INTERNAL_IP_POOL=${INTERNAL_IP%.*}.0/24
    SERVER_ENDPOINT=$(curl -s checkip.amazonaws.com || curl -s ident.me)
    SERVER_PUB_KEY_PATH="/etc/wireguard/server-pub.key"
    CLIENT_PUB_KEY_PATH="/etc/wireguard/tmp/client-pub.key"
    CLIENT_KEY_PATH="/etc/wireguard/tmp/client.key"
    CLIENT_PSK_PATH="/etc/wireguard/tmp/client.psk"
    CLIENT_CONFIG_PATH="/etc/wireguard/client-configs/$HOSTNAME-$WG_INTERFACE-client-$CLIENT_NAME.conf"
}

# TODO: FIX ????
pre_checks() {
    [ -z "$CLIENT_NAME" ] && print_error "Not enough arguments: [-n CLIENT_NAME]"
    [ ! -d "/etc/wireguard" ] && print_error "Main directory is missing: [/etc/wireguard]"
    [ ! -e "$SERVER_PUB_KEY_PATH" ] && print_error "File is missing: [Server public key]"
}

configure_directories() {
    mkdir -p /etc/wireguard/client-configs
    mkdir -p /etc/wireguard/tmp
}

configure_new_octet() {
    NEW_OCTET_COUNT=$(($(cat /etc/wireguard/octet.count) + 1))
    echo $NEW_OCTET_COUNT >/etc/wireguard/octet.count
    OCTET_COUNT=$(cat /etc/wireguard/octet.count)
}

generate_client_secrets() {
    wg genpsk >$CLIENT_PSK_PATH 2>/dev/null
    wg genkey >$CLIENT_KEY_PATH 2>/dev/null
    wg genkey | tee $CLIENT_KEY_PATH | wg pubkey >$CLIENT_PUB_KEY_PATH
}

generate_client_config() {
    echo "
    [Peer]
    # friendly_name = $CLIENT_NAME
    PublicKey = CLIENT_PUB_KEY
    PresharedKey = CLIENT_PSK
    AllowedIPs = $WG_IP_POOL_PART.$OCTET_COUNT/32
    PersistentKeepalive = 30" | sed 's/^[ \t]*//' >>/etc/wireguard/$WG_INTERFACE.conf

    sed -i "s,CLIENT_PUB_KEY,$(cat $CLIENT_PUB_KEY_PATH),g" /etc/wireguard/$WG_INTERFACE.conf
    sed -i "s,CLIENT_PSK,$(cat $CLIENT_PSK_PATH),g" /etc/wireguard/$WG_INTERFACE.conf

    echo "# config for client $CLIENT_NAME
    [Interface]
    PrivateKey = CLIENT_KEY
    Address = $WG_IP_POOL_PART.$OCTET_COUNT/24
    DNS = 1.1.1.1, 8.8.8.8

    [Peer]
    PublicKey = SERVER_PUB_KEY
    PresharedKey = CLIENT_PSK
    Endpoint = $SERVER_ENDPOINT:$WG_PORT
    AllowedIPs = $INTERNAL_IP_POOL" | sed 's/^[ \t]*//' >$CLIENT_CONFIG_PATH

    sed -i "s,SERVER_PUB_KEY,$(cat $SERVER_PUB_KEY_PATH),g" $CLIENT_CONFIG_PATH
    sed -i "s,CLIENT_PSK,$(cat $CLIENT_PSK_PATH),g" $CLIENT_CONFIG_PATH
    sed -i "s,CLIENT_KEY,$(cat $CLIENT_KEY_PATH),g" $CLIENT_CONFIG_PATH
}

check_permissions() {
    chmod 600 $CLIENT_CONFIG_PATH
}

interface_reload() {
    systemctl reload wg-quick@$WG_INTERFACE
}

cleanup() {
    rm -rfd /etc/wireguard/tmp
}

print_config() {
    echo -e "\nClient config path: $CLIENT_CONFIG_PATH"
    echo -e "\nClient config QR code:\n"
    cat $CLIENT_CONFIG_PATH | qrencode -t ansiutf8
}

print_success "configure variables" && configure_variables || print_error "configure variables"
print_success "pre_checks" && pre_checks || print_error "pre_checks"
print_success "configure directories" && configure_directories || print_error "configure directories"
print_success "configure new octet" && configure_new_octet || print_error "configure new octet"
print_success "generate client secrets" && generate_client_secrets || print_error "generate client secrets"
print_success "generate client config" && generate_client_config || print_error "generate client config"
print_success "check permissions" && check_permissions || print_error "check permissions"
print_success "interface reload" && interface_reload || print_error "interface reload"
print_success "cleanup" && cleanup || print_error "cleanup"
print_success "print config" && print_config || print_error "print config"
