#!/bin/bash
# status-sample.sh — collects the CPU, NTS-KE and disk figures status.cgi
# cannot get for itself (it runs unprivileged, per request). Runs every 30s
# via status-sample.timer. See status.txt for the full rationale.
#
# Output, all world-readable:
#   /run/status/cpu.hist      "<ts> <total_jiffies> <idle_jiffies>", 5min kept
#   /run/status/chrony.txt    "<key> <value>" lines, latest snapshot only
#   /run/status/qps.txt       three condensed NTP rate figures
#   /run/status/disk.txt      current disk figures + a downsampled 30d series
#   /var/lib/status/disk.hist THE ONE PERSISTENT FILE. Append-only, forever.
#
# Everything else is tmpfs, cleared on reboot; disk.hist is the one exception
# and lives in the state directory instead — see the disk block below.
set -eu

CPU_HIST=/run/status/cpu.hist
CHRONY_OUT=/run/status/chrony.txt
QPS_OUT=/run/status/qps.txt
QPS_HIST=/var/lib/dashboard/ntp_qps.hist
WINDOW=300 # seconds of CPU history to retain

# Disk. Unlike everything else here the history is PERSISTENT and kept forever,
# so it lives in the state directory rather than on tmpfs — see the disk block
# at the bottom of this file for the size arithmetic.
DISK_HIST=/var/lib/status/disk.hist
DISK_OUT=/run/status/disk.txt
DISK_FS=/
DISK_INTERVAL=300     # seconds between disk samples (this timer ticks at 30s)
DISK_WINDOW=2592000   # 30 days, the span the status page graphs
DISK_STEP=7200        # 2h buckets -> at most 360 plotted points
DISK_TAIL=12000       # lines scanned to build those buckets (~41 days at 5min)

# systemd-tmpfiles creates /run/status at boot; create it here too so a manual
# run before the first tmpfiles pass still works.
mkdir -p /run/status

now=$(date +%s)

# ---------------------------------------------------------------- CPU sample
#
# /proc/stat's first line: cpu user nice system idle iowait irq softirq steal
# guest guest_nice. total = every field; idle = idle + iowait (measures CPU
# *executing*, not "unable to schedule" — see status.txt).
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_all=$((idle + iowait))

# Append, then keep only samples inside the window. Written via a temp file
# and renamed so the CGI never reads a half-written history.
tmp=$(mktemp /run/status/.cpu.XXXXXX)
{
	[ -f "$CPU_HIST" ] && awk -v cutoff="$((now - WINDOW))" '$1 >= cutoff' "$CPU_HIST"
	echo "$now $total $idle_all"
} >"$tmp"
chmod 644 "$tmp"
mv -f "$tmp" "$CPU_HIST"

# ------------------------------------------------------------- chrony sample
#
# `chronyc -c serverstats` emits one CSV row (chrony 4.x field order):
#   1 NTP packets received      2 NTP packets dropped
#   3 Command packets received  4 Command packets dropped
#   5 Client log records dropped
#   6 NTS-KE connections accepted   <-- wanted
#   7 NTS-KE connections dropped    <-- wanted
#   8 Authenticated NTP packets     ...timestamp counters follow
#
# If chronyd is down or the call is refused, leave the previous snapshot in
# place rather than writing zeros — sampled_at is how the CGI tells stale from
# genuinely-zero.
if stats=$(timeout 5 /usr/bin/chronyc -c serverstats 2>/dev/null) && [ -n "$stats" ]; then
	IFS=, read -r _ _ _ _ _ nts_accepted nts_dropped _ <<<"$stats"
	# Guard against chronyc emitting an error string where a number belongs —
	# a bug that has bitten this box before (see ntpset.txt).
	if [[ $nts_accepted =~ ^[0-9]+$ && $nts_dropped =~ ^[0-9]+$ ]]; then
		tmp=$(mktemp /run/status/.chrony.XXXXXX)
		{
			echo "sampled_at $now"
			echo "nts_ke_accepted $nts_accepted"
			echo "nts_ke_dropped $nts_dropped"
		} >"$tmp"
		chmod 644 "$tmp"
		mv -f "$tmp" "$CHRONY_OUT"
	fi
fi

# ---------------------------------------------------------------- NTP rates
#
# Condenses /var/lib/dashboard/ntp_qps.hist (~95k lines, appended every 5s by
# ntp-qps-sample.service) down to three numbers — see status.txt for why this
# lives here instead of the CGI, and for the reset-handling rationale below.
# A decrease between consecutive samples starts a new averaging window.
if [ -r "$QPS_HIST" ]; then
	if qps=$(awk '
		{
			ts = $1; pkts = $2
			if (pkts !~ /^[0-9]+$/) next
			if (!have || pkts < prev) { win_ts = ts; win_pkts = pkts; have = 1 }
			prev = pkts
			# keep the trailing pair for the instantaneous rate
			p_ts = l_ts; p_pkts = l_pkts
			l_ts = ts;   l_pkts = pkts
		}
		END {
			if (!have) exit 1
			span = l_ts - win_ts
			if (span > 0) printf "avg %.2f\navg_span %d\n", (l_pkts - win_pkts) / span, span
			dt = l_ts - p_ts
			if (dt > 0 && l_pkts >= p_pkts) printf "now %.2f\n", (l_pkts - p_pkts) / dt
		}
	' "$QPS_HIST" 2>/dev/null) && [ -n "$qps" ]; then
		tmp=$(mktemp /run/status/.qps.XXXXXX)
		{
			echo "sampled_at $now"
			echo "$qps"
		} >"$tmp"
		chmod 644 "$tmp"
		mv -f "$tmp" "$QPS_OUT"
	fi
fi

# -------------------------------------------------------------- disk usage
#
# Two outputs with different lifetimes: disk.hist is persistent and kept
# forever ("<ts> <used_kb> <total_kb> <avail_kb>"); disk.txt is tmpfs,
# rewritten each sample with current figures plus a downsampled 30-day
# series. See status.txt for the size arithmetic and why this is safe.
#
# The 5-minute cadence is enforced here rather than by a second timer, and is
# measured from the last line of the persistent history so a reboot resumes
# it correctly instead of restarting it.
mkdir -p "$(dirname "$DISK_HIST")"

disk_last=0
if [ -s "$DISK_HIST" ]; then
	disk_last=$(tail -n 1 "$DISK_HIST" | cut -d' ' -f1)
	case $disk_last in '' | *[!0-9]*) disk_last=0 ;; esac
fi

# The -f test regenerates the condensed file after a reboot has wiped tmpfs,
# even when the next sample is not due yet, so the page is never blank for up
# to five minutes just because the box restarted.
if [ $((now - disk_last)) -ge "$DISK_INTERVAL" ] || [ ! -f "$DISK_OUT" ]; then
	# -P forces the POSIX one-line-per-filesystem format: without it a long
	# device name wraps onto its own line and the fields shift. -k fixes the
	# unit at 1KiB blocks regardless of the caller's environment.
	#
	# Note df's Used + Available does NOT equal Size: ext4 reserves ~5% for
	# root. All three are stored, so the page can show that reserve as its own
	# segment instead of pretending the gap is free space.
	if disk=$(df -P -k "$DISK_FS" 2>/dev/null | awk 'NR==2 {print $2, $3, $4}') && [ -n "$disk" ]; then
		read -r d_total d_used d_avail <<<"$disk"
		if [[ $d_total =~ ^[0-9]+$ && $d_used =~ ^[0-9]+$ && $d_avail =~ ^[0-9]+$ && $d_total -gt 0 ]]; then
			# Only append when a sample is actually due. The -f branch above
			# rebuilds the condensed file from existing history without
			# polluting it with an off-cadence extra row.
			if [ $((now - disk_last)) -ge "$DISK_INTERVAL" ]; then
				echo "$now $d_used $d_total $d_avail" >>"$DISK_HIST"
				chmod 644 "$DISK_HIST" 2>/dev/null || true
			fi

			# Downsample to one point per DISK_STEP, taking the MAXIMUM used in
			# each bucket (see status.txt for max-vs-mean and the tail-before-awk
			# cost rationale). Each point is "p <bucket> <ts> <used_kb>":
			#
			#   bucket  a regular 2h grid, so the CGI can tell a missing bucket
			#           from a present one and break the line on real gaps.
			#   ts      the actual time of the peak sample, for where to plot
			#           the point — the bucket floor alone can misplace it by
			#           up to 2h, most of the width on a short history.
			disk_cut=$((now - DISK_WINDOW))
			if series=$(tail -n "$DISK_TAIL" "$DISK_HIST" 2>/dev/null | awk \
				-v cut="$disk_cut" -v step="$DISK_STEP" '
				$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 >= cut {
					b = int($1 / step) * step
					if (!(b in m) || $2 + 0 > m[b]) { m[b] = $2 + 0; t[b] = $1 + 0 }
				}
				END { for (b in m) printf "p %d %d %d\n", b, t[b], m[b] }
			' | sort -n -k2); then
				tmp=$(mktemp /run/status/.disk.XXXXXX)
				{
					echo "sampled_at $now"
					echo "used $d_used"
					echo "total $d_total"
					echo "avail $d_avail"
					echo "window $DISK_WINDOW"
					echo "step $DISK_STEP"
					# first_ts lets the page say "history began N ago" instead
					# of implying a full month of data it does not have yet.
					head -n 1 "$DISK_HIST" | awk '$1 ~ /^[0-9]+$/ {print "first_ts", $1}'
					echo "$series"
				} >"$tmp"
				chmod 644 "$tmp"
				mv -f "$tmp" "$DISK_OUT"
			fi
		fi
	fi
fi
