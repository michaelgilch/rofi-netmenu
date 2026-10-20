# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# Ethernet menu: one row per wired device, through nmcli.
#
# Every `nmcli -t` call below disables escaping and puts the only free-text
# field last, so `IFS=: read` splits cleanly and the last variable keeps any
# colons in a name.

backend ethernet eth 10 "Ethernet" network-wired

eth_load() {
    eth_dev=() eth_state=() eth_conn=()
    local dev type state conn
    while IFS=: read -r dev type state conn; do
        [[ $type == ethernet ]] || continue
        eth_dev+=("$dev")
        eth_state+=("$state")
        eth_conn+=("$conn")
    done < <(nmcli -t --escape no -f DEVICE,TYPE,STATE,CONNECTION device)
}

eth_available() {
    eth_load
    ((${#eth_dev[@]} > 0))
}

eth_menu() {
    local back=${1:-} key i label
    if ! eth_available; then
        notify "Ethernet" "No ethernet devices found"
        exit 0
    fi

    menu_reset
    for i in "${!eth_dev[@]}"; do
        case ${eth_state[i]} in
        connected*) label="󰈀 ${eth_dev[i]}  ${eth_conn[i]}  ✓" ;;
        unavailable) label="󰈂 ${eth_dev[i]}  unplugged" ;;
        *) label="󰈂 ${eth_dev[i]}  ${eth_state[i]}" ;;
        esac
        row "eth:$i" "$label"
    done

    [[ -n $back ]] && row back "Back" go-previous
    key=$(menu "Ethernet") || exit 0
    case $key in
    back) return 0 ;;
    eth:*) eth_toggle "${key#eth:}" ;;
    esac
}

eth_toggle() {
    local dev=${eth_dev[$1]}
    case ${eth_state[$1]} in
    unavailable)
        notify "$dev" "No cable"
        exit 0
        ;;
    connected*)
        run_bg "$dev disconnected" "Failed to disconnect $dev" nmcli device disconnect "$dev"
        ;;
    *)
        run_bg "$dev connected" "Failed to connect $dev" nmcli device connect "$dev"
        ;;
    esac
}
