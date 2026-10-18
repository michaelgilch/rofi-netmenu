PREFIX ?= /usr/local
BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/rofi-netmenu

LIBS = lib/netmenu-lib.sh lib/ethernet.sh lib/wifi.sh lib/forticlient.sh lib/tailscale.sh

.PHONY: install uninstall link check

install:
	install -Dm755 rofi-netmenu $(BINDIR)/rofi-netmenu
	install -Dm644 -t $(LIBDIR) $(LIBS)

uninstall:
	rm -f $(BINDIR)/rofi-netmenu
	rm -rf $(LIBDIR)

# Symlink the working tree for development. The script resolves its own
# symlink and finds lib/ next to it, so nothing under $(LIBDIR) is needed.
link:
	rm -rf $(LIBDIR)
	mkdir -p $(BINDIR)
	ln -sfn $(CURDIR)/rofi-netmenu $(BINDIR)/rofi-netmenu

check:
	shellcheck -x rofi-netmenu $(LIBS)
