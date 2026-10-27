# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# Forticlient menu: openfortivpn connect/disconnect, SSH sessions and remote
# apps over the tunnel.

forti_title="Forticlient${FORTI_NAME:+ ($FORTI_NAME)}"
FORTI_NAME="${FORTI_NAME:-Forticlient}"

backend forticlient forti 30 "$forti_title" network-vpn

forti_available() {
    [[ -n ${FORTI_HOST:-} ]]
}

forti_menu() {
    local back=${1:-} key
    if ! forti_available; then
        notify "$FORTI_NAME" "Not configured: set FORTI_HOST in $config"
        exit 0
    fi
    # With a single configured tunnel, Connect would be the only row, so go
    # straight to the password prompt.
    if ! forti_up && ! pgrep -x openfortivpn >/dev/null; then
        forti_connect
    fi
    while :; do
        menu_reset
        forti_rows
        [[ -n $back ]] && row back "Back" go-previous
        key=$(menu "$forti_title") || exit 0
        case $key in
        back) return 0 ;;
        connect) forti_connect ;;
        disconnect) forti_disconnect ;;
        sessions) forti_sessions_menu ;;
        apps) forti_apps_menu ;;
        esac
    done
}

# A single openfortivpn tunnel always comes up as ppp0.
forti_up() {
    ip link show ppp0 &>/dev/null
}

forti_rows() {
    # Disconnect goes last so it isn't the row highlighted on open.
    if forti_up; then
        if ((${#FORTI_SSH_SESSIONS[@]})); then
            row sessions "SSH Sessions ▸" utilities-terminal
        fi
        if ((${#FORTI_SSH_APPS[@]})) && [[ -n ${FORTI_SSH_HOST:-} ]]; then
            row apps "Remote Apps ▸" application-x-executable
        fi
        row disconnect "Disconnect" network-offline
    elif pgrep -x openfortivpn >/dev/null; then
        row disconnect "Connecting… (cancel)" network-offline
    else
        row connect "Connect" network-vpn
    fi
}

# The command line must match the sudoers rule in the README exactly, and
# holds no secrets: the password goes to openfortivpn on stdin. `-c /dev/null`
# keeps /etc/openfortivpn/config out of it, since a password set there would
# be used instead of the one from stdin.
forti_command() {
    forti_cmd=(sudo -n openfortivpn -c /dev/null "$FORTI_HOST:${FORTI_PORT:-443}"
        -u "$FORTI_USER")
    [[ -n ${FORTI_TRUSTED_CERT:-} ]] && forti_cmd+=("--trusted-cert=$FORTI_TRUSTED_CERT")
}

forti_connect() {
    local pw
    pw=$(prompt_password "$FORTI_NAME password") || exit 0
    forti_command
    notify "$FORTI_NAME" "Connecting…"
    (
        local pid connected="" _
        printf '%s\n' "$pw" | "${forti_cmd[@]}" &>/dev/null &
        pid=$!
        for _ in {1..60}; do
            if forti_up; then
                connected=1
                notify "$FORTI_NAME" "Connected"
                on_change
                break
            fi
            kill -0 "$pid" 2>/dev/null || break
            sleep 1
        done
        wait "$pid"
        if [[ -n $connected ]]; then
            notify "$FORTI_NAME" "Disconnected"
        else
            notify "$FORTI_NAME" "Connection failed" critical
        fi
        on_change
    ) &>/dev/null &
    exit 0
}

forti_disconnect() {
    if ! sudo -n pkill -x openfortivpn; then
        notify "$FORTI_NAME" "Disconnect failed. Is the sudoers rule for pkill set up?" critical
    fi
    on_change
    exit 0
}

# forti_entries <array name>: split "Name|command|icon" entries into
# entry_name / entry_cmd / entry_icon arrays.
forti_entries() {
    local -n entries=$1
    local entry name cmd icon
    entry_name=() entry_cmd=() entry_icon=()
    for entry in "${entries[@]}"; do
        IFS='|' read -r name cmd icon <<<"$entry"
        entry_name+=("$name")
        entry_cmd+=("$cmd")
        entry_icon+=("$icon")
    done
}

forti_sessions_menu() {
    local key i
    forti_entries FORTI_SSH_SESSIONS
    menu_reset
    for i in "${!entry_name[@]}"; do
        row "e:$i" "${entry_name[i]}" "${entry_icon[i]:-utilities-terminal}"
    done
    row back "Back" go-previous
    key=$(menu "SSH Sessions") || exit 0
    [[ $key == back ]] && return 0
    spawn "${entry_cmd[${key#e:}]}"
    exit 0
}

forti_apps_menu() {
    local key i cmd pw target
    forti_entries FORTI_SSH_APPS
    menu_reset
    for i in "${!entry_name[@]}"; do
        row "e:$i" "${entry_name[i]}" "${entry_icon[i]:-application-x-executable}"
    done
    row back "Back" go-previous
    key=$(menu "Remote Apps") || exit 0
    [[ $key == back ]] && return 0

    cmd=${entry_cmd[${key#e:}]}
    target="${FORTI_SSH_USER:+$FORTI_SSH_USER@}$FORTI_SSH_HOST"
    pw=$(prompt_password "SSH password ($target)") || exit 0
    # sshpass -e reads the password from the environment, so it never shows
    # up in ps the way -p does.
    SSHPASS=$pw setsid -f sshpass -e ssh -Y -C "$target" "$cmd" &>/dev/null
    exit 0
}
