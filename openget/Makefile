# OpenGET — OSRS Grand Exchange tracker.
#
#   make            build the binary
#   make test       run the unit tests
#   make install    install binary, data, config, retro scripts and unit
#   make recipes    regenerate data/recipes.toml from live /mapping
#
# Same shape as the other hand-rolled services on this box: one binary, one systemd unit, `make && sudo make install`.

BIN      := openget
VERSION  := $(shell date -u +%Y.%m.%d)
PREFIX   ?= /usr/local
BINDIR   := $(PREFIX)/bin
LIBDIR   := $(PREFIX)/lib/openget
DATADIR  := $(PREFIX)/share/openget
CONFDIR  := /etc/openget
STATEDIR := /var/lib/openget
UNITDIR  := /etc/systemd/system

GOPHERDIR := /srv/gopher/ge
GEMINIDIR := /srv/gemini/ge
FINGERDIR := /srv/finger

# buildvcs=false: this tree is not itself a git checkout, and Go otherwise refuses to stamp the binary.
GOFLAGS := -buildvcs=false -trimpath
LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: all build test vet clean install install-retro recipes fmt

all: build

build:
	go build $(GOFLAGS) -ldflags '$(LDFLAGS)' -o $(BIN) ./cmd/openget

# install depends on the binary FILE, not on the build target. `sudo make install` would otherwise rebuild from scratch against root's cold Go cache, which takes minutes and recompiles modernc.org/sqlite for no reason. The house pattern is `make && sudo make install`.
$(BIN):
	@echo "$(BIN) not built. Run 'make' first (as your normal user)." >&2
	@false

test:
	go test $(GOFLAGS) ./...

vet:
	go vet $(GOFLAGS) ./...

fmt:
	gofmt -w cmd internal

# Regenerate the money-maker recipes against the live item mapping. Run after any game update that adds or renames items.
recipes:
	python3 contrib/gen_recipes.py > data/recipes.toml

clean:
	rm -f $(BIN)

install: $(BIN)
	install -d $(BINDIR) $(LIBDIR) $(DATADIR) $(CONFDIR) $(STATEDIR)
	install -m 0755 $(BIN) $(BINDIR)/$(BIN)
	install -m 0644 data/recipes.toml $(DATADIR)/recipes.toml
	install -m 0644 data/indices.toml $(DATADIR)/indices.toml
	install -m 0644 data/shops.toml   $(DATADIR)/shops.toml
	install -m 0644 contrib/opengetFetch.pl $(LIBDIR)/opengetFetch.pl
	# Never clobber a live config: the deployed file carries the User-Agent and the retention policy.
	[ -f $(CONFDIR)/config.toml ] || install -m 0644 contrib/config.toml $(CONFDIR)/config.toml
	install -m 0644 contrib/openget.service $(UNITDIR)/openget.service
	systemctl daemon-reload
	@echo
	@echo "Installed. Now:"
	@echo "  sudo make install-retro     # gopher/gemini/finger frontends"
	@echo "  sudo systemctl enable --now openget"

# The retro frontends touch three other services' trees, so they are a separate target: installing OpenGET should not silently rewrite the finger server's behaviour for every unknown name.
install-retro:
	install -d $(GOPHERDIR)/cgi-bin $(GEMINIDIR)/cgi-bin
	install -m 0755 contrib/gopherCgi/search $(GOPHERDIR)/cgi-bin/search
	install -m 0755 contrib/gopherCgi/item   $(GOPHERDIR)/cgi-bin/item
	install -m 0755 contrib/geminiCgi/ge     $(GEMINIDIR)/cgi-bin/ge
	install -m 0755 contrib/fingerNouser     $(FINGERDIR)/.nouser
	@echo
	@echo "Retro frontends installed. Remaining manual steps:"
	@echo "  * add a CGIPaths line for $(GEMINIDIR)/cgi-bin to"
	@echo "    /etc/molly-brown/dreamstation.conf, then restart molly-brown"
	@echo "  * confirm gophernicus is NOT started with -nx (it is not, today)"
	@echo "  * spartan needs nothing: it shares molly-brown's /srv/gemini root"
