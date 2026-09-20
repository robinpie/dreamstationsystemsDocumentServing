#!/bin/bash
# install.sh (STARPORT) — run ON starport, as root, from a directory holding
# the rest of statusSample/starport/. dreamstation's promoteSite.sh ships the
# directory over and runs this; it is idempotent and only restarts the timer
# when something actually changed. See status.txt ("The second host").
set -eu
cd "$(dirname "$0")"

# The pull account. A real shell is REQUIRED: sshd runs a forced command via
# the user's login shell, so nologin would refuse the one thing this account
# exists to do. It has no password, no sudo, and its only key is locked below.
if ! id statuspull >/dev/null 2>&1; then
	useradd --system --create-home --home-dir /var/lib/statuspull \
		--shell /bin/sh --comment "status page pull (dreamstation)" statuspull
fi

# authorized_keys is root-owned and not writable by statuspull, so the account
# cannot loosen its own restriction. `restrict` turns off forwarding, pty,
# agent, X11 and rc files in one word, including anything OpenSSH adds later.
install -d -m755 -o root -g root /var/lib/statuspull/.ssh
printf 'restrict,command="/usr/local/bin/statusExport.sh" %s\n' "$(cat statuspull.pub)" >authorized_keys.new
if ! cmp -s authorized_keys.new /var/lib/statuspull/.ssh/authorized_keys; then
	install -m644 -o root -g root authorized_keys.new /var/lib/statuspull/.ssh/authorized_keys
	echo "starport: installed statuspull authorized_keys"
fi
rm -f authorized_keys.new

changed=0
units=0
for f in statusSample.sh statusExport.sh; do
	if ! cmp -s "$f" "/usr/local/bin/$f"; then
		install -m755 -o root -g root "$f" "/usr/local/bin/$f"
		changed=1
	fi
done
for u in statusSample.service statusSample.timer; do
	if ! cmp -s "$u" "/etc/systemd/system/$u"; then
		install -m644 -o root -g root "$u" "/etc/systemd/system/$u"
		units=1
	fi
done
[ "$units" = 1 ] && systemctl daemon-reload
systemctl is-enabled --quiet statusSample.timer || systemctl enable --quiet statusSample.timer
if [ "$changed" = 1 ] || [ "$units" = 1 ] || ! systemctl is-active --quiet statusSample.timer; then
	systemctl restart statusSample.timer
	echo "starport: statusSample installed (timer restarted)"
fi
