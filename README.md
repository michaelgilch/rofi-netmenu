# rofi-netmenu

Network management from a [rofi](https://github.com/davatorium/rofi) menu.

Supports:
- **Ethernet** through NetworkManager
- **Wi-Fi** through NetworkManager
- **FortiClient-compatible SSL VPN** through `openfortivpn`
- **Tailscale**

New backend interfaces can be added under `lib/`. The menu is populated from whatever is available at that location. See [Adding a backend](#adding-a-backend).

## Features

The top-level menu lists only the backends that apply: no wired device means
no Ethernet entry, an empty `FORTI_HOST` hides the VPN, and so on. Each backend
can also be opened directly from the command line.

- **Ethernet**: connect or disconnect each wired device.
- **Wi-Fi**: toggle the radio, scan, connect (open, WPA or saved), disconnect
  and forget networks.
- **Forticlient**: connect and disconnect, plus launch SSH sessions and
  X-forwarded remote apps while the tunnel is up.
- **Tailscale**: connect, disconnect and log in, pick an exit node, SSH to
  peers or copy their IPs.

## Dependencies

Required:

| Package | Used for |
| --- | --- |
| `bash` 4.3+ | everything |
| `rofi` | menus and password prompts |
| `libnotify` (`notify-send`) | status and error notifications |
| `util-linux` (`setsid`) | detaching background work from the menu |
| A [Nerd Font](https://www.nerdfonts.com/) | Ethernet and Wi-Fi glyphs |

Per backend:

| Backend | Needs |
| --- | --- |
| Ethernet, Wi-Fi | NetworkManager (`nmcli`) |
| Forticlient | `openfortivpn`, `sudo`; `sshpass` for Remote Apps |
| Tailscale | `tailscale`, `jq`; `xclip` for Copy IP |
| Login/status/SSH windows | A terminal that accepts `-e <command...>` (default `kitty`) |
| `make check` | `shellcheck` |

## Installation

```sh
git clone https://github.com/michaelgilch/rofi-netmenu.git
cd rofi-netmenu
make install
```

This installs `rofi-netmenu` to `~/.local/bin` and the backends to
`~/.local/lib/rofi-netmenu`. Make sure `~/.local/bin` is on your `PATH`.

`PREFIX` and `DESTDIR` work as usual. For a system-wide install:

```sh
sudo make PREFIX=/usr/local install
```

Remove it with `make uninstall` (using the same `PREFIX`).

### Launcher entries

`make install` also writes a `.desktop` entry for the top menu and one per
backend to `~/.local/share/applications`. A launcher such as `rofi -show drun`
then finds them: type `wifi` or `tailscale` to open that menu directly, or
`netmenu` to list them all. The entries are generated at install time, so
rerun `make install` (or just `make desktop`) after adding a backend.

For development, `make link` symlinks the script from your working tree
instead. The script resolves its own symlink and loads `lib/` from the
checkout, so edits take effect immediately.

## Usage

```
rofi-netmenu [backend]
```

With no argument it opens the top-level menu. With a backend name
(`ethernet`, `wifi`, `forticlient`, `tailscale`, or any you've added) it opens
that backend directly, without a Back row. An unknown name prints the list of
installed backends.

Bind it to a key or a bar module, for example:

```
# i3 / sway
bindsym $mod+n exec --no-startup-id rofi-netmenu

# polybar
click-left = rofi-netmenu wifi
```

## Configuration

Copy the example config and edit it. Every setting is optional.

```sh
mkdir -p ~/.config/rofi-netmenu
cp config.example ~/.config/rofi-netmenu/config
```

The file is sourced as bash from `${XDG_CONFIG_HOME:-~/.config}/rofi-netmenu/config`.

| Variable | Default | Description |
| --- | --- | --- |
| `ROFI_ARGS` | | Extra flags for every rofi call, e.g. `-theme gruvbox-dark`. Split on whitespace; quotes aren't honored |
| `ON_CHANGE` | | Command run (via `bash -c`) after any state change, e.g. to refresh a bar |
| `TERMINAL` | `$TERMINAL`, then `kitty` | Terminal for login, status and SSH windows |
| `FORTI_NAME` | `Forticlient` | Name shown in the menu title, prompts and notifications |
| `FORTI_HOST` | | VPN gateway. The Forticlient menu is hidden while this is empty |
| `FORTI_PORT` | `443` | VPN gateway port |
| `FORTI_USER` | | VPN username |
| `FORTI_TRUSTED_CERT` | | Gateway certificate digest (see below) |
| `FORTI_SSH_HOST` | | Host that Remote Apps run on |
| `FORTI_SSH_USER` | | User for Remote Apps |
| `FORTI_SSH_SESSIONS` | `()` | Array of `"Name\|command\|icon"`. Commands run as-is, so include the terminal |
| `FORTI_SSH_APPS` | `()` | Array of `"Name\|command\|icon"`. Commands run on `FORTI_SSH_HOST` over `ssh -X` |
| `TS_SSH_USER` | `$USER` | User for SSH sessions to Tailscale peers |

### Forticlient sudoers rules

`openfortivpn` needs root, and the menu runs it with `sudo -n`, so it needs
passwordless sudo rules for exactly two commands. Create a drop-in with
`sudo visudo -f /etc/sudoers.d/rofi-netmenu`:

```
# Values must match your config exactly. Escape ':' and '=' with a backslash.
alice ALL=(root) NOPASSWD: /usr/bin/openfortivpn -c /dev/null vpn.example.com\:443 -u alice --trusted-cert\=0123abcd...
alice ALL=(root) NOPASSWD: /usr/bin/pkill -x openfortivpn
```

Each rule must match the command line byte for byte. The command is built
like this, with the `--trusted-cert` argument left off when
`FORTI_TRUSTED_CERT` is empty:

```
openfortivpn -c /dev/null <FORTI_HOST>:<FORTI_PORT> -u <FORTI_USER> --trusted-cert=<FORTI_TRUSTED_CERT>
```

No secret is ever part of the command, so the rule is safe to write down. The
password goes to `openfortivpn` on stdin.

**Getting the certificate digest:** if your gateway's certificate isn't
trusted by the system, run `sudo openfortivpn <host>:<port> -u <user>` once by
hand. It refuses to connect and prints the `--trusted-cert` digest to use. Put
that in `FORTI_TRUSTED_CERT` and in the sudoers rule.

### Tailscale operator

Changing Tailscale's state needs root unless your user is the tailnet
operator. If you aren't, the Tailscale menu shows a single **Grant operator
access** row, which runs `sudo tailscale set --operator=$USER` in a terminal.
You only need to do it once.

## Security notes

- Passwords never appear on a command line, where `ps` could show them.
  Wi-Fi passwords go to `nmcli --ask` on stdin, the VPN password goes to
  `openfortivpn` on stdin, and the Remote Apps SSH password goes to `sshpass -e`
  through the environment.
- `openfortivpn` runs with `-c /dev/null` so a password saved in
  `/etc/openfortivpn/config` can't override the one you typed.
- SSIDs and connection names are treated as untrusted input: they're parsed
  with escaping turned off and kept out of arithmetic contexts.

## Adding a backend

Each backend is one file in `lib/`. At startup, rofi-netmenu sources every
`lib/*.sh` except `netmenu-lib.sh`, and each backend registers itself. The
top menu and the command line are built from that registry, so adding a
backend means adding a file and nothing else. Backends don't know about each
other; they use the shared helpers in `lib/netmenu-lib.sh` to draw menus and
report results.

### The contract

A backend registers itself once, at the top of its file:

```bash
backend <name> <prefix> <order> <label> <icon>
```

- **`name`**: the command line argument, e.g. `rofi-netmenu wireguard`
- **`prefix`**: the prefix of its functions (below)
- **`order`**: its position in the top menu. The built-in backends use 10,
  20, 30 and 40, so 25 slots in between Wi-Fi and Forticlient
- **`label`**, **`icon`**: the top menu row

The config is loaded before backends are sourced, so a backend can set
defaults for its own settings, or build its label from them, at the top of
the file.

It also defines two functions:

- **`<prefix>_available`** returns success if the backend applies to this machine
  (the hardware exists, the tool is installed, the config is set). It's called
  every time the top menu is drawn, so keep it cheap.
- **`<prefix>_menu [back]`** shows the backend's menu. When it's passed an
  argument, it was opened from the top menu and should offer a Back row.
  - `return 0` goes back to the parent menu.
  - `exit 0` closes rofi-netmenu.

### Helpers

| Helper | Purpose |
| --- | --- |
| `menu_reset` | Start a new list of rows |
| `row <key> <label> [icon]` | Add a row. `key` is what `menu` returns, so you never parse labels |
| `menu <prompt>` | Show the rows and print the chosen key. Fails on Escape |
| `prompt_password <prompt>` | Masked rofi prompt. Fails on Escape or empty input |
| `notify <summary> [body] [urgency]` | Desktop notification |
| `run_bg <ok msg> <fail msg> <cmd...>` | Run a command in the background, notify the result, run `ON_CHANGE`, and close the menu |
| `on_change` | Run the user's `ON_CHANGE` hook |
| `spawn <cmd string>` | Run a user-configured command, detached |
| `terminal_run <cmd...>` | Run a command in `$TERMINAL` |
| `terminal_hold <cmd...>` | Same, but keep the window open until Enter |

All backends share one shell, so prefix your globals and functions, and
declare everything else `local`.

### Example: WireGuard

`lib/wireguard.sh`, toggling NetworkManager WireGuard profiles:

```bash
# shellcheck shell=bash
# shellcheck disable=SC2154  # globals are set in rofi-netmenu and netmenu-lib.sh
# WireGuard menu: bring NetworkManager WireGuard profiles up and down.

backend wireguard wg 35 "WireGuard" network-vpn

wg_load() {
    wg_uuid=() wg_active=() wg_name=()
    local uuid type active name
    while IFS=: read -r uuid type active name; do
        [[ $type == wireguard ]] || continue
        wg_uuid+=("$uuid")
        wg_active+=("$active")
        wg_name+=("$name")
    done < <(nmcli -t --escape no -f UUID,TYPE,ACTIVE,NAME connection show)
}

wg_available() {
    wg_load
    ((${#wg_uuid[@]} > 0))
}

wg_menu() {
    local back=${1:-} key i
    if ! wg_available; then
        notify "WireGuard" "No WireGuard profiles found"
        exit 0
    fi

    menu_reset
    for i in "${!wg_uuid[@]}"; do
        if [[ ${wg_active[i]} == yes ]]; then
            row "wg:$i" "${wg_name[i]}  ✓" network-vpn
        else
            row "wg:$i" "${wg_name[i]}" network-vpn
        fi
    done

    [[ -n $back ]] && row back "Back" go-previous
    key=$(menu "WireGuard") || exit 0
    case $key in
    back) return 0 ;;
    wg:*) wg_toggle "${key#wg:}" ;;
    esac
}

wg_toggle() {
    local i=$1 name=${wg_name[$1]}
    if [[ ${wg_active[i]} == yes ]]; then
        run_bg "$name down" "Failed to bring $name down" \
            nmcli connection down uuid "${wg_uuid[i]}"
    else
        run_bg "$name up" "Failed to bring $name up" \
            nmcli connection up uuid "${wg_uuid[i]}"
    fi
}
```

Save that as `lib/wireguard.sh` and it shows up in the menu between
Forticlient and Tailscale whenever a WireGuard profile exists. The Makefile
picks up every `lib/*.sh`, so `make install` and `make check` include it
automatically. If the backend reads any settings, document them in
`config.example`.

## Development

```
rofi-netmenu          entry point: loads config and backends, top menu, CLI
lib/netmenu-lib.sh    backend registry and shared helpers: rows, menus, prompts, notifications
lib/ethernet.sh       Ethernet backend
lib/wifi.sh           Wi-Fi backend
lib/forticlient.sh    openfortivpn backend
lib/tailscale.sh      Tailscale backend
config.example        documented example config
```

- `make link` runs the script from your checkout
- `make check` runs shellcheck over the script and all backends

## License

TODO: choose a license and add a `LICENSE` file.
