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

function print_warning() {
    printf '%sWARNING: %s%s\n' "$(printf '\033[31m')" "$*" "$(printf '\033[m')" >&2
}

function print_error() {
    printf '%sERROR: %s%s\n' "$(printf '\033[31m')" "$*" "$(printf '\033[m')" >&2
    exit 1
}

function get_input() {
    read -rp "$1" "$2"
}

function get_keypress() {
    local REPLY IFS=
    printf >/dev/tty '%s' "$*"
    read </dev/tty -rn1
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
            # Replace the last octet with 0
            addr=$(echo $addr | sed 's/\.[0-9]\{1,3\}$/\.0/')
            private_ipv4+=("$addr/24")
        fi
    done

    # Return the pool of private IPv4 addresses
    echo "${private_ipv4[@]}"
}

function select_ipv4_pool() {
    echo "Select the pool of IPv4 addresses to which the client will have access (if EXTERNAL_ACCESS is disabled):"
    select ip in $(check_ipv4); do
        if [[ -n "$ip" ]]; then
            echo -e "Selected IPv4 address pool: $ip\n"
            echo "$ip" >$MAIN_DIRECTORY_PATH/allowed_ipv4_pool.txt
            chown ${WG_USERNAME}:${WG_GROUP} $MAIN_DIRECTORY_PATH/allowed_ipv4_pool.txt
            chmod 600 $MAIN_DIRECTORY_PATH/allowed_ipv4_pool.txt
            break
        fi
    done
}

function set_ipv6_pool() {
    # Set the pool of IPv6 addresses to which the client will have access (if EXTERNAL_ACCESS is disabled)
    echo "fc00::/7" >$MAIN_DIRECTORY_PATH/allowed_ipv6_pool.txt
    chown ${WG_USERNAME}:${WG_GROUP} $MAIN_DIRECTORY_PATH/allowed_ipv6_pool.txt
    chmod 600 $MAIN_DIRECTORY_PATH/allowed_ipv6_pool.txt
}

select_addresses() {
    # check if the files with addresses already exist
    if [ -f "$MAIN_DIRECTORY_PATH/allowed_ipv4_pool.txt" ] && [ -f "$MAIN_DIRECTORY_PATH/allowed_ipv6_pool.txt" ]; then
        return
    fi

    select_ipv4_pool
    set_ipv6_pool
}

function configure_variables() {
    WG_PORT="{{ wg_port }}"
    WG_INTERFACE="{{ wg_interface }}"
    WG_SHORT_IPV4_POOL_PART="{{ wg_short_ipv4_pool_part }}"
    WG_SHORT_IPV6_POOL_PART="{{ wg_short_ipv6_pool_part }}"
    WG_IPV4_CIDR="{{ wg_ipv4_cidr }}"
    WG_IPV6_CIDR="{{ wg_ipv6_cidr }}"
    WG_USERNAME="{{ wg_system_user }}"
    WG_GROUP="{{ wg_system_group }}"
    MAIN_DIRECTORY_PATH="/etc/wireguard/{{ wg_interface }}-files"

    SERVER_ENDPOINT_IPV4=$(curl -4 -s ident.me)
    SERVER_ENDPOINT_IPV6=$(curl -6 -s ident.me)
    SERVER_PUB_KEY_PATH="$MAIN_DIRECTORY_PATH/server-pub.key"
    SERVER_CONFIG_PATH="$MAIN_DIRECTORY_PATH/{{ wg_interface }}.conf"
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
    OCTET_COUNT=$(($(cat ${MAIN_DIRECTORY_PATH}/octet.count) + 1))
    echo $OCTET_COUNT >${MAIN_DIRECTORY_PATH}/octet.count
}

function generate_client_secrets() {
    CLIENT_PSK=$(wg genpsk)
    CLIENT_KEY=$(wg genkey)
    CLIENT_PUB_KEY=$(echo $CLIENT_KEY | wg pubkey)
}

function generate_client_config() {
    CLIENT_ALLOWED_IPV4_POOL=$(cat ${MAIN_DIRECTORY_PATH}/allowed_ipv4_pool.txt) && CLIENT_ALLOWED_IPV6_POOL=$(cat ${MAIN_DIRECTORY_PATH}/allowed_ipv6_pool.txt)
    [[ $EXTERNAL_ACCESS == "true" ]] && CLIENT_ALLOWED_IPV4_POOL="0.0.0.0/0" && CLIENT_ALLOWED_IPV6_POOL="::/0"
    if [[ $INTERNAL_DNS == "true" ]]; then
        CLIENT_DNS_IPV4="${WG_SHORT_IPV4_POOL_PART}.1"
        CLIENT_DNS_IPV6="${WG_SHORT_IPV6_POOL_PART}1"
    else
        CLIENT_DNS_IPV4="1.1.1.2,9.9.9.9"
        CLIENT_DNS_IPV6="2606:4700:4700::1112,2620:fe::fe"
    fi

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
    # IPv4 Endpoint
    Endpoint = ${SERVER_ENDPOINT_IPV4}:$WG_PORT
    # IPv6 Endpoint (disabled by default, can be used in IPv6-only scheme)
    # Endpoint = [${SERVER_ENDPOINT_IPV6}]:$WG_PORT 
    AllowedIPs = $CLIENT_ALLOWED_IPV4_POOL
    AllowedIPs = $CLIENT_ALLOWED_IPV6_POOL" | sed 's/^[ \t]*//' >$CLIENT_CONFIG_PATH

    sed -i "s,SERVER_PUB_KEY,$(cat ${SERVER_PUB_KEY_PATH}),g" $CLIENT_CONFIG_PATH
}

function check_permissions() {
    chown ${WG_USERNAME}:${WG_GROUP} $CLIENT_CONFIG_PATH
    chmod 600 $CLIENT_CONFIG_PATH
}

function interface_reload() {
    systemctl reload wg-quick@${WG_INTERFACE}
}

function firewall() {
    if [[ $SERVER_ACCESS == "true" ]]; then
        iptables -A INPUT -s ${WG_SHORT_IPV4_POOL_PART}.${OCTET_COUNT}/32 -i $WG_INTERFACE -m comment --comment "server access from $WG_INTERFACE" -j ACCEPT
        iptables-save >/etc/iptables/rules.v4
        print_warning "added iptables rule to access server"

        ip6tables -A INPUT -s ${WG_SHORT_IPV6_POOL_PART}${OCTET_COUNT}/128 -i $WG_INTERFACE -m comment --comment "server access from $WG_INTERFACE" -j ACCEPT
        ip6tables-save >/etc/iptables/rules.v6
        print_warning "added ip6tables rule to access server"
    fi
}

function print_config() {
    echo -e "\nClient config path: $CLIENT_CONFIG_PATH"
    echo -e "\nClient config QR code:\n"
    cat "$CLIENT_CONFIG_PATH" | qrencode -t ansiutf8
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
