# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# Wifi menu: radio, saved networks and the SSID list, through nmcli.
#
# Every `nmcli -t` call below disables escaping and puts the only free-text
# field last, so `IFS=: read` splits cleanly and the last variable keeps any
# colons in a name.

wifi_load_device() {
    wifi_iface="" wifi_state=""
    local dev type state
    while IFS=: read -r dev type state; do
        if [[ $type == wifi ]]; then
            wifi_iface=$dev
            wifi_state=$state
            return 0
        fi
    done < <(nmcli -t --escape no -f DEVICE,TYPE,STATE device)
}

wifi_available() {
    wifi_load_device
    [[ -n $wifi_iface ]]
}

wifi_menu() {
    local back=${1:-} rescan=no key
    while :; do
        if ! wifi_available; then
            notify "Wifi" "No Wi-Fi device found"
            exit 0
        fi
        menu_reset
        wifi_rows "$rescan"
        rescan=no

        [[ -n $back ]] && row back "Back" go-previous
        key=$(menu "Wifi") || exit 0
        case $key in
        back) return 0 ;;
        radio:*)
            run_bg "Wifi turned ${key#radio:}" "Failed to turn Wifi ${key#radio:}" \
                nmcli radio wifi "${key#radio:}"
            ;;
        disconnect)
            run_bg "Wifi disconnected" "Failed to disconnect $wifi_iface" \
                nmcli device disconnect "$wifi_iface"
            ;;
        rescan)
            notify "Wifi" "Scanning…"
            rescan=yes
            ;;
        forget) wifi_forget_menu ;;
        ssid:*) wifi_select "${ssids[${key#ssid:}]}" ;;
        esac
    done
}

# Prints "uuid<TAB>ssid<TAB>name" for every saved Wi-Fi profile.
wifi_profiles() {
    local uuid type name ssid
    while IFS=: read -r uuid type name; do
        [[ $type == 802-11-wireless ]] || continue
        ssid=$(nmcli --escape no -g 802-11-wireless.ssid connection show uuid "$uuid" </dev/null)
        printf '%s\t%s\t%s\n' "$uuid" "$ssid" "$name"
    done < <(nmcli -t --escape no -f UUID,TYPE,NAME connection show)
}

# wifi_scan <no|yes>
# Fills ssids (display order) and the wifi_* / known maps, keyed by SSID.
wifi_scan() {
    declare -gA known=() wifi_signal=() wifi_bars=() wifi_sec=() wifi_used=()
    ssids=()
    local uuid ssid name inuse signal bars sec cur rank

    # Matched by SSID, not profile name, so renamed profiles and "SSID 1"
    # duplicates still count as known.
    while IFS=$'\t' read -r uuid ssid name; do
        [[ -n $ssid ]] && known[$ssid]=$uuid
    done < <(wifi_profiles)

    while IFS=: read -r inuse signal bars sec ssid; do
        [[ -n $ssid ]] || continue
        [[ $inuse == '*' ]] && wifi_used[$ssid]=1
        # SSIDs are untrusted, so keep them out of arithmetic contexts.
        cur=${wifi_signal[$ssid]:--1}
        if ((signal > cur)); then
            wifi_signal[$ssid]=$signal
            wifi_bars[$ssid]=$bars
            wifi_sec[$ssid]=$sec
        fi
    done < <(nmcli -t --escape no -f IN-USE,SIGNAL,BARS,SECURITY,SSID \
        device wifi list --rescan "$1")

    while IFS=$'\t' read -r _ _ ssid; do
        ssids+=("$ssid")
    done < <(
        for ssid in "${!wifi_signal[@]}"; do
            rank=2
            [[ -n ${known[$ssid]:-} ]] && rank=1
            [[ -n ${wifi_used[$ssid]:-} ]] && rank=0
            printf '%s\t%s\t%s\n' "$rank" "${wifi_signal[$ssid]}" "$ssid"
        done | sort -t $'\t' -k1,1n -k2,2nr
    )
}

wifi_secured() {
    case ${wifi_sec[$1]} in
    "" | "--" | OWE) return 1 ;;
    esac
}

wifi_rows() {
    local i ssid label

    if [[ $(nmcli radio wifi) != enabled ]]; then
        row radio:on "Wifi: off" network-wireless-offline
        row forget "Forget network ▸" edit-delete
        return 0
    fi

    # The first row is highlighted on open, so the SSID list comes first and
    # the rows that drop the connection come last.
    wifi_scan "$1"
    # Listing from cache keeps the menu instant; a scan that doesn't block
    # keeps the cache fresh for the next open.
    [[ $1 == no ]] && nmcli device wifi rescan &>/dev/null &
    for i in "${!ssids[@]}"; do
        ssid=${ssids[i]}
        label="󰖩 ${wifi_bars[$ssid]}  $ssid"
        wifi_secured "$ssid" && label+="  "
        [[ -n ${wifi_used[$ssid]:-} ]] && label+="  ✓"
        row "ssid:$i" "$label"
    done
    row rescan "Rescan" view-refresh
    row forget "Forget network ▸" edit-delete
    [[ $wifi_state == connected ]] && row disconnect "Disconnect" network-offline
    row radio:off "Wifi: on" network-wireless
}

wifi_select() {
    local ssid=$1 pw

    if [[ -n ${wifi_used[$ssid]:-} ]]; then
        wifi_connected_menu "$ssid"
        return
    fi

    if [[ -n ${known[$ssid]:-} ]]; then
        notify "Wifi" "Connecting to $ssid…"
        run_bg "Connected to $ssid" "Failed to connect to $ssid" \
            nmcli connection up uuid "${known[$ssid]}"
    fi

    case ${wifi_sec[$ssid]} in
    *802.1X*)
        notify "$ssid" "Enterprise (802.1X) networks need nm-connection-editor"
        exit 0
        ;;
    esac

    notify "Wifi" "Connecting to $ssid…"
    if ! wifi_secured "$ssid"; then
        run_bg "Connected to $ssid" "Failed to connect to $ssid" \
            nmcli device wifi connect "$ssid" ifname "$wifi_iface"
    fi

    pw=$(prompt_password "Password for $ssid") || exit 0
    wifi_connect_new "$ssid" "$pw"
}

# The password goes to nmcli on stdin via --ask, never on its command line.
wifi_connect_new() {
    local ssid=$1 pw=$2
    (
        local out uuid pssid
        if out=$(printf '%s\n' "$pw" |
            nmcli --ask device wifi connect "$ssid" ifname "$wifi_iface" 2>&1); then
            notify "Connected to $ssid"
        else
            # NetworkManager keeps the profile after a failed attempt and would
            # reuse it next time instead of asking for the password again. The
            # network had no profile before, so any profile for it is ours.
            while IFS=$'\t' read -r uuid pssid _; do
                [[ $pssid == "$ssid" ]] && nmcli connection delete uuid "$uuid"
            done < <(wifi_profiles)
            notify "Failed to connect to $ssid" "$out" critical
        fi
        on_change
    ) &>/dev/null &
    exit 0
}

wifi_connected_menu() {
    local ssid=$1 key
    menu_reset
    row disconnect "Disconnect" network-offline
    [[ -n ${known[$ssid]:-} ]] && row forget "Forget" edit-delete
    row back "Back" go-previous
    key=$(menu "$ssid") || exit 0
    case $key in
    back) return 0 ;;
    disconnect)
        run_bg "Disconnected from $ssid" "Failed to disconnect $wifi_iface" \
            nmcli device disconnect "$wifi_iface"
        ;;
    forget)
        run_bg "Forgot $ssid" "Failed to forget $ssid" \
            nmcli connection delete uuid "${known[$ssid]}"
        ;;
    esac
}

wifi_forget_menu() {
    local uuids=() names=() uuid name key i
    while IFS=$'\t' read -r uuid _ name; do
        uuids+=("$uuid")
        names+=("$name")
    done < <(wifi_profiles | sort -t $'\t' -k3)

    menu_reset
    for i in "${!names[@]}"; do
        row "p:$i" "${names[i]}" network-wireless
    done
    row back "Back" go-previous
    key=$(menu "Forget") || exit 0
    case $key in
    back) return 0 ;;
    p:*)
        i=${key#p:}
        run_bg "Forgot ${names[i]}" "Failed to forget ${names[i]}" \
            nmcli connection delete uuid "${uuids[i]}"
        ;;
    esac
}
