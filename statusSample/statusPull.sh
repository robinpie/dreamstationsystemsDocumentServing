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
#   ntp.json                           starport's NTP server stats, for ntpstatsgen
#                                      (meta gains "ntp_age <s>" when present)
#   ntpprobe                           our own NTP query of starport:123, made
#                                      here, NOT over SSH (see below)
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

# ---- starport's NTP service, probed from HERE over the internet.
#
# The Services-table row for starport. The CGI may not touch the network and
# starport's own figures (ntp.json) only show that packets ARRIVE, so this is
# the one direct answer to "does it serve time": a single mode-3 client query
# to UDP/123, up to 3 tries of 1.5s. Runs BEFORE the SSH pull and is written
# whatever the pull does, because it is independent evidence — a broken SSH key
# says nothing about NTP. Uses only our clock: `at` is ours, so the CGI's age
# check needs no skew handling. One query a minute against ~6k/s is noise, and
# well inside starport's `ratelimit interval 2 burst 32`.
#
# up      = a mode-4 reply echoing our transmit timestamp, stratum 1-15
# down    = no reply / refused / stratum 16 (unsynchronised)
# unknown = could not resolve, or a kiss-o'-death (alive but refusing US,
#           which is not evidence either way about everyone else)
NTP_HOST=starport.dreamstation.systems
{
	printf 'at %s\n' "$(date +%s)"
	timeout 8 perl - "$NTP_HOST" <<'PERL' || printf 'state unknown\ndetail probe failed\n'
use strict; use warnings;
use IO::Socket::INET; use Time::HiRes ();
my $host = shift;
my $s = IO::Socket::INET->new(PeerAddr => $host, PeerPort => 123, Proto => 'udp')
	or do { print "state unknown\ndetail could not resolve $host\n"; exit 0 };
my $why = 'no reply';
for my $try (1 .. 3) {
	my $xmt = pack 'NN', int rand 2**32, int rand 2**32;
	my $t0 = Time::HiRes::time();
	$s->send(chr(0x23) . ("\0" x 39) . $xmt) or do { $why = 'send failed'; next };
	my $rin = ''; vec($rin, fileno $s, 1) = 1;
	while ((my $left = $t0 + 1.5 - Time::HiRes::time()) > 0) {
		select(my $rout = $rin, undef, undef, $left) or last;
		my $buf;
		unless (defined $s->recv($buf, 512)) { $why = 'refused'; last }
		# Only OUR reply counts: it must echo our random transmit timestamp.
		next unless length($buf) >= 48 && substr($buf, 24, 8) eq $xmt;
		my $ms = (Time::HiRes::time() - $t0) * 1000;
		my ($mode, $stratum) = (ord($buf) & 7, ord substr $buf, 1, 1);
		if ($mode == 4 && $stratum >= 1 && $stratum <= 15) {
			printf "state up\nstratum %d\nrtt_ms %.0f\n", $stratum, $ms;
		} elsif ($stratum == 0) {
			(my $code = substr $buf, 12, 4) =~ s/[^A-Z]//g;
			print "state unknown\ndetail kiss-o'-death $code\n";
		} else {
			print "state down\ndetail unsynchronised (stratum $stratum)\n";
		}
		exit 0;
	}
}
print "state down\ndetail $why\n";
PERL
} >"$work/ntpprobe"
chmod 644 "$work/ntpprobe"
mv -f "$work/ntpprobe" "$OUT/ntpprobe"

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
		if ($2 ~ /^(now|stamp|cpu\.hist|meminfo|uptime|disk\.txt|ntp\.json)$/) f = dir "/f." $2
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

# ntp.json is for ntpstatsgen, not the CGI: starport's own NTP server stats,
# collected there every 5 minutes. Its age gets the same one-clock treatment
# as the sample's (starport's `now` minus starport's collected_at), recorded
# as ntp_age. No usable ntp.json -> no ntp_age line -> ntpstatsgen shows "?"
# for starport rather than trusting whatever older copy is lying here.
ntp_age=
if [ -s "$work/f.ntp.json" ]; then
	cat=$(grep -o '"collected_at": *[0-9]\+' "$work/f.ntp.json" | head -n1 | grep -o '[0-9]\+$' || true)
	if [[ $cat =~ ^[0-9]+$ ]]; then
		ntp_age=$((rnow - cat))
		[ "$ntp_age" -lt 0 ] && ntp_age=0
		chmod 644 "$work/f.ntp.json"
		mv -f "$work/f.ntp.json" "$OUT/ntp.json"
	fi
fi

# meta LAST: it is what vouches for the files above.
{
	printf 'pulled_at %s\nsample_age %s\n' "$(date +%s)" "$age"
	[ -n "$ntp_age" ] && printf 'ntp_age %s\n' "$ntp_age"
	true
} >"$work/meta"
chmod 644 "$work/meta"
mv -f "$work/meta" "$OUT/meta"
