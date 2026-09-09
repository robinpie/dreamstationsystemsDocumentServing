#!/bin/bash
# Promote: takes what you have looked at on staging and makes it live.
# Run BY HAND. No git hook calls this.
#
#   /srv/httpstaging -> /srv/http           nginx docroot (content, no executables)
#   cgi/             -> /srv/cgi            CGI scripts run by fcgiwrap
#   gopher/          -> /srv/gopher         gophernicus doc root
#   gemini/          -> /srv/gemini         molly-brown doc root (Spartan too)
#   statusSample/    -> /usr/local/bin + units  the status page's other half
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
	bare-ip
	dreamstation.systems
	grandexchange.dreamstation.systems
	pool-ntp.tesla.com
	pool.ntp.org
	staging.dreamstation.systems
)
NGINX_CONFD=(
	logFormat.conf
)
NGINX_SNIPPETS=(
	accessLog.conf
	clacks.conf
	feeds.conf
	pgpKey.conf
	statusCgi.conf
	teslaNotice.conf
	theme.conf
	wkd.conf
)

# etc/ mirrors real /etc paths, installed by name like the nginx lists: these
# dirs hold files this repo does not own, so a new file does nothing until
# listed. jail.local is DELIBERATELY absent — it carries ignoreip lines with a
# home IP and an institutional range, and this repo is public. See githooks.txt
# ("promote: the rest of the tree") and fail2ban.txt.
ETC_FILES=(
	default/gophernicus
	molly-brown/dreamstation.conf
	fail2ban/filter.d/gophernicus.conf
	fail2ban/filter.d/molly-brown.conf
	logrotate.d/gophernicus
)

# ------------------------------------------------------------- staging checks
#
# Refuses the two ways staging can lie to you. See githooks.txt.
if [ ! -d "$STAGING" ] || [ -z "$(ls -A "$STAGING" 2>/dev/null)" ]; then
	echo "ABORT: $STAGING is missing or empty — run ./stageSite.sh first." >&2
	echo "Promoting it would --delete the live site." >&2
	exit 1
fi

# Uncommitted edits to rootdomain/ are not staged (the hook fires on commit),
# so what you previewed is the last commit, not your working tree. Asked of
# git rather than diffing the trees, since stageSite.sh's chown/chmod makes
# any tree-diff approach fight false positives. See githooks.txt.
dirty="$(git -C "$ROOT" status --porcelain -- rootdomain 2>/dev/null || true)"
if [ -n "$dirty" ]; then
	echo "NOTE: rootdomain/ has uncommitted changes. Staging is the last COMMIT," >&2
	echo "      so the following are NOT in it and will not go live:" >&2
	printf '%s\n' "$dirty" | sed 's/^/      /' >&2
	echo "      Commit (which re-stages), or run ./stageSite.sh by hand." >&2
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
# Repeated from stageSite.sh: a promote can happen at any distance from the
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

if [ -f "$ROOT/statusSample/statusSample.sh" ]; then
	if ! bash -n "$ROOT/statusSample/statusSample.sh" 2>/dev/null; then
		echo "ABORT: statusSample.sh fails syntax check — nothing promoted." >&2
		bash -n "$ROOT/statusSample/statusSample.sh" || true
		exit 1
	fi
fi

# etc/ gates. Unlike nginx there is no one `-t` for these, so each file gets
# the best offline check its own tool offers, BEFORE anything is installed.
# molly-brown is the one that really needs it: it has no config-test flag and
# no second instance, so a bad config is a genuine outage rather than a
# refused reload. See nginx.txt for why the nginx block cannot work this way.
if [ -d "$ROOT/etc" ]; then
	# /etc/default/gophernicus is a systemd EnvironmentFile: KEY=VALUE only.
	f="$ROOT/etc/default/gophernicus"
	if [ -f "$f" ] && grep -vE '^\s*(#|$)' "$f" | grep -qvE '^[A-Za-z_][A-Za-z0-9_]*='; then
		echo "ABORT: etc/default/gophernicus has a line that is not KEY=VALUE." >&2
		grep -vE '^\s*(#|$)' "$f" | grep -vE '^[A-Za-z_][A-Za-z0-9_]*=' | sed 's/^/      /' >&2
		exit 1
	fi

	# logrotate reads a config only if root owns it, so validate a root-owned
	# copy rather than the repo file. --debug parses and changes nothing.
	f="$ROOT/etc/logrotate.d/gophernicus"
	if [ -f "$f" ]; then
		lr_tmp="$(mktemp -d)"
		sudo install -m644 -o root -g root "$f" "$lr_tmp/lr"
		if sudo logrotate --debug "$lr_tmp/lr" 2>&1 | grep -qi '^error'; then
			echo "ABORT: etc/logrotate.d/gophernicus fails logrotate parsing." >&2
			sudo logrotate --debug "$lr_tmp/lr" 2>&1 | grep -i '^error' | sed 's/^/      /' >&2
			sudo rm -rf "$lr_tmp"
			exit 1
		fi
		sudo rm -rf "$lr_tmp"
	fi

	# molly-brown: run the real binary against the candidate config and check
	# HOW it fails. With the live instance holding :1965, a fully valid config
	# reaches "address already in use" (TOML parsed, keypair loaded, logs
	# opened). Requiring that exact message — not just a zero exit — is what
	# catches the ErrorLog="-" footgun, where errors go to a file named "-" and
	# a broken config fails silently. See gemini.txt CONFIG.
	f="$ROOT/etc/molly-brown/dreamstation.conf"
	if [ -f "$f" ] && command -v molly-brown >/dev/null 2>&1; then
		# Run it from a throwaway cwd, never the repo. An ErrorLog of "-" makes
		# molly create a file literally named "-" in the working directory, and
		# a validation step must not drop that into a git tree.
		#
		# The timeout is short and deliberate. If the service is DOWN and the
		# config is good, this probe genuinely binds :1965 and would sit there
		# serving; 3s caps how long a validation run can hold the real port.
		mb_tmp="$(mktemp -d)"
		mb_out="$(cd "$mb_tmp" && sudo timeout 3 molly-brown -c "$f" 2>&1 || true)"
		sudo rm -rf "$mb_tmp"
		if systemctl is-active --quiet molly-brown@dreamstation; then
			if ! printf '%s' "$mb_out" | grep -q 'address already in use'; then
				echo "ABORT: etc/molly-brown/dreamstation.conf did not validate." >&2
				echo "       Expected it to reach a bind conflict on the live port;" >&2
				echo "       got this instead:" >&2
				printf '%s\n' "${mb_out:-(no output — check for ErrorLog = \"-\")}" | sed 's/^/      /' >&2
				exit 1
			fi
		else
			# Service is down, so there is no port conflict to bump into and a
			# valid config would just start serving. Fall back to the weaker
			# check: it must at least not be a TOML parse error.
			if printf '%s' "$mb_out" | grep -q 'toml:'; then
				echo "ABORT: etc/molly-brown/dreamstation.conf fails to parse." >&2
				printf '%s\n' "$mb_out" | sed 's/^/      /' >&2
				exit 1
			fi
			echo "NOTE: molly-brown@dreamstation is not running, so its config got" >&2
			echo "      only a parse check, not the full startup check." >&2
		fi
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
# The two retro doc roots. Promote-only, no restart (both servers read from
# disk per request). Two carve-outs from --delete — ge/ (OpenGET's generated,
# gitignored frontend) and ntpstats.* (written by ntpstatsgen.timer) — and
# robin:robin ownership so the content stays sudo-free to edit. Full rationale
# in githooks.txt, "promote: the rest of the tree"; see also gophernicus.txt
# and gemini.txt.
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

# --------------------------------------------------------------- statusSample
#
# The other half of the status page (see status.txt); deployed alongside the
# CGI so the two never drift apart. Restarting the timer is safe and cheap.
if [ -d "$ROOT/statusSample" ]; then
	sample_changed=0
	units_changed=0

	if ! sudo cmp -s "$ROOT/statusSample/statusSample.sh" /usr/local/bin/statusSample.sh; then
		sudo install -m755 -o root -g root \
			"$ROOT/statusSample/statusSample.sh" /usr/local/bin/statusSample.sh
		sample_changed=1
	fi

	for u in statusSample.service statusSample.timer; do
		if ! sudo cmp -s "$ROOT/statusSample/$u" "/etc/systemd/system/$u"; then
			sudo install -m644 -o root -g root \
				"$ROOT/statusSample/$u" "/etc/systemd/system/$u"
			units_changed=1
		fi
	done

	if [ "$units_changed" = 1 ]; then
		sudo systemctl daemon-reload
	fi
	if [ "$sample_changed" = 1 ] || [ "$units_changed" = 1 ]; then
		sudo systemctl restart statusSample.timer
		echo "Promoted statusSample/ → /usr/local/bin + systemd (timer restarted)"
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
		for dest in conf.d sites-available snippets; do
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

	# conf.d first: it defines the log_format that the snippets below refer to,
	# and nginx resolves a format name only if it was defined earlier in the
	# parse. Install order does not set parse order (nginx.conf's includes do,
	# and conf.d/* comes before sites-enabled/* there), but keeping the two in
	# the same order means one less thing to reason about.
	install_managed conf.d conf.d "${NGINX_CONFD[@]}"
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

# ----------------------------------------------------------------------- etc/
#
# Single files across five /etc locations, all gated offline earlier. Remaining
# risk here is behavioural, not syntactic, so each service is restarted, PROBED
# over its own protocol, and rolled back if the probe fails. molly-brown's
# probe can only run post-restart (no config test, no second instance), so a
# bad config costs seconds of downtime. See githooks.txt, "promote: the rest
# of the tree".
if [ -d "$ROOT/etc" ]; then
	etc_backup="$(mktemp -d)"
	# Keeps the nginx block's backup dir in the trap too — a bare `trap ... EXIT`
	# here would REPLACE that handler and leak it.
	trap 'sudo rm -rf "$etc_backup" ${backup:+"$backup"}' EXIT
	etc_changed=()

	for rel in "${ETC_FILES[@]}"; do
		src="$ROOT/etc/$rel"
		if [ ! -f "$src" ]; then
			echo "ABORT: etc/$rel is in ETC_FILES but missing from the repo." >&2
			exit 1
		fi
		if ! sudo cmp -s "$src" "/etc/$rel"; then
			sudo mkdir -p "$etc_backup/$(dirname "$rel")"
			if sudo test -f "/etc/$rel"; then
				sudo cp -p "/etc/$rel" "$etc_backup/$rel"
			else
				# Absent upstream: record it, so a rollback removes the file
				# rather than leaving a half-applied config behind.
				sudo touch "$etc_backup/$rel.ABSENT"
			fi
			sudo install -D -m644 -o root -g root "$src" "/etc/$rel"
			etc_changed+=("$rel")
		fi
	done

	etc_did_change() { # <rel>
		local rel
		for rel in ${etc_changed[@]+"${etc_changed[@]}"}; do
			[ "$rel" = "$1" ] && return 0
		done
		return 1
	}

	etc_restore() { # <rel>...
		local rel
		for rel in "$@"; do
			if sudo test -f "$etc_backup/$rel.ABSENT"; then
				sudo rm -f "/etc/$rel"
			elif sudo test -f "$etc_backup/$rel"; then
				sudo cp -p "$etc_backup/$rel" "/etc/$rel"
			fi
		done
	}

	# Probes retry briefly: a restarted daemon is not always listening the
	# instant systemctl returns.
	probe_gopher() {
		local i
		for i in 1 2 3 4 5 6 7 8 9 10; do
			if printf '\r\n' | timeout 5 nc -w 3 localhost 70 2>/dev/null | grep -q .; then
				return 0
			fi
			sleep 0.3
		done
		return 1
	}

	probe_gemini() {
		local i
		for i in 1 2 3 4 5 6 7 8 9 10; do
			if printf 'gemini://dreamstation.systems/\r\n' |
				timeout 10 openssl s_client -quiet \
					-connect localhost:1965 -servername dreamstation.systems 2>/dev/null |
				head -1 | grep -q '^20 '; then
				return 0
			fi
			sleep 0.3
		done
		return 1
	}

	# -- gophernicus: socket-activated, so only the socket unit is restarted.
	if etc_did_change default/gophernicus; then
		sudo systemctl restart gophernicus.socket
		if probe_gopher; then
			echo "Promoted etc/default/gophernicus (gophernicus.socket restarted)"
		else
			echo "ABORT: gopher :70 stopped answering after the config change —" >&2
			echo "       rolling back and restarting." >&2
			etc_restore default/gophernicus
			sudo systemctl restart gophernicus.socket
			probe_gopher && echo "Rolled back; :70 is answering again." >&2 ||
				echo "ROLLBACK ALSO FAILS. gophernicus needs a human." >&2
			exit 1
		fi
	fi

	# -- molly-brown: a real restart, and the capsule is down while it happens.
	if etc_did_change molly-brown/dreamstation.conf; then
		sudo systemctl restart molly-brown@dreamstation
		if probe_gemini; then
			echo "Promoted etc/molly-brown/dreamstation.conf (molly-brown@dreamstation restarted)"
		else
			echo "ABORT: gemini :1965 did not come back after the config change —" >&2
			echo "       rolling back and restarting." >&2
			etc_restore molly-brown/dreamstation.conf
			sudo systemctl restart molly-brown@dreamstation
			probe_gemini && echo "Rolled back; :1965 is answering again." >&2 ||
				echo "ROLLBACK ALSO FAILS. molly-brown needs a human." >&2
			exit 1
		fi
	fi

	# -- fail2ban: the filters cannot be checked standalone because jail.local
	# is what references them (and jail.local is deliberately not in this repo).
	# So this one keeps the nginx order: install, then test the whole config.
	if etc_did_change fail2ban/filter.d/gophernicus.conf ||
		etc_did_change fail2ban/filter.d/molly-brown.conf; then
		if sudo fail2ban-client --test >/dev/null 2>&1; then
			sudo systemctl reload fail2ban
			echo "Promoted etc/fail2ban/filter.d/* (fail2ban reloaded)"
		else
			echo "ABORT: fail2ban-client --test fails with the new filters — rolling back." >&2
			sudo fail2ban-client --test 2>&1 | tail -5 | sed 's/^/      /' >&2
			etc_restore fail2ban/filter.d/gophernicus.conf fail2ban/filter.d/molly-brown.conf
			sudo fail2ban-client --test >/dev/null 2>&1 &&
				echo "Rolled back; fail2ban config is valid again (not reloaded)." >&2 ||
				echo "ROLLBACK ALSO FAILS fail2ban-client --test. Needs a human." >&2
			exit 1
		fi
	fi

	# -- logrotate: nothing runs it on our behalf and nothing needs reloading;
	# the parse gate above is the whole check.
	if etc_did_change logrotate.d/gophernicus; then
		echo "Promoted etc/logrotate.d/gophernicus"
	fi
fi
