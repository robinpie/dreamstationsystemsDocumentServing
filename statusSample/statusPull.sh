#!/bin/bash
# statusPull.sh — fetches starport's vitals for status.cgi. Runs every 60s via
# statusPull.timer as the unprivileged `statuspull` user. See status.txt
# ("The second host").
#
# One SSH connection, whose key is locked on the far side to statusExport.sh:
# it can print the sampler's files and nothing else. The CGI never does this
# itself — an SSH handshake on the request path would wreck the cost budget
# the whole page is built around — it only reads what this leaves in tmpfs.
#
# Output, /run/status/starport/:
#   cpu.hist meminfo uptime disk.txt   as written by starport's sampler
#   meta                               "pulled_at <epoch, OUR clock>"
#                                      "sample_age <s>"  age of the sample at
#                                      the moment of export, by STARPORT's
#                                      clock on both sides of the subtraction
#
# The CGI's age for the data is (now - pulled_at) + sample_age. Each term is a
# difference of two readings of ONE clock, so skew between the boxes cancels.
#
# ON ANY FAILURE NOTHING IS WRITTEN. The previous files stay, meta keeps its
# old pulled_at, and the page ages them into "unknown" by itself. There is no
# failure path here that can make old data look new.
set -euo pipefail

HOST=statuspull@starport.dreamstation.systems
KEY=/var/lib/statuspull/.ssh/id_ed25519
KNOWN=/var/lib/statuspull/.ssh/known_hosts
OUT=/run/status/starport
MAX=262144 # bytes accepted; real output is ~6KB

[ -d "$OUT" ] || { echo "statusPull: $OUT missing (tmpfiles.d/statusPull.conf)" >&2; exit 1; }

work=$(mktemp -d "$OUT/.pull.XXXXXX")
trap 'rm -rf "$work"' EXIT

# StrictHostKeyChecking=yes against a pinned known_hosts: a changed host key
# fails the pull (-> "unknown" on the page) rather than being trusted. The
# remote command is ignored by the forced command; "export" is for the logs.
timeout 20 ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes \
	-o UserKnownHostsFile="$KNOWN" -o StrictHostKeyChecking=yes \
	-o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
	"$HOST" export 2>"$work/err" | head -c "$MAX" >"$work/raw" || {
	echo "statusPull: ssh failed: $(tr '\n' ' ' <"$work/err")" >&2
	exit 1
}

# Split on the "@@ <name>" frames. The name is matched against a fixed list,
# never used as given: the far side is ours, but a path from the network does
# not get to choose where a file lands.
awk -v dir="$work" '
	/^@@ / {
		f = ""
		if ($2 ~ /^(now|stamp|cpu\.hist|meminfo|uptime|disk\.txt)$/) f = dir "/f." $2
		next
	}
	f != "" { print > f }
' "$work/raw"

rnow=$(head -n1 "$work/f.now" 2>/dev/null || true)
stamp=$(head -n1 "$work/f.stamp" 2>/dev/null || true)
if ! [[ $rnow =~ ^[0-9]+$ && $stamp =~ ^[0-9]+$ ]]; then
	echo "statusPull: export had no usable now/stamp" >&2
	exit 1
fi
age=$((rnow - stamp))
[ "$age" -lt 0 ] && age=0

for f in cpu.hist meminfo uptime disk.txt; do
	[ -s "$work/f.$f" ] || continue
	chmod 644 "$work/f.$f"
	mv -f "$work/f.$f" "$OUT/$f"
done

# meta LAST: it is what vouches for the files above.
printf 'pulled_at %s\nsample_age %s\n' "$(date +%s)" "$age" >"$work/meta"
chmod 644 "$work/meta"
mv -f "$work/meta" "$OUT/meta"
