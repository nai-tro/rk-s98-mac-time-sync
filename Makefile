PREFIX ?= $(HOME)/.local
BINDIR ?= $(PREFIX)/bin

.PHONY: all build install uninstall clean test

all: build
build:
	mkdir -p bin
	swiftc -O Sources/rksync.swift -o bin/rksync

test:
	./bin/rksync

install:
	mkdir -p $(BINDIR)
	mkdir -p $(HOME)/Library/LaunchAgents
	swiftc -O Sources/rksync.swift -o $(BINDIR)/rksync
	chmod +x $(BINDIR)/rksync
	cp Sources/rk_s98_sync.py $(BINDIR)/rk_s98_sync.py
	chmod +x $(BINDIR)/rk_s98_sync.py
	./Scripts/create_app.sh "" "$(BINDIR)/rksync"
	launchctl unload $(HOME)/Library/LaunchAgents/com.user.rks98timesync.plist 2>/dev/null || true
	sed 's|__BIN_PATH__|$(BINDIR)/rksync|g' LaunchAgent/com.user.rks98timesync.plist > $(HOME)/Library/LaunchAgents/com.user.rks98timesync.plist
	launchctl load $(HOME)/Library/LaunchAgents/com.user.rks98timesync.plist

uninstall:
	launchctl unload $(HOME)/Library/LaunchAgents/com.user.rks98timesync.plist 2>/dev/null || true
	rm -f $(HOME)/Library/LaunchAgents/com.user.rks98timesync.plist
	rm -f $(BINDIR)/rksync
	rm -f $(BINDIR)/rk_s98_sync.py
	rm -rf "/Applications/Sync Keyboard Time.app" "$(HOME)/Applications/Sync Keyboard Time.app" "$(HOME)/Desktop/Sync Keyboard Time.app"
	rm -f /tmp/rk_s98_sync.log /tmp/rk_s98_sync.err

clean:
	rm -rf bin
