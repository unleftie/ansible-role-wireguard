#! /bin/bash
# version: 3.3

set -o pipefail

while getopts "n:e:s:d:" option; do
    case "${option}" in
    n) CLIENT_NAME=${OPTARG} ;;
    e) EXTERNAL_ACCESS=${OPTARG} ;;
    s) SERVER_ACCESS=${OPTARG} ;;
    d) INTERNAL_DNS=${OPTARG} ;;
    esac
done

function print_success() {
    printf '%s# %s%s\n' "$(printf '\033[32m')" "$*" "$(printf '\033[m')" >&2
}

function print_error() {
    printf '%sERROR: %s%s\n' "$(printf '\033[31m')" "$*" "$(printf '\033[m')" >&2
    exit 1
}

function get_input() {
    [[ $ZSH_VERSION ]] && read "$2"\?"$1"
    [[ $BASH_VERSION ]] && read -p "$1" "$2"
}

function get_keypress() {
    local REPLY IFS=
    printf >/dev/tty '%s' "$*"
    [[ $ZSH_VERSION ]] && read -rk1
    [[ $BASH_VERSION ]] && read </dev/tty -rn1
    printf '%s' "$REPLY"
}

function confirm() {
    local prompt="${1:-Are you sure?} [y/n] "
    local enter_return=$2
    local REPLY
    while REPLY=$(get_keypress "$prompt"); do
        [[ $REPLY ]] && printf '\n'
        case "$REPLY" in
        Y | y) return 0 ;;
        N | n) return 1 ;;
        '') [[ $enter_return ]] && return "$enter_return" ;;
        esac
    done
}

function configure_variables() {
    HOSTNAME=$(hostname)
    NIC=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    WG_PORT="{{ wg_port }}"
    WG_INTERFACE="{{ wg_interface }}"
    WG_SHORT_IP_POOL_PART="{{ wg_short_ip_pool_part }}"
    INTERNAL_IP=$(hostname -I | awk '{print $1}')

    MAIN_DIRECTORY_PATH="/etc/wireguard/$WG_INTERFACE-files"

    SERVER_ENDPOINT=$(curl -s checkip.amazonaws.com || curl -s ident.me)
    SERVER_PUB_KEY_PATH="$MAIN_DIRECTORY_PATH/server-pub.key"
    SERVER_CONFIG_PATH="$MAIN_DIRECTORY_PATH/$WG_INTERFACE.conf"

    CLIENT_ALLOWED_IP_POOL=${INTERNAL_IP%.*}.0/24
}

function pre_input_checks() {
    [ ! -d "$MAIN_DIRECTORY_PATH" ] && print_error "Main directory is missing: [$MAIN_DIRECTORY_PATH]"
    [ ! -e "$SERVER_PUB_KEY_PATH" ] && print_error "File is missing: [$SERVER_PUB_KEY_PATH]"
    [ ! -z $EXTERNAL_ACCESS ] && [[ $EXTERNAL_ACCESS != "true" ]] && [[ $EXTERNAL_ACCESS != "false" ]] && print_error "boolean required: [-e EXTERNAL_ACCESS]"
    [ ! -z $SERVER_ACCESS ] && [[ $SERVER_ACCESS != "true" ]] && [[ $SERVER_ACCESS != "false" ]] && print_error "boolean required: [-s SERVER_ACCESS]"
    [ ! -z $INTERNAL_DNS ] && [[ $INTERNAL_DNS != "true" ]] && [[ $INTERNAL_DNS != "false" ]] && print_error "boolean required: [-d INTERNAL_DNS]"
}

function input() {
    [ -z "$CLIENT_NAME" ] && get_input "Client name: " CLIENT_NAME
    [[ "$CLIENT_NAME" == "" ]] && print_error "'Client name' value cannot be blank"
    [ "${CLIENT_NAME//[A-Za-z0-9_]/}" ] && print_error "Valid characters for 'client name' value are 'A-Z', 'a-z', '0-9' and '_'"
    grep -q "friendly_name = $CLIENT_NAME" $SERVER_CONFIG_PATH && print_error "'Client name' value already in use: $CLIENT_NAME"
    [ -z "$EXTERNAL_ACCESS" ] && confirm "Whether to allow external access?" && EXTERNAL_ACCESS="true"
    [ -z "$SERVER_ACCESS" ] && confirm "Whether to allow access to server?" && SERVER_ACCESS="true"
    [ -z "$INTERNAL_DNS" ] && confirm "Whether to use internal DNS?" && INTERNAL_DNS="true"
}

function configure_directories() {
    mkdir -p $MAIN_DIRECTORY_PATH/clients
}

function configure_new_octet() {
    OCTET_COUNT=$(($(cat $MAIN_DIRECTORY_PATH/octet.count) + 1))
    echo $OCTET_COUNT >$MAIN_DIRECTORY_PATH/octet.count
}

function generate_client_secrets() {
    CLIENT_PSK=$(wg genpsk)
    CLIENT_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo $CLIENT_KEY | wg pubkey)
}

function generate_client_config() {
    [[ $EXTERNAL_ACCESS == "true" ]] && CLIENT_ALLOWED_IP_POOL="0.0.0.0/0"
    [[ $INTERNAL_DNS == "true" ]] && CLIENT_DNS="$WG_SHORT_IP_POOL_PART.1" || CLIENT_DNS="1.1.1.1, 8.8.8.8"
    CLIENT_CONFIG_PATH="$MAIN_DIRECTORY_PATH/clients/$CLIENT_NAME.conf"

    echo "
    [Peer]
    # friendly_name = $CLIENT_NAME
    PublicKey = $CLIENT_PUB_KEY
    PresharedKey = $CLIENT_PSK
    AllowedIPs = $WG_SHORT_IP_POOL_PART.$OCTET_COUNT/32
    PersistentKeepalive = 30" | sed 's/^[ \t]*//' >>$SERVER_CONFIG_PATH

    echo "# config for client $CLIENT_NAME
    [Interface]
    PrivateKey = $CLIENT_KEY
    Address = $WG_SHORT_IP_POOL_PART.$OCTET_COUNT/24
    DNS = $CLIENT_DNS

    [Peer]
    PublicKey = SERVER_PUB_KEY
    PresharedKey = $CLIENT_PSK
    Endpoint = $SERVER_ENDPOINT:$WG_PORT
    AllowedIPs = $CLIENT_ALLOWED_IP_POOL" | sed 's/^[ \t]*//' >$CLIENT_CONFIG_PATH

    sed -i "s,SERVER_PUB_KEY,$(cat $SERVER_PUB_KEY_PATH),g" $CLIENT_CONFIG_PATH
}

function check_permissions() {
    WG_USERNAME=$(stat -c '%U' $MAIN_DIRECTORY_PATH/clients)
    WG_GROUP=$(stat -c '%G' $MAIN_DIRECTORY_PATH/clients)
    chown $WG_USERNAME:$WG_GROUP $CLIENT_CONFIG_PATH
    chmod 600 $CLIENT_CONFIG_PATH
}

function interface_reload() {
    systemctl reload wg-quick@$WG_INTERFACE
}

function firewall() {
    if [[ $SERVER_ACCESS == "true" ]]; then
        iptables -A INPUT -s $WG_SHORT_IP_POOL_PART.$OCTET_COUNT/32 -i $WG_INTERFACE -m comment --comment "server access from $WG_INTERFACE" -j ACCEPT
        iptables-save >/etc/iptables/rules.v4
    fi
}

function print_config() {
    echo -e "\nClient config path: $CLIENT_CONFIG_PATH"
    echo -e "\nClient config QR code:\n"
    cat $CLIENT_CONFIG_PATH | qrencode -t ansiutf8
}

print_success "configure variables" && configure_variables || print_error "configure variables"
print_success "pre_input_checks" && pre_input_checks
print_success "input" && input
print_success "configure directories" && configure_directories || print_error "configure directories"
print_success "configure new octet" && configure_new_octet || print_error "configure new octet"
print_success "generate client secrets" && generate_client_secrets || print_error "generate client secrets"
print_success "generate client config" && generate_client_config || print_error "generate client config"
print_success "check permissions" && check_permissions || print_error "check permissions"
print_success "interface reload" && interface_reload || print_error "interface reload"
print_success "firewall" && firewall || print_error "firewall"
print_success "print config" && print_config || print_error "print config"
