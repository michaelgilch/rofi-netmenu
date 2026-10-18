# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# Shared helpers for rofi-netmenu. Sourced, not executed.

# ------------------------------------------------------------------ rofi rows

# Rows are collected in parallel arrays and printed by menu(). Each row has a
# key, which is what menu() returns, so callers never parse display labels.
menu_reset() {
    _keys=()
    _labels=()
    _icons=()
}

# row <key> <label> [icon]
row() {
    _keys+=("$1")
    _labels+=("$2")
    _icons+=("${3:-}")
}

# menu <prompt> [rofi args...]
# Shows the collected rows and prints the key of the chosen one.
# Returns non-zero on Escape.
menu() {
    local prompt=$1 idx i
    shift
    idx=$(
        for i in "${!_labels[@]}"; do
            if [[ -n ${_icons[i]} ]]; then
                printf '%s\0icon\x1f%s\n' "${_labels[i]}" "${_icons[i]}"
            else
                printf '%s\n' "${_labels[i]}"
            fi
        done | rofi -dmenu -i -no-custom -format i -p "$prompt" "${rofi_args[@]}" "$@"
    ) || return 1
    [[ $idx =~ ^[0-9]+$ ]] || return 1
    printf '%s\n' "${_keys[idx]}"
}

# prompt_password <prompt>
# Prints the entered password. Returns non-zero on Escape or empty input.
prompt_password() {
    local pw
    pw=$(rofi -dmenu -password -l 0 -p "$1" "${rofi_args[@]}" </dev/null) || return 1
    [[ -n $pw ]] || return 1
    printf '%s\n' "$pw"
}

# ------------------------------------------------------------ side effects

# notify <summary> [body] [urgency]
notify() {
    notify-send -a rofi-netmenu -u "${3:-normal}" "$1" "${2:-}"
}

on_change() {
    [[ -n $ON_CHANGE ]] || return 0
    setsid -f bash -c "$ON_CHANGE" &>/dev/null || true
}

# run_bg <success summary> <failure summary> <command...>
# Runs the command in the background, reports the result, then closes the menu.
run_bg() {
    local ok=$1 fail=$2
    shift 2
    (
        local out
        if out=$("$@" 2>&1); then
            notify "$ok"
        else
            notify "$fail" "$out" critical
        fi
        on_change
    ) &>/dev/null &
    exit 0
}

# spawn <command string>: run a user-configured command detached from the menu.
spawn() {
    setsid -f bash -c "$1" &>/dev/null
}

# terminal_run <command...>
terminal_run() {
    setsid -f "$TERMINAL" -e "$@" &>/dev/null
}

# terminal_hold <command...>: like terminal_run, but keep the window open so
# the output can be read.
terminal_hold() {
    # shellcheck disable=SC2016  # "$@" is for the inner sh
    terminal_run sh -c '"$@"; printf "\nPress Enter to close."; read -r _' sh "$@"
}
