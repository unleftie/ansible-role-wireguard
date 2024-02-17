#! /bin/bash
# version: 4.0

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

function check_ipv4() {
    # Get all IPv4 addresses assigned to the instance
    ipv4_addresses=$(ip addr show | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b')

    # Filter out private IPv4 addresses (RFC 1918)
    private_ipv4=()
    for addr in $ipv4_addresses; do
        if [[ $addr =~ ^((10|172\.(1[6-9]|2[0-9]|3[0-1])|192\.168)\.) ]]; then
            private_ipv4+=("$addr/24")
        fi
    done

    # Return the pool of private IPv4 addresses
    echo "${private_ipv4[@]}"
}

function check_ipv6() {
    # Get all IPv6 addresses assigned to the instance
    ipv6_addresses=$(ip addr show | grep -oE '\b([0-9a-fA-F]{1,4}::?){1,7}[0-9a-fA-F]{1,4}\b')

    # Filter out private IPv6 addresses (RFC 4193)
    private_ipv6=()
    for addr in $ipv6_addresses; do
        if [[ $addr =~ ^[fcd][0-9a-f]{2} ]]; then
            private_ipv6+=("$addr/96")
        fi
    done

    # Return the pool of private IPv6 addresses
    echo "${private_ipv6[@]}"
}

function select_ipv4() {
    echo "Select the pool of IPv4 addresses to which the client will have access:"
    select ip in $(check_ipv4); do
        if [[ -n "$ip" ]]; then
            echo "Selected IPv4 address pool: $ip"
            echo "$ip" >./selected_ipv4_addresses
            break
        fi
    done
}

function select_ipv6() {
    echo "Select the pool of IPv6 addresses to which the client will have access:"
    select ip in $(check_ipv6); do
        if [[ -n "$ip" ]]; then
            echo "Selected IPv6 address pool: $ip"
            echo "$ip" >./selected_ipv6_addresses
            break
        fi
    done
}

select_addresses() {
    # Check if the files already exist
    if [ -f "./selected_ipv4_addresses" ] && [ -f "./selected_ipv6_addresses" ]; then
        echo "Selected addresses already exist. Skipping."
        return
    fi

    select_ipv4
    select_ipv6
}

# Call the main function
select_addresses

function configure_variables() {
    HOSTNAME=$(hostname)
    # NIC=$(ip -o -4 route show to default | awk '{print $5}' | head -n 1)
    WG_PORT="{{ wg_port }}"
    WG_INTERFACE="{{ wg_interface }}"
    WG_SHORT_IPV4_POOL_PART="{{ wg_short_ipv4_pool_part }}"
    WG_SHORT_IPV6_POOL_PART="{{ wg_short_ipv6_pool_part }}"
    WG_IPV4_CIDR="{{ wg_ipv4_cidr }}"
    WG_IPV6_CIDR="{{ wg_ipv6_cidr }}"

    MAIN_DIRECTORY_PATH="/etc/wireguard/$WG_INTERFACE-files"

    SERVER_ENDPOINT_IPV4=$(curl -4 -s ident.me)
    SERVER_ENDPOINT_IPV6=$(curl -6 -s ident.me)
    SERVER_PUB_KEY_PATH="$MAIN_DIRECTORY_PATH/server-pub.key"
    SERVER_CONFIG_PATH="$MAIN_DIRECTORY_PATH/$WG_INTERFACE.conf"
}

function pre_input_checks() {
    [ ! -d "$MAIN_DIRECTORY_PATH" ] && print_error "Main directory is missing: [$MAIN_DIRECTORY_PATH]"
    [ ! -e "$SERVER_PUB_KEY_PATH" ] && print_error "File is missing: [$SERVER_PUB_KEY_PATH]"
    [ ! -z $EXTERNAL_ACCESS ] && [[ $EXTERNAL_ACCESS != "true" ]] && [[ $EXTERNAL_ACCESS != "false" ]] && print_error "boolean required: [-e EXTERNAL_ACCESS]"
    [ ! -z $SERVER_ACCESS ] && [[ $SERVER_ACCESS != "true" ]] && [[ $SERVER_ACCESS != "false" ]] && print_error "boolean required: [-s SERVER_ACCESS]"
    [ ! -z $INTERNAL_DNS ] && [[ $INTERNAL_DNS != "true" ]] && [[ $INTERNAL_DNS != "false" ]] && print_error "boolean required: [-d INTERNAL_DNS]"
}

function input() {
    select_addresses
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
    CLIENT_ALLOWED_IPV4_POOL=$(cat ./selected_ipv4_addresses) && CLIENT_ALLOWED_IPV6_POOL=$(cat ./selected_ipv6_addresses)
    [[ $EXTERNAL_ACCESS == "true" ]] && CLIENT_ALLOWED_IPV4_POOL="0.0.0.0/0" && CLIENT_ALLOWED_IPV6_POOL="::0"
    [[ $INTERNAL_DNS == "true" ]] && CLIENT_DNS_IPV4="${WG_SHORT_IPV4_POOL_PART}.1" && CLIENT_DNS_IPV6="${WG_SHORT_IPV6_POOL_PART}1" ||
        CLIENT_DNS_IPV4="1.1.1.2,9.9.9.9" && CLIENT_DNS_IPV6="2606:4700:4700::1112,2620:fe::fe"
    CLIENT_CONFIG_PATH="${MAIN_DIRECTORY_PATH}/clients/${CLIENT_NAME}.conf"

    echo "
    [Peer]
    # friendly_name = $CLIENT_NAME
    PublicKey = $CLIENT_PUB_KEY
    PresharedKey = $CLIENT_PSK
    AllowedIPs = ${WG_SHORT_IPV4_POOL_PART}.${OCTET_COUNT}/32
    AllowedIPs = ${WG_SHORT_IPV6_POOL_PART}${OCTET_COUNT}/128
    PersistentKeepalive = 30" | sed 's/^[ \t]*//' >>$SERVER_CONFIG_PATH

    echo "# config for client $CLIENT_NAME
    [Interface]
    PrivateKey = $CLIENT_KEY
    Address = ${WG_SHORT_IPV4_POOL_PART}.${OCTET_COUNT}/${WG_IPV4_CIDR}
    Address = ${WG_SHORT_IPV6_POOL_PART}${OCTET_COUNT}/${WG_IPV6_CIDR}
    DNS = $CLIENT_DNS_IPV4
    DNS = $CLIENT_DNS_IPV6

    [Peer]
    PublicKey = SERVER_PUB_KEY
    PresharedKey = $CLIENT_PSK
    Endpoint = ${SERVER_ENDPOINT_IPV4}:$WG_PORT
    Endpoint = [${SERVER_ENDPOINT_IPV6}]:$WG_PORT
    AllowedIPs = $CLIENT_ALLOWED_IPV4_POOL
    AllowedIPs = $CLIENT_ALLOWED_IPV6_POOL" | sed 's/^[ \t]*//' >$CLIENT_CONFIG_PATH

    sed -i "s,SERVER_PUB_KEY,$(cat ${SERVER_PUB_KEY_PATH}),g" $CLIENT_CONFIG_PATH
}

function check_permissions() {
    WG_USERNAME=$(stat -c '%U' $MAIN_DIRECTORY_PATH/clients)
    WG_GROUP=$(stat -c '%G' $MAIN_DIRECTORY_PATH/clients)
    chown ${WG_USERNAME}:${WG_GROUP} $CLIENT_CONFIG_PATH
    chmod 600 $CLIENT_CONFIG_PATH
}

function interface_reload() {
    systemctl reload wg-quick@$WG_INTERFACE
}

function firewall() {
    if [[ $SERVER_ACCESS == "true" ]]; then
        iptables -A INPUT -s ${WG_SHORT_IPV4_POOL_PART}.${OCTET_COUNT}/32 -i $WG_INTERFACE -m comment --comment "server access from $WG_INTERFACE" -j ACCEPT
        iptables-save >/etc/iptables/rules.v4
    fi
}

function print_config() {
    echo -e "\nClient config path: $CLIENT_CONFIG_PATH"
    echo -e "\nClient config QR code:\n"
    cat "$CLIENT_CONFIG_PATH" | qrencode -t ansiutf8
}

(print_success "configure variables" && configure_variables) || print_error "configure variables"
print_success "pre_input_checks" && pre_input_checks
print_success "input" && input
(print_success "configure directories" && configure_directories) || print_error "configure directories"
(print_success "configure new octet" && configure_new_octet) || print_error "configure new octet"
(print_success "generate client secrets" && generate_client_secrets) || print_error "generate client secrets"
(print_success "generate client config" && generate_client_config) || print_error "generate client config"
(print_success "check permissions" && check_permissions) || print_error "check permissions"
(print_success "interface reload" && interface_reload) || print_error "interface reload"
(print_success "firewall" && firewall) || print_error "firewall"
(print_success "print config" && print_config) || print_error "print config"
