PREFIX ?= $(HOME)/.local
BINDIR = $(DESTDIR)$(PREFIX)/bin
LIBDIR = $(DESTDIR)$(PREFIX)/lib/rofi-netmenu
APPDIR = $(DESTDIR)$(PREFIX)/share/applications

LIBS = $(wildcard lib/*.sh)

.PHONY: install uninstall link check desktop

install: desktop
	install -Dm755 rofi-netmenu $(BINDIR)/rofi-netmenu
	install -Dm644 -t $(LIBDIR) $(LIBS)

uninstall:
	rm -f $(BINDIR)/rofi-netmenu
	rm -rf $(LIBDIR)
	rm -f $(APPDIR)/rofi-netmenu*.desktop

# Symlink the working tree for development. The script resolves its own
# symlink and finds lib/ next to it, so nothing under $(LIBDIR) is needed.
link: desktop
	rm -rf $(LIBDIR)
	mkdir -p $(BINDIR)
	ln -sfn $(CURDIR)/rofi-netmenu $(BINDIR)/rofi-netmenu

# Launcher entries for the top menu and each backend, so a drun launcher
# finds them by name or by typing "netmenu". Rerun after adding a backend.
desktop:
	install -d $(APPDIR)
	rm -f $(APPDIR)/rofi-netmenu*.desktop
	@entry() { \
		printf '%s\n' '[Desktop Entry]' 'Type=Application' "Name=$$2" \
			'GenericName=Network Menu' "Exec=$(PREFIX)/bin/rofi-netmenu$$3" \
			"Icon=$$4" "Keywords=netmenu;network;$$5" 'Categories=Network;' >"$$1"; \
		echo "wrote $$1"; \
	}; \
	entry $(APPDIR)/rofi-netmenu.desktop 'Network Menu' '' \
		preferences-system-network ''; \
	./rofi-netmenu --list | while IFS="$$(printf '\t')" read -r name label icon; do \
		entry "$(APPDIR)/rofi-netmenu-$$name.desktop" "$$label" " $$name" \
			"$$icon" "$$name;"; \
	done

check:
	shellcheck -x rofi-netmenu $(LIBS)
