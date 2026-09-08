#!/bin/bash
# Promote: takes what you have looked at on staging and makes it live.
# Run BY HAND. No git hook calls this.
#
#   /srv/httpstaging -> /srv/http           nginx docroot (content, no executables)
#   cgi/             -> /srv/cgi            CGI scripts run by fcgiwrap
#   gopher/          -> /srv/gopher         gophernicus doc root
#   gemini/          -> /srv/gemini         molly-brown doc root (Spartan too)
#   status-sample/   -> /usr/local/bin + units  the status page's other half
#   nginx/           -> /etc/nginx          vhosts and snippets
#
# Web content comes from the staging tree so the live docroot matches what was
# previewed; everything else comes from the repo since it has no staging copy.
# Order matters: content, then the things that read it, then nginx last.
# Full rationale in githooks.txt and nginx.txt.
set -eu

ROOT="$(cd "$(dirname "$0")" && pwd)"
STAGING=/srv/httpstaging

# Named lists, not an rsync: both destination dirs hold files this repo does
# not own. Adding a file here is the only way to deploy it. See nginx.txt.
NGINX_SITES=(
	000-default-catchall
	dreamstation.systems
	grandexchange.dreamstation.systems
	pool.ntp.org
	staging.dreamstation.systems
)
NGINX_SNIPPETS=(
	clacks.conf
	feeds.conf
	pgp-key.conf
	status-cgi.conf
	theme.conf
	wkd.conf
)

# ------------------------------------------------------------- staging checks
#
# Refuses the two ways staging can lie to you. See githooks.txt.
if [ ! -d "$STAGING" ] || [ -z "$(ls -A "$STAGING" 2>/dev/null)" ]; then
	echo "ABORT: $STAGING is missing or empty — run ./stage-site.sh first." >&2
	echo "Promoting it would --delete the live site." >&2
	exit 1
fi

# Uncommitted edits to rootdomain/ are not staged (the hook fires on commit),
# so what you previewed is the last commit, not your working tree. Asked of
# git rather than diffing the trees, since stage-site.sh's chown/chmod makes
# any tree-diff approach fight false positives. See githooks.txt.
dirty="$(git -C "$ROOT" status --porcelain -- rootdomain 2>/dev/null || true)"
if [ -n "$dirty" ]; then
	echo "NOTE: rootdomain/ has uncommitted changes. Staging is the last COMMIT," >&2
	echo "      so the following are NOT in it and will not go live:" >&2
	printf '%s\n' "$dirty" | sed 's/^/      /' >&2
	echo "      Commit (which re-stages), or run ./stage-site.sh by hand." >&2
	if [ ! -t 0 ]; then
		echo "ABORT: not a terminal, cannot ask. Nothing promoted." >&2
		exit 1
	fi
	printf 'Promote staging as it is anyway? [y/N] ' >&2
	read -r reply
	case "$reply" in
	[yY]*) ;;
	*)
		echo "Nothing promoted." >&2
		exit 1
		;;
	esac
fi

# --------------------------------------------------------------- syntax gates
#
# Repeated from stage-site.sh: a promote can happen at any distance from the
# commit that staged it, so this has to hold at the moment things go live.
if compgen -G "$ROOT/cgi/*.cgi" >/dev/null; then
	for f in "$ROOT"/cgi/*.cgi; do
		if ! perl -c "$f" >/dev/null 2>&1; then
			echo "ABORT: $(basename "$f") fails syntax check — nothing promoted." >&2
			perl -c "$f" || true # show the user why
			exit 1
		fi
	done
fi

if [ -f "$ROOT/status-sample/status-sample.sh" ]; then
	if ! bash -n "$ROOT/status-sample/status-sample.sh" 2>/dev/null; then
		echo "ABORT: status-sample.sh fails syntax check — nothing promoted." >&2
		bash -n "$ROOT/status-sample/status-sample.sh" || true
		exit 1
	fi
fi

# -------------------------------------------------------------------- content
sudo rsync -a --delete \
	--exclude '.well-known/acme-challenge/' \
	--exclude 'ntpstats.txt' \
	"$STAGING/" /srv/http/

# Match the rest of the served tree: root-owned, world-readable.
sudo chown -R root:root /srv/http/
sudo chmod -R u=rwX,go=rX /srv/http/

echo "Promoted $STAGING → /srv/http"

# ------------------------------------------------------------------------ cgi
if [ -d "$ROOT/cgi" ]; then
	sudo mkdir -p /srv/cgi
	sudo rsync -a --delete "$ROOT/cgi/" /srv/cgi/

	# Same posture as the docroot, except the execute bit must survive:
	# capital X keeps it only where it already exists, so scripts committed
	# 755 stay runnable and any stray data file does not become executable.
	sudo chown -R root:root /srv/cgi/
	sudo chmod -R u=rwX,go=rX /srv/cgi/

	echo "Promoted cgi/ → /srv/cgi"
fi

# ------------------------------------------------------------- gopher, gemini
#
# The two retro doc roots. Promote-only, like everything below the web content:
# there is one gophernicus and one molly-brown on this box and no second
# instance for a change to stand up in, so "staged" and "live" would be the
# same tree. See gophernicus.txt and gemini.txt.
#
# NO RESTART IS NEEDED and none is issued. gophernicus is socket-activated
# per connection, molly-brown reads from disk per request, and spartan.pl
# (which shares /srv/gemini) does too. Content is live the moment rsync
# finishes.
#
# THE TWO CARVE-OUTS, and why --delete would otherwise be destructive:
#
#   ge/          OpenGET's retro frontend. The openget daemon rewrites ~50
#                files under it after every stats recomputation and owns the
#                dirs as openget:openget; `make install-retro` puts the
#                cgi-bin/ scripts there. It is generated, not authored, so it
#                is gitignored and absent from this repo -- and an unexcluded
#                --delete would wipe it between regenerations. Excluding it
#                also protects it from the ownership note below, since
#                openget writes atomically (temp file + rename) and so needs
#                write access to the DIRECTORY, not just the files.
#
#   ntpstats.*   written every 5 min by ntpstatsgen.timer straight into both
#                doc roots. Same carve-out /srv/http/ntpstats.txt gets above.
#
# rsync excludes protect receiver-side files from --delete (that is the
# default; only --delete-excluded overrides it), which is exactly what both
# of these need.
#
# OWNERSHIP is deliberately NOT the root:root the web docroot gets. These
# trees are robin:robin so the content can be edited without sudo, and -a
# preserves that from the repo. --chmod normalises the repo's group-writable
# 664/775 to the 644/755 the doc roots have always carried; both leave every
# file world-readable, which is what lets _gophernicus and molly-brown's
# DynamicUser read them.
promote_retro() { # <repo subdir> <doc root> <generated file to protect>
	local sub="$1" dest="$2" generated="$3"
	[ -d "$ROOT/$sub" ] || return 0
	sudo rsync -a --delete \
		--chmod=D755,F644 \
		--exclude 'ge/' \
		--exclude "$generated" \
		"$ROOT/$sub/" "$dest/"
	echo "Promoted $sub/ → $dest"
}

promote_retro gopher /srv/gopher ntpstats.txt
promote_retro gemini /srv/gemini ntpstats.gmi

# -------------------------------------------------------------- status-sample
#
# The other half of the status page (see status.txt); deployed alongside the
# CGI so the two never drift apart. Restarting the timer is safe and cheap.
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
		echo "Promoted status-sample/ → /usr/local/bin + systemd (timer restarted)"
	fi
fi

# ---------------------------------------------------------------------- nginx
#
# Unlike everything above, nginx config can't be syntax-checked before it's
# installed, so the sequence here is install -> `nginx -t` -> roll back on
# failure. A pre-existing failure is reported and skipped, not "fixed". See
# nginx.txt.
if [ -d "$ROOT/nginx" ]; then
	if ! sudo nginx -t >/dev/null 2>&1; then
		echo "SKIP: /etc/nginx is already failing nginx -t before this promote touched it." >&2
		sudo nginx -t || true
		echo "SKIP: fix that first, then re-run $0. Content above IS live." >&2
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
			echo "Promoted nginx/ → /etc/nginx (reloaded)"
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
