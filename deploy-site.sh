#!/bin/bash
# Deploys this monorepo's served and installed pieces:
#
#   rootdomain/    -> /srv/http               nginx docroot (content, no executables)
#   cgi/           -> /srv/cgi                CGI scripts run by fcgiwrap
#   status-sample/ -> /usr/local/bin + units  the status page's other half
#   nginx/         -> /etc/nginx              vhosts and snippets
#
# Two carve-outs in /srv/http (excluded paths are protected from --delete):
#   .well-known/acme-challenge/   certbot webroot
#   ntpstats.txt                  written every 5 min by ntpstatsgen.timer
#
# cgi/ is a SIBLING of rootdomain/, not a subdirectory of it, so executables
# never land inside the docroot. If a location block is ever misconfigured,
# nginx has no path by which it could serve a CGI script's source. The same
# goes for status-sample/, assets-build/ and nginx/ — nothing outside
# rootdomain/ is reachable over HTTP.
#
# ORDER MATTERS. Content, then the things that read it, then nginx last: a
# vhost that references a new path should not go live before the path exists.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"

# The two trees below are NOT --delete'd into their destinations, because both
# share a directory with files this repo does not own (/usr/local/bin is full
# of other services' daemons; /etc/nginx/snippets carries Debian's own
# fastcgi-php.conf and snakeoil.conf). Managed files are listed explicitly and
# installed one at a time. Adding a file here is the only way to deploy it.
NGINX_SITES=(
	000-default-catchall
	dreamstation.systems
	grandexchange.dreamstation.systems
	pool.ntp.org
)
NGINX_SNIPPETS=(
	clacks.conf
	feeds.conf
	pgp-key.conf
	status-cgi.conf
	theme.conf
	wkd.conf
)

# --------------------------------------------------------------- syntax gates
#
# Deploy is automatic on every commit (post-commit / post-merge hooks), so a
# typo would otherwise go straight to the live site and turn the status page
# into a 502 with no warning. Abort the WHOLE deploy — content included — if
# anything fails to compile, so the site and its scripts never go out of sync.
#
# These catch compile-time errors only, not logic ones. That is the point: a
# cheap gate against the realistic failure, not a test suite. nginx gets the
# same treatment, but it cannot be tested without installing first — see the
# nginx section for how that is made safe.
if compgen -G "$ROOT/cgi/*.cgi" >/dev/null; then
	for f in "$ROOT"/cgi/*.cgi; do
		if ! perl -c "$f" >/dev/null 2>&1; then
			echo "ABORT: $(basename "$f") fails syntax check — nothing deployed." >&2
			perl -c "$f" || true # show the user why
			exit 1
		fi
	done
fi

if [ -f "$ROOT/status-sample/status-sample.sh" ]; then
	if ! bash -n "$ROOT/status-sample/status-sample.sh" 2>/dev/null; then
		echo "ABORT: status-sample.sh fails syntax check — nothing deployed." >&2
		bash -n "$ROOT/status-sample/status-sample.sh" || true
		exit 1
	fi
fi

# -------------------------------------------------------------------- content
sudo rsync -a --delete \
	--exclude '.well-known/acme-challenge/' \
	--exclude 'ntpstats.txt' \
	"$ROOT/rootdomain/" /srv/http/

# Match the rest of the served tree: root-owned, world-readable.
sudo chown -R root:root /srv/http/
sudo chmod -R u=rwX,go=rX /srv/http/

echo "Deployed rootdomain/ → /srv/http"

# ------------------------------------------------------------------------ cgi
if [ -d "$ROOT/cgi" ]; then
	sudo mkdir -p /srv/cgi
	sudo rsync -a --delete "$ROOT/cgi/" /srv/cgi/

	# Same posture as the docroot, except the execute bit must survive:
	# capital X keeps it only where it already exists, so scripts committed
	# 755 stay runnable and any stray data file does not become executable.
	sudo chown -R root:root /srv/cgi/
	sudo chmod -R u=rwX,go=rX /srv/cgi/

	echo "Deployed cgi/ → /srv/cgi"
fi

# -------------------------------------------------------------- status-sample
#
# status-sample.sh is the half of the status page that its CGI cannot do for
# itself: a rolling CPU average, root-only chronyc counters, and a month of
# disk history. Everything it writes (/run/status/*, /var/lib/status/disk.hist)
# is read by cgi/status.cgi and by nothing else, so the two are one program in
# two files and must not be deployed separately — which is why this lives here
# rather than being installed by hand.
#
# Restarting the timer is safe and cheap: it ticks every 30s, holds no state in
# memory, and its one persistent file is append-only.
if [ -d "$ROOT/status-sample" ]; then
	sample_changed=0
	units_changed=0

	if ! sudo cmp -s "$ROOT/status-sample/status-sample.sh" /usr/local/bin/status-sample.sh; then
		sudo install -m755 -o root -g root \
			"$ROOT/status-sample/status-sample.sh" /usr/local/bin/status-sample.sh
		sample_changed=1
	fi

	for u in status-sample.service status-sample.timer; do
		if ! sudo cmp -s "$ROOT/status-sample/$u" "/etc/systemd/system/$u"; then
			sudo install -m644 -o root -g root \
				"$ROOT/status-sample/$u" "/etc/systemd/system/$u"
			units_changed=1
		fi
	done

	if [ "$units_changed" = 1 ]; then
		sudo systemctl daemon-reload
	fi
	if [ "$sample_changed" = 1 ] || [ "$units_changed" = 1 ]; then
		sudo systemctl restart status-sample.timer
		echo "Deployed status-sample/ → /usr/local/bin + systemd (timer restarted)"
	fi
fi

# ---------------------------------------------------------------------- nginx
#
# Unlike everything above, nginx config CANNOT be checked before it is
# installed: the vhosts `include snippets/...` relative to nginx's own prefix,
# so a copy sitting in this repo does not resolve. The sequence is therefore
# install → test → roll back if the test fails, which leaves /etc/nginx correct
# in every outcome. The RUNNING server is never at risk: a reload happens only
# after `nginx -t` passes, and nginx keeps serving the last good config until
# then.
#
# A pre-existing failure is reported and skipped rather than "fixed", so this
# script never gets blamed for breakage it did not cause and never rolls a
# hand-edit back into a state it cannot test.
if [ -d "$ROOT/nginx" ]; then
	if ! sudo nginx -t >/dev/null 2>&1; then
		echo "SKIP: /etc/nginx is already failing nginx -t before this deploy touched it." >&2
		sudo nginx -t || true
		echo "SKIP: fix that first, then re-run $0. Content above IS deployed." >&2
		exit 1
	fi

	backup="$(mktemp -d)"
	trap 'rm -rf "$backup"' EXIT
	nginx_changed=0

	install_managed() { # <repo subdir> <etc subdir> <file>...
		local sub="$1" dest="$2" f
		shift 2
		mkdir -p "$backup/$dest"
		for f in "$@"; do
			if ! sudo cmp -s "$ROOT/nginx/$sub/$f" "/etc/nginx/$dest/$f"; then
				if [ -f "/etc/nginx/$dest/$f" ]; then
					sudo cp -p "/etc/nginx/$dest/$f" "$backup/$dest/$f"
				else
					# Absent upstream: record that, so a rollback removes
					# it rather than leaving a half-applied new vhost.
					touch "$backup/$dest/$f.ABSENT"
				fi
				sudo install -m644 -o root -g root \
					"$ROOT/nginx/$sub/$f" "/etc/nginx/$dest/$f"
				nginx_changed=1
			fi
		done
	}

	rollback() {
		local dest f
		for dest in sites-available snippets; do
			[ -d "$backup/$dest" ] || continue
			for f in "$backup/$dest"/*; do
				[ -e "$f" ] || continue
				case "$f" in
				*.ABSENT) sudo rm -f "/etc/nginx/$dest/$(basename "${f%.ABSENT}")" ;;
				*) sudo cp -p "$f" "/etc/nginx/$dest/$(basename "$f")" ;;
				esac
			done
		done
	}

	install_managed sites-available sites-available "${NGINX_SITES[@]}"
	install_managed snippets snippets "${NGINX_SNIPPETS[@]}"

	if [ "$nginx_changed" = 1 ]; then
		if sudo nginx -t >/dev/null 2>&1; then
			sudo systemctl reload nginx
			echo "Deployed nginx/ → /etc/nginx (reloaded)"
		else
			echo "ABORT: new nginx config fails nginx -t — rolling back." >&2
			sudo nginx -t || true # show the user why
			rollback
			if sudo nginx -t >/dev/null 2>&1; then
				echo "Rolled back; /etc/nginx is as it was and nginx was never reloaded." >&2
			else
				echo "ROLLBACK ALSO FAILS nginx -t. /etc/nginx needs a human." >&2
			fi
			exit 1
		fi
	fi
fi
