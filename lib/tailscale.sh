# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# Tailscale menu: up/down, exit nodes and devices.

ts_available() {
    command -v tailscale >/dev/null
}

ts_menu() {
    local back=${1:-} key
    if ! ts_available; then
        notify "Tailscale" "tailscale is not installed"
        exit 0
    fi
    while :; do
        if ! ts_load; then
            notify "Tailscale" "Can't get status from tailscaled"
            exit 0
        fi
        menu_reset
        ts_rows
        [[ -n $back ]] && row back "Back" go-previous
        key=$(menu "Tailscale") || exit 0
        case $key in
        back) return 0 ;;
        operator)
            terminal_hold sudo tailscale set --operator="$USER"
            exit 0
            ;;
        up) run_bg "Tailscale connected" "Tailscale failed to connect" tailscale up ;;
        down) run_bg "Tailscale disconnected" "Tailscale failed to disconnect" tailscale down ;;
        login)
            terminal_hold tailscale up
            exit 0
            ;;
        status)
            terminal_hold tailscale status
            exit 0
            ;;
        exit) ts_exit_menu ;;
        devices) ts_devices_menu ;;
        esac
    done
}

ts_load() {
    ts_status=$(tailscale status --json 2>/dev/null)
    [[ -n $ts_status ]] || return 1
    ts_prefs=$(tailscale debug prefs 2>/dev/null)
    [[ -n $ts_prefs ]] || ts_prefs='{}'

    ts_state=$(jq -r '.BackendState // "NoState"' <<<"$ts_status")
    ts_operator=$(jq -r '.OperatorUser // ""' <<<"$ts_prefs")
    ts_exit_id=$(jq -r '.ExitNodeID // ""' <<<"$ts_prefs")
    ts_allow_lan=$(jq -r '.ExitNodeAllowLANAccess // false' <<<"$ts_prefs")
    ts_exit_name=""
    if [[ -n $ts_exit_id ]]; then
        ts_exit_name=$(jq -r --arg id "$ts_exit_id" \
            '.Peer[]? | select(.ID == $id) | .HostName' <<<"$ts_status")
        ts_exit_name=${ts_exit_name:-$ts_exit_id}
    fi
}

ts_rows() {
    # State changes need root unless this user is the operator. Offer the
    # one-time setup instead of failing from inside the menu.
    if [[ $ts_operator != "$USER" && $EUID -ne 0 ]]; then
        row operator "Grant operator access" dialog-password
        return 0
    fi

    case $ts_state in
    Running)
        # Disconnect goes last so it isn't the row highlighted on open.
        row exit "Exit Node: ${ts_exit_name:-none} ▸" network-vpn
        row devices "Devices ▸" network-workgroup
        row down "Disconnect" network-offline
        ;;
    Stopped) row up "Connect" network-vpn ;;
    NeedsLogin | NeedsMachineAuth) row login "Log in" network-vpn ;;
    *) row status "Status: $ts_state" dialog-information ;;
    esac
}

ts_exit_menu() {
    local hosts=() ids=() host id key i
    while IFS='|' read -r host id; do
        [[ -n $host ]] || continue
        hosts+=("$host")
        ids+=("$id")
    done < <(jq -r '.Peer[]? | select(.ExitNodeOption == true)
                    | "\(.HostName)|\(.ID)"' <<<"$ts_status" | sort)

    menu_reset
    if [[ -n $ts_exit_id ]]; then
        row none "None (direct)" network-wired
    else
        row current "None (direct)  ✓" network-wired
    fi
    for i in "${!hosts[@]}"; do
        if [[ ${ids[i]} == "$ts_exit_id" ]]; then
            row current "${hosts[i]}  ✓" network-vpn
        else
            row "node:$i" "${hosts[i]}" network-vpn
        fi
    done
    # --exit-node-allow-lan-access is only accepted while an exit node is set.
    if [[ -n $ts_exit_id ]]; then
        if [[ $ts_allow_lan == true ]]; then
            row lan:false "Allow LAN access: on" network-wired
        else
            row lan:true "Allow LAN access: off" network-wired
        fi
    fi

    row back "Back" go-previous
    key=$(menu "Exit Node") || exit 0
    case $key in
    back) return 0 ;;
    current) exit 0 ;;
    none) run_bg "Exit node: none" "Failed to clear exit node" tailscale set --exit-node= ;;
    node:*)
        host=${hosts[${key#node:}]}
        run_bg "Exit node: $host" "Failed to set exit node $host" \
            tailscale set --exit-node="$host"
        ;;
    lan:*)
        run_bg "Allow LAN access: ${key#lan:}" "Failed to change LAN access" \
            tailscale set --exit-node-allow-lan-access="${key#lan:}"
        ;;
    esac
}

ts_devices_menu() {
    local key
    while :; do
        menu_reset
        row ssh "SSH ▸" utilities-terminal
        row ip "Copy IP ▸" edit-copy
        row back "Back" go-previous
        key=$(menu "Devices") || exit 0
        case $key in
        back) return 0 ;;
        ssh) ts_ssh_menu ;;
        ip) ts_ip_menu ;;
        esac
    done
}

# Peers have no Tailscale SSH host keys, so these are plain ssh sessions over
# the tailnet DNS name. Phones are left out; they're only in the Copy IP list.
ts_ssh_menu() {
    local hosts=() dnss=() host dns key i
    while IFS='|' read -r host dns; do
        [[ -n $host ]] || continue
        hosts+=("$host")
        dnss+=("${dns%.}")
    done < <(jq -r '.Peer[]? | select(.Online == true)
                    | select(.OS != "android" and .OS != "iOS")
                    | "\(.HostName)|\(.DNSName)"' <<<"$ts_status" | sort)

    menu_reset
    for i in "${!hosts[@]}"; do
        row "h:$i" "${hosts[i]}" utilities-terminal
    done
    row back "Back" go-previous
    key=$(menu "SSH") || exit 0
    [[ $key == back ]] && return 0
    terminal_run ssh "$TS_SSH_USER@${dnss[${key#h:}]}"
    exit 0
}

ts_ip_menu() {
    local hosts=() ips=() host ip key i
    while IFS='|' read -r host ip; do
        [[ -n $host && -n $ip ]] || continue
        hosts+=("$host")
        ips+=("$ip")
    done < <(jq -r '.Peer[]? | "\(.HostName)|\(.TailscaleIPs[0] // "")"' \
        <<<"$ts_status" | sort)

    menu_reset
    for i in "${!hosts[@]}"; do
        row "h:$i" "${hosts[i]}  ${ips[i]}" edit-copy
    done
    row back "Back" go-previous
    key=$(menu "Copy IP") || exit 0
    [[ $key == back ]] && return 0
    ip=${ips[${key#h:}]}
    printf '%s' "$ip" | xclip -selection clipboard
    notify "Tailscale" "Copied $ip"
    exit 0
}
