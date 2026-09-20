#!/bin/bash
# statusSample.sh (STARPORT) — collects host vitals on starport for the status
# page served by dreamstation. Runs every 30s via statusSample.timer.
#
# This is the remote half of a pull: NOTHING here talks to the network.
# dreamstation's statusPull.timer SSHes in as the `statuspull` user, whose key
# is locked to statusExport.sh, and reads what this writes. See status.txt on
# dreamstation ("The second host") for the design.
#
# THE FILE FORMATS ARE A CONTRACT with cgi/status.cgi, which parses them with
# the same readers it uses for dreamstation's own files. cpu.hist and disk.txt
# are byte-for-byte the format ../statusSample.sh writes; if you change one
# sampler's format, change the other and the CGI together.
#
# Output, all world-readable:
#   /run/status/cpu.hist      "<ts> <total_jiffies> <idle_jiffies>", 5min kept
#   /run/status/disk.txt      current disk figures + a downsampled 30d series
#   /run/status/meminfo       verbatim copy of /proc/meminfo
#   /run/status/uptime        verbatim copy of /proc/uptime
#   /run/status/stamp         epoch of this sample, by THIS box's clock
#   /var/lib/status/disk.hist THE ONE PERSISTENT FILE. Append-only, forever.
#
# meminfo and uptime are verbatim snapshots rather than condensed figures so
# that the CGI's read_mem()/read_uptime() work on them unchanged — the htop
# accounting lives in exactly one place. dreamstation's sampler has no such
# files because its CGI reads /proc directly.
set -eu

CPU_HIST=/run/status/cpu.hist
WINDOW=300 # seconds of CPU history to retain

DISK_HIST=/var/lib/status/disk.hist
DISK_OUT=/run/status/disk.txt
DISK_FS=/
DISK_INTERVAL=300     # seconds between disk samples (this timer ticks at 30s)
DISK_WINDOW=2592000   # 30 days, the span the status page graphs
DISK_STEP=7200        # 2h buckets -> at most 360 plotted points
DISK_TAIL=12000       # lines scanned to build those buckets (~41 days at 5min)

mkdir -p /run/status

now=$(date +%s)

# put <name>: stdin -> /run/status/<name>, atomically, world-readable.
put() {
	local tmp
	tmp=$(mktemp "/run/status/.$1.XXXXXX")
	cat >"$tmp"
	chmod 644 "$tmp"
	mv -f "$tmp" "/run/status/$1"
}

# ---------------------------------------------------------------- CPU sample
#
# idle = idle + iowait: the bar measures CPU *executing*. Same definition as
# dreamstation's sampler, so the two CPU bars mean the same thing.
read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
total=$((user + nice + system + idle + iowait + irq + softirq + steal))
idle_all=$((idle + iowait))

{
	[ -f "$CPU_HIST" ] && awk -v cutoff="$((now - WINDOW))" '$1 >= cutoff' "$CPU_HIST"
	echo "$now $total $idle_all"
} | put cpu.hist

# ------------------------------------------------------- memory and uptime
put meminfo </proc/meminfo
put uptime </proc/uptime

# -------------------------------------------------------------- disk usage
#
# Identical to dreamstation's disk block; see status.txt there for max-vs-mean
# bucketing, the two timestamps per point, and why keeping the history forever
# is safe (~4MB/year).
mkdir -p "$(dirname "$DISK_HIST")"

disk_last=0
if [ -s "$DISK_HIST" ]; then
	disk_last=$(tail -n 1 "$DISK_HIST" | cut -d' ' -f1)
	case $disk_last in '' | *[!0-9]*) disk_last=0 ;; esac
fi

if [ $((now - disk_last)) -ge "$DISK_INTERVAL" ] || [ ! -f "$DISK_OUT" ]; then
	if disk=$(df -P -k "$DISK_FS" 2>/dev/null | awk 'NR==2 {print $2, $3, $4}') && [ -n "$disk" ]; then
		read -r d_total d_used d_avail <<<"$disk"
		if [[ $d_total =~ ^[0-9]+$ && $d_used =~ ^[0-9]+$ && $d_avail =~ ^[0-9]+$ && $d_total -gt 0 ]]; then
			if [ $((now - disk_last)) -ge "$DISK_INTERVAL" ]; then
				echo "$now $d_used $d_total $d_avail" >>"$DISK_HIST"
				chmod 644 "$DISK_HIST" 2>/dev/null || true
			fi

			disk_cut=$((now - DISK_WINDOW))
			if series=$(tail -n "$DISK_TAIL" "$DISK_HIST" 2>/dev/null | awk \
				-v cut="$disk_cut" -v step="$DISK_STEP" '
				$1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ && $1 >= cut {
					b = int($1 / step) * step
					if (!(b in m) || $2 + 0 > m[b]) { m[b] = $2 + 0; t[b] = $1 + 0 }
				}
				END { for (b in m) printf "p %d %d %d\n", b, t[b], m[b] }
			' | sort -n -k2); then
				{
					echo "sampled_at $now"
					echo "used $d_used"
					echo "total $d_total"
					echo "avail $d_avail"
					echo "window $DISK_WINDOW"
					echo "step $DISK_STEP"
					head -n 1 "$DISK_HIST" | awk '$1 ~ /^[0-9]+$/ {print "first_ts", $1}'
					echo "$series"
				} | put disk.txt
			fi
		fi
	fi
fi

# LAST, so a stamp never vouches for files that were not written: set -e
# means any failure above exits before this line. The puller turns it into a
# sample age — see statusExport.sh.
echo "$now" | put stamp
