#!/bin/sh
# statusExport.sh (STARPORT) — the ONLY thing the statuspull SSH key can run.
# It is the forced command in ~statuspull/.ssh/authorized_keys, so whatever
# the client asks for, it gets this: the sampler's files, framed, on stdout.
# It reads no input and takes no arguments ($SSH_ORIGINAL_COMMAND is ignored).
#
# Framing is "@@ <name>" on its own line before each file. None of the files
# can contain such a line (they are numbers, /proc/meminfo, and "p ..." rows).
#
# `now` is THIS box's clock at export time. The puller subtracts `stamp` from
# it to get the sample's age with both readings from the same clock, so clock
# skew between the two boxes cannot make fresh data look stale or vice versa.
# Not hypothetical: starport shipped with no time sync at all and was a second
# out when this was written. It runs chrony against dreamstation now, but a
# status page must not depend on the thing it might be reporting as broken.
echo "@@ now"
date +%s
for f in stamp cpu.hist meminfo uptime disk.txt; do
	[ -r "/run/status/$f" ] || continue
	echo "@@ $f"
	cat "/run/status/$f"
done
