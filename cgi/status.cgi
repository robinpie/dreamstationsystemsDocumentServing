#!/usr/bin/perl
#
# status.cgi — live service status for dreamstation.systems
#
# Deployed to /srv/cgi/status.cgi by promote-site.sh; served at /professional/status via fcgiwrap. Runs as www-data.
#
# Warning for very claudish comments lol.
#
# See ~/configNotes/status.txt for the whole design. The three things most
# likely to trip up an editor:
#
#   1. EVERY PROBE IS A REAL PROTOCOL EXCHANGE, not a systemd state check.
#      `systemctl is-active` is actively wrong for two services here: Gopher
#      is socket-activated (the service unit is per-connection and normally
#      absent, so you must check gophernicus.socket) and Gemini is templated
#      (molly-brown@dreamstation.service). Unit state is reported alongside
#      the probe, never instead of it.
#
#   2. TWO PROBES HAVE NON-OBVIOUS REQUIREMENTS, both found by measurement:
#      - HTTP must send a Host header. Without one, nginx's 000-default
#        catchall matches and returns 444 (drops the connection), so our own
#        web server reads as DOWN on its own status page.
#      - TLS ports (1965, 4460) must complete a handshake. A read-a-byte
#        probe blocks until timeout because the server is waiting for a
#        ClientHello — :4460 cost 2000ms and still reported DOWN.
#
#   3. THE CACHE IS THE COST BOUND. A full sweep is ~640ms of a single vCPU,
#      and chronyd needs that core. The cache means at most one sweep per
#      CACHE_TTL regardless of request rate, so a link aggregator cannot turn
#      this page into an outage of the NTP service it exists to advertise.

use strict;
use warnings;

# NOTHING BUT strict AND warnings IS LOADED HERE, on purpose. Every module
# this script uses is require'd at its point of use instead, because each is
# expensive to compile and most requests need none of them. See status.txt
# ("Cost and the cache") for the measured costs. If you add a `use` at the
# top of this file, measure it first.

# Sub-second timing, loaded on demand — only the sweep path needs it. Code
# outside the sweep keeps using CORE::time (whole seconds), so nothing
# silently changes meaning. See status.txt.
my $HIRES;
sub hnow {
	$HIRES ||= do { require Time::HiRes; 1 };
	return Time::HiRes::time();
}

# ---------------------------------------------------------------- constants

use constant {
	CACHE       => '/run/status/cache.txt',
	CPU_HIST    => '/run/status/cpu.hist',
	CHRONY_SNAP => '/run/status/chrony.txt',
	QPS_SNAP    => '/run/status/qps.txt',
	DISK_SNAP   => '/run/status/disk.txt',
	SEEN_SET    => '/var/lib/dashboard/ntp_clients_seen.bin',

	CACHE_TTL      => 20,    # seconds a rendered sweep stays authoritative
	SWEEP_DEADLINE => 8,     # give up starting new probes after this
	TCP_TIMEOUT    => 1.5,   # per plain probe (measured max on loopback: 281ms)
	TLS_TIMEOUT    => 2.5,   # per TLS handshake (measured: ~90ms)
	STALE_WARN     => 120,   # cache older than this gets a visible banner

	POOL_URL => 'https://www.ntppool.org/scores/67.215.249.229',
};

# Disk graph geometry, in user units of a fixed viewBox. The rendered SVG is
# width:100% / height:auto, so these are proportions rather than pixels — but
# text inside an SVG scales with it, so the numbers are chosen to keep the
# labels legible at the ~340px this gets on a phone rather than only at 720.
use constant {
	G_W => 720, G_H => 180,
	G_L => 54,   # left gutter: wide enough for "19.0 GB"
	G_R => 10,
	G_T => 12,
	G_B => 24,   # bottom strip for the two date labels
};

# Hover titles for the bar segments: the exact quantity each is computed from.
# Defined once because both render paths (full page and corner box fragment)
# use them. These are title attributes on aria-hidden elements — a mouse
# affordance, not a text alternative. See status.txt ("Segment hover titles").
use constant {
	T_CPU        => '1 − Δ(idle + iowait) / Δtotal over the sampled window',
	T_MEM_USED   => 'MemTotal − MemFree − cache',
	T_MEM_CACHE  => 'cache',
	T_SWAP_USED  => 'SwapTotal − SwapFree − SwapCached',
	T_SWAP_CACHE => 'SwapCached',
	T_DISK_USED  => 'df Used',
	T_DISK_RSVD  => 'Unused root reserve',
};

# Probes run against loopback deliberately, so they never pollute the access
# log dashboard parses. See status.txt.
use constant HOST => '127.0.0.1';

# id, label, port, probe type, systemd unit to report alongside, note
#
# The port here is WHAT WE PROBE, not "where the service is". It is never shown
# to the reader — see the note in render() — because for several rows the probed
# port is only one of the ways in. Pick whichever port gives the cheapest honest
# answer for the service as a whole.
my @SERVICES = (
	[ 'time',    'Time (NTP / NTS)', 4460, 'tls',   'chrony.service',                 'NTP on 123/udp, NTS-KE on 4460/tcp' ],
	[ 'web',     'Web',              80,   'http',  'nginx.service',                  'HTTP and HTTPS'                     ],
	[ 'gopher',  'Gopher',           70,   'line',  'gophernicus.socket',             'socket‐activated'                   ],
	[ 'gemini',  'Gemini',           1965, 'tls',   'molly-brown@dreamstation.service', ''                                 ],
	[ 'spartan', 'Spartan',          300,  'req',   'spartan.service',                ''                                   ],
	[ 'finger',  'Finger',           79,   'line',  'finger.service',                 ''                                   ],
	[ 'dict',    'Dictionary (DICT)',2628, 'banner','dictd.service',                  ''                                   ],
	[ 'ftp',     'FTP archive',      21,   'banner','vsftpd.service',                 ''                                   ],
	[ 'mail',    'Mail',             25,   'banner','postfix.service',                'SMTP, submission, IMAP'             ],
	[ 'openget', 'OpenGET',          4151, 'http',  'openget.service',                'grandexchange.dreamstation.systems' ],
	[ 'qotd',    'Quote of the Day', 17,   'banner','qotd.service',                   'RFC 865'                            ],
	[ 'daytime', 'Daytime',          13,   'banner','daytime.service',                'RFC 867'                            ],
	[ 'echo',    'Echo',             7,    'echo',  'echo.service',                   'RFC 862'                            ],
	[ 'discard', 'Discard',          9,    'sink',  'discard.service',                'RFC 863'                            ],
	[ 'chargen', 'Character Generator', 19,'banner','chargen.service',                'RFC 864'                            ],
);

# ------------------------------------------------------------------- probes

# Returns (state, detail). state is one of up / down / unknown.
sub probe_tcp {
	my ($port, $kind) = @_;
	my $t0 = hnow();

	# Lazy — see the note at the top of the file. Unlike the SSL case this one
	# is not optional: without sockets there are no probes at all, so a failure
	# here is fatal to the sweep rather than to one row.
	require IO::Socket::INET;

	my $sock = IO::Socket::INET->new(
		PeerAddr => HOST, PeerPort => $port,
		Proto    => 'tcp', Timeout  => TCP_TIMEOUT,
	);
	return ('down', 'connection refused') unless $sock;

	$sock->autoflush(1);
	my $ok = 0;
	eval {
		local $SIG{ALRM} = sub { die "timeout\n" };
		# Sub-second alarm via setitimer would be neater, but ALRM's 1s
		# granularity is fine against a 1.5s budget and avoids the syscall
		# filter surprises that bit the sampler unit.
		alarm 2;

		if ($kind eq 'sink') {
			# Discard never replies. A completed connect plus an accepted
			# write is the whole protocol.
			print $sock 'x';
			$ok = 1;
		} elsif ($kind eq 'echo') {
			print $sock "status-probe\n";
			my $buf = '';
			sysread($sock, $buf, 32);
			$ok = ($buf =~ /status-probe/) ? 1 : 0;
		} elsif ($kind eq 'http') {
			# The Host header is mandatory — see header comment (2).
			print $sock "HEAD / HTTP/1.0\r\nHost: dreamstation.systems\r\n\r\n";
			my $buf = '';
			sysread($sock, $buf, 64);
			$ok = ($buf =~ m{^HTTP/}) ? 1 : 0;
		} else {
			# banner: server speaks first.
			# line:   nudge with CRLF, then read.
			# req:    protocol needs a real request line.
			print $sock "\r\n"                             if $kind eq 'line';
			print $sock "dreamstation.systems / 0\r\n"     if $kind eq 'req';
			my $buf = '';
			$ok = (defined sysread($sock, $buf, 1) && length $buf) ? 1 : 0;
		}
		alarm 0;
	};
	alarm 0;
	close $sock;

	my $ms = sprintf '%.0fms', (hnow() - $t0) * 1000;
	return ('down', 'no response') if $@;
	return $ok ? ('up', $ms) : ('down', 'unexpected response');
}

sub probe_tls {
	my ($port) = @_;
	my $t0 = hnow();

	# Lazy load — see the note at the top of the file. If the module is
	# missing entirely, say so rather than dying and losing the whole page.
	unless (eval { require IO::Socket::SSL; 1 }) {
		return ('unknown', 'IO::Socket::SSL unavailable');
	}

	# A completed handshake is the assertion. Certificate validation is
	# deliberately off: Gemini uses TOFU rather than a CA chain, and we are
	# testing "is the daemon answering", not "is this cert trusted".
	my $sock = IO::Socket::SSL->new(
		PeerAddr        => HOST, PeerPort => $port,
		Proto           => 'tcp', Timeout => TLS_TIMEOUT,
		SSL_verify_mode => IO::Socket::SSL::SSL_VERIFY_NONE(),
		SSL_hostname    => 'dreamstation.systems',
	);
	return ('down', $! ? 'handshake failed' : 'no response') unless $sock;

	my $ms = sprintf '%.0fms', (hnow() - $t0) * 1000;
	close $sock;
	return ('up', $ms);
}

sub unit_states {
	# ONE fork for every unit, not one per unit. systemctl accepts a list and
	# prints one word per unit in the order given, emitting "inactive" for
	# units it does not know rather than skipping them — so the lines line up
	# with the input positionally.
	#
	# This matters more than it looks: at ~55ms per systemctl invocation,
	# doing this per-service cost 830ms of a single vCPU per sweep, more than
	# the entire probe pass. Measured, not guessed.
	my @units = @_;
	my %state;
	@state{@units} = ('unknown') x @units;

	my $safe = join ' ', map { my $u = $_; $u =~ s/'/'\\''/g; "'$u'" } @units;
	my @out = split /\n/, qx{systemctl is-active $safe 2>/dev/null};
	return \%state if @out != @units;    # unexpected shape: report nothing

	$state{ $units[$_] } = $out[$_] for 0 .. $#units;
	return \%state;
}

# ------------------------------------------------------------------ metrics

sub read_cpu {
	# Rolling utilisation across whatever span the sampler's history covers.
	# The span is reported honestly rather than always claiming 5 minutes:
	# after a reboot, or if the timer has been stopped, the window is short
	# and the label says so.
	open my $fh, '<', CPU_HIST or return undef;
	my @l = <$fh>;
	close $fh;
	return undef if @l < 2;

	my ($t0, $tot0, $idle0) = split ' ', $l[0];
	my ($t1, $tot1, $idle1) = split ' ', $l[-1];
	my $dt = $tot1 - $tot0;
	return undef if !$dt || $dt <= 0;

	my $busy = 100 * (1 - ($idle1 - $idle0) / $dt);
	$busy = 0   if $busy < 0;
	$busy = 100 if $busy > 100;
	return { pct => $busy, span => $t1 - $t0 };
}

sub read_mem {
	open my $fh, '<', '/proc/meminfo' or return undef;
	my %m;
	while (<$fh>) { $m{$1} = $2 if /^(\w+):\s+(\d+)/ }
	close $fh;
	return undef unless $m{MemTotal};

	# htop's decomposition, not free(1)'s — for SWAP AS WELL AS MEMORY. Both
	# halves of this function follow the same convention; they did not always,
	# which is how the page came to disagree with htop about swap.
	#
	# Memory: excluding reclaimable cache is both more accurate and more
	# flattering here — it reports ~676MB genuinely used where free(1) claims
	# ~783MB.
	my $cache = ($m{Buffers} // 0) + ($m{Cached} // 0) + ($m{SReclaimable} // 0) - ($m{Shmem} // 0);
	my $used  = $m{MemTotal} - $m{MemFree} - $cache;

	# Swap: SwapCached is pages that exist in BOTH places — swapped out once,
	# read back into RAM, with the on-disk copy retained so that evicting them
	# again costs no write. free(1) counts those slots as used, because they
	# are genuinely allocated on disk; htop does not, because the pages are
	# resident. Neither is wrong. Following htop, they become the faded segment
	# of the bar rather than part of the solid one.
	#
	# The clamp is defensive: the two counters are sampled by the kernel a few
	# instructions apart, so a transient negative is conceivable.
	my $swap_cache = $m{SwapCached} // 0;
	my $swap_used  = ($m{SwapTotal} // 0) - ($m{SwapFree} // 0) - $swap_cache;
	$swap_used = 0 if $swap_used < 0;

	return {
		total => $m{MemTotal}, used => $used, cache => $cache, free => $m{MemFree},
		swap_total => $m{SwapTotal} // 0,
		swap_used  => $swap_used,
		swap_cache => $swap_cache,
	};
}

sub read_uptime {
	open my $fh, '<', '/proc/uptime' or return undef;
	my $l = <$fh>; close $fh;
	my ($secs) = split ' ', $l;
	return $secs;
}

# How long chronyd itself has been running. This is the denominator the NTS-KE
# counter needs: chrony reports those "since chronyd started" and does NOT
# persist them across restarts, so a bare total with no window attached is
# close to meaningless.
#
# Read from /proc rather than asked of systemd, because `systemctl show` is
# another 55ms fork on the sweep path and the cgroup hands us the PIDs for
# free. Field 22 of /proc/PID/stat is starttime in clock ticks since boot;
# comm (field 2) is parenthesised and may itself contain spaces or ')', so
# split after the LAST ')' rather than on whitespace from the start.
sub chronyd_uptime {
	open my $fh, '<', '/sys/fs/cgroup/system.slice/chrony.service/cgroup.procs'
		or return undef;
	my @pids = map { /^(\d+)$/ ? $1 : () } <$fh>;
	close $fh;

	my $ticks;
	for my $pid (@pids) {
		open my $sh, '<', "/proc/$pid/stat" or next;
		my $line = <$sh>;
		close $sh;
		next unless defined $line && $line =~ /\)\s+(.*)$/s;
		# Post-')' the fields resume at 3, so starttime (22) is index 19.
		my $st = (split ' ', $1)[19];
		next unless defined $st && $st =~ /^\d+$/;
		# chronyd forks helpers, so the cgroup holds several PIDs. The
		# earliest-started one is the daemon; the rest came from it.
		$ticks = $st if !defined $ticks || $st < $ticks;
	}
	return undef unless defined $ticks;

	my $up = read_uptime() or return undef;
	# USER_HZ, fixed at 100 for /proc regardless of the kernel's real HZ.
	# Hardcoded rather than asked of POSIX::sysconf, which costs 95ms to load.
	my $age = $up - $ticks / 100;
	return $age > 0 ? $age : undef;
}

sub read_chrony {
	my %out;

	# tracking needs no privilege. CSV field order (chrony 4.x):
	#   3 stratum, 6 last offset, 7 RMS offset, 14 leap status
	my $csv = qx{chronyc -c tracking 2>/dev/null};
	chomp $csv;
	if ($csv) {
		my @f = split /,/, $csv;
		if (@f >= 14 && $f[2] =~ /^\d+$/) {
			$out{stratum} = $f[2];
			$out{offset}  = $f[5];
			$out{leap}    = $f[13];
		}
	}

	# NTS-KE comes from the root-only `chronyc serverstats`, captured for us
	# by status-sample.service. Reading a file here keeps www-data out of
	# sudoers entirely.
	if (open my $fh, '<', CHRONY_SNAP) {
		while (<$fh>) { $out{$1} = $2 if /^(\w+)\s+(\S+)/ }
		close $fh;
	}

	$out{uptime} = chronyd_uptime();
	return \%out;
}

sub read_qps {
	# Three numbers, already condensed by status-sample.service. The scan that
	# produces them walks ~95k lines and costs ~263ms, which is why it does
	# not happen here — see the reset-handling note in status-sample.sh.
	open my $fh, '<', QPS_SNAP or return undef;
	my %o;
	while (<$fh>) { $o{$1} = $2 if /^(\w+)\s+(\S+)/ }
	close $fh;
	return (defined $o{now} || defined $o{avg}) ? \%o : undef;
}

# Current disk figures plus the downsampled 30-day series, both already
# condensed by status-sample.sh. The persistent history is never opened here
# — see status.txt. At most ~360 "p" lines, so this is a ~4KB read of tmpfs.
sub read_disk {
	open my $fh, '<', DISK_SNAP or return undef;
	my (%o, @series);
	while (<$fh>) {
		# "p <bucket> <ts> <used>". The two-field form is the previous
		# sampler's output; accepted so that a disk.txt written before an
		# upgrade still draws (bucket floor doubles as the plot time) rather
		# than blanking the graph until the next tick.
		if    (/^p (\d+) (\d+) (\d+)/) { push @series, [ $1, $2, $3 ] }
		elsif (/^p (\d+) (\d+)/)        { push @series, [ $1, $1, $2 ] }
		elsif (/^(\w+) (\S+)/) { $o{$1} = $2 }
	}
	close $fh;
	return undef unless $o{total} && $o{total} > 0;
	$o{series} = \@series;    # sorted by timestamp on the way in
	return \%o;
}

sub read_seen {
	# Packed sorted array of 4-byte big-endian IPv4 addresses, no header, so
	# the count is implicit in the file size. stat() only — this file is
	# ~440MB and must never be read.
	my $size = -s SEEN_SET;
	return $size ? int($size / 4) : undef;
}

# -------------------------------------------------------------------- sweep

sub sweep {
	# $started is hi-res because it measures a duration; `generated` is a plain
	# integer stamp compared against CORE::time by cache_read/render.
	my $started = hnow();
	my %d = (generated => time, deadline_hit => 0);

	my $units = unit_states(map { $_->[4] } @SERVICES);

	for my $s (@SERVICES) {
		my ($id, $label, $port, $kind, $unit) = @$s;

		if (hnow() - $started > SWEEP_DEADLINE) {
			# Budget spent. Remaining services are reported honestly as
			# unknown rather than being left to look fine or hanging the
			# request past nginx's fastcgi_read_timeout.
			$d{svc}{$id} = { state => 'unknown', detail => 'not probed (time budget)' };
			$d{deadline_hit} = 1;
			next;
		}

		my ($state, $detail) = $kind eq 'tls' ? probe_tls($port) : probe_tcp($port, $kind);
		$d{svc}{$id} = { state => $state, detail => $detail, unit => $units->{$unit} };
	}

	$d{cpu}    = read_cpu();
	$d{mem}    = read_mem();
	$d{uptime} = read_uptime();
	$d{chrony} = read_chrony();
	$d{qps}    = read_qps();
	$d{seen}   = read_seen();
	$d{took}   = hnow() - $started;
	return \%d;
}

# ---------------------------------------------------------- cache (flat kv)

sub cache_write {
	my ($d) = @_;
	# tmp + rename so a concurrent reader never sees a half-written cache.
	my $tmp = CACHE . ".$$";
	open my $fh, '>', $tmp or return;

	print $fh "generated $d->{generated}\n";
	print $fh "took $d->{took}\n";
	print $fh "deadline_hit $d->{deadline_hit}\n";
	for my $id (keys %{ $d->{svc} }) {
		my $s = $d->{svc}{$id};
		printf $fh "svc %s %s %s|%s\n", $id, $s->{state}, ($s->{unit} // 'unknown'), ($s->{detail} // '');
	}
	printf $fh "cpu %s %s\n", $d->{cpu}{pct}, $d->{cpu}{span} if $d->{cpu};
	# Positional, and so the same trap as the chrony whitelist below: a field
	# added to read_mem() but not to BOTH this line and its regex in
	# cache_read() renders once from the sweep and then vanishes on every
	# cached request.
	printf $fh "mem %s %s %s %s %s %s %s\n", @{ $d->{mem} }{qw(total used cache free swap_total swap_used swap_cache)} if $d->{mem};
	printf $fh "uptime %s\n", $d->{uptime} if defined $d->{uptime};
	printf $fh "seen %s\n",   $d->{seen}   if defined $d->{seen};
	printf $fh "qps %s %s %s\n", ($d->{qps}{now} // ''), ($d->{qps}{avg} // ''), ($d->{qps}{avg_span} // '') if $d->{qps};
	# THIS LIST IS A WHITELIST. A key added to read_chrony() but not added here
	# is written by the sweep, renders correctly once, and then silently
	# disappears for the next CACHE_TTL seconds — i.e. on almost every real
	# request. That is a genuinely confusing bug to chase; it has happened once.
	for my $k (qw(stratum offset leap nts_ke_accepted nts_ke_dropped uptime)) {
		printf $fh "chrony %s %s\n", $k, $d->{chrony}{$k} if defined $d->{chrony}{$k};
	}
	close $fh;
	rename $tmp, CACHE or unlink $tmp;
}

sub cache_read {
	open my $fh, '<', CACHE or return undef;
	my %d;
	while (my $l = <$fh>) {
		chomp $l;
		if ($l =~ /^svc (\S+) (\S+) (\S+)\|(.*)$/) {
			$d{svc}{$1} = { state => $2, unit => $3, detail => $4 };
		} elsif ($l =~ /^cpu (\S+) (\S+)/) {
			$d{cpu} = { pct => $1, span => $2 };
		# swap_cache is optional so that a cache file written by the previous
		# version of this script still parses, rather than dropping the whole
		# memory block until it expires.
		} elsif ($l =~ /^mem (\S+) (\S+) (\S+) (\S+) (\S+) (\S+)(?: (\S+))?/) {
			@{ $d{mem} }{qw(total used cache free swap_total swap_used swap_cache)} = ($1, $2, $3, $4, $5, $6, $7);
		} elsif ($l =~ /^qps (\S*) (\S*) (\S*)/) {
			$d{qps} = { now => $1, avg => $2, avg_span => $3 };
		} elsif ($l =~ /^chrony (\S+) (\S+)/) {
			$d{chrony}{$1} = $2;
		} elsif ($l =~ /^(\w+) (\S+)/) {
			$d{$1} = $2;
		}
	}
	close $fh;
	return $d{generated} ? \%d : undef;
}

# ------------------------------------------------------------------- render

sub esc {
	my $s = shift // '';
	$s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
	return $s;
}

sub commify { my $n = reverse shift; $n =~ s/(\d{3})(?=\d)/$1,/g; return scalar reverse $n }

sub dur {
	my $s = shift // 0;
	return sprintf '%ds', $s if $s < 60;
	return sprintf '%dm', $s / 60 if $s < 3600;
	return sprintf '%dh %dm', $s / 3600, ($s % 3600) / 60 if $s < 86400;
	return sprintf '%dd %dh', $s / 86400, ($s % 86400) / 3600;
}

sub mb { sprintf '%.0f', $_[0] / 1024 }
sub gb { sprintf '%.1f', $_[0] / 1048576 }

# Date labels for the graph's x-axis. gmtime is a builtin; POSIX::strftime
# would be correct-er about locales and costs 95ms to load for two labels a
# month apart, so it is not used. See the header note on module cost.
#
# gmtime, NOT localtime. The box sits in America/Los_Angeles, which is an
# accident of where the VPS is racked and not a fact about anyone reading the
# page. The x-axis label is the ONLY absolute time this page prints — every
# other figure is a relative duration and so reads the same everywhere — which
# makes it the one place a timezone can mislead. UTC is equally wrong for
# every reader, which is the best available answer for a public page.
#
# Note that TZ is unset for the CGI (fcgiwrap's unit sets no environment), so
# localtime here would silently follow /etc/localtime — i.e. the label's
# meaning would change under a `timedatectl set-timezone` with nothing in this
# file to explain why.
my @MON = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
sub daystamp { my @t = gmtime($_[0] // 0); return sprintf '%d %s', $t[3], $MON[ $t[4] ] }

# Status is conveyed by symbol AND word AND colour — never colour alone. The
# page this hangs off claims WCAG 2.2 AA conformance with a W3C badge, and a
# bare coloured dot would break that claim.
# WRAPPED IN aria-hidden AT THE POINT OF USE, because the word beside each mark
# already says the same thing: unwrapped, these announce as "black circle up" and
# "multiplication x DOWN". Hiding the glyph costs a screen reader nothing (the
# word is the content) and the colour+symbol+word triple survives intact for
# everyone else. Same reason the ꩜ and the 🖱️ in the host line are hidden.
my %MARK = (up => '●', down => '✕', unknown => '○');

# bar($pct, $extra_pct, $far): two segments, <i> solid and <u> faded. $far
# moves the faded segment to the right end of the bar instead of butting it
# against the solid one — meaningful, not cosmetic, since faded means
# "occupied but reclaimable" (adjacent, Memory/Swap) vs. "unoccupied but not
# yours" (far, Disk). Do not "unify" these. See status.txt.
sub bar {
	my ($pct, $extra_pct, $far, $titles) = @_;
	$pct = 0 if !defined $pct || $pct < 0;
	my $w  = sprintf '%.1f', $pct > 100 ? 100 : $pct;
	my $w2 = defined $extra_pct ? sprintf('%.1f', $extra_pct > 100 ? 100 : $extra_pct) : 0;

	# $titles is [solid, faded]: the exact quantity each segment is computed
	# from. A mouse affordance, not a text alternative — the bar stays
	# aria-hidden. Either title may be undef. See status.txt.
	my ($t_solid, $t_faded) = @{ $titles || [] };
	my $a_solid = defined $t_solid ? ' title="' . esc($t_solid) . '"' : '';
	my $a_faded = defined $t_faded ? ' title="' . esc($t_faded) . '"' : '';

	# aria-hidden: the bar is decoration. The number beside it is the content.
	#
	# The newlines around the bar are load-bearing, not formatting. Every caller
	# emits label-bar-value with no whitespace between them, and the bar renders
	# as nothing in a text browser, so lynx ran the two together as "CPU51%".
	# Both row layouts are grid (.sbrow directly, .metric via display:contents
	# on .metrics), and a grid or flex container drops whitespace-only text
	# between its items, so these cost exactly nothing in a graphical browser
	# while giving lynx a word break. Do not tidy them away.
	return qq{\n<span class="bar" aria-hidden="true"><i$a_solid style="width:$w%"></i>}
	     . ($w2 ? qq{<u} . ($far ? ' class="far"' : '') . qq{$a_faded style="width:$w2%"></u>} : '')
	     . qq{</span>\n};
}

# ------------------------------------------------------------------ the graph
#
# Hand-rolled SVG rather than a charting module (cost, theme, accessibility —
# see status.txt). Returns '' when there is not enough history to draw an
# honest line, so the caller can simply omit the figure.
sub disk_graph {
	my ($d) = @_;
	my $pts = $d->{series} || [];
	return '' if @$pts < 2;

	my $step  = $d->{step}       || 7200;
	my $win   = $d->{window}     || 2592000;
	my $end   = $d->{sampled_at} || time;
	my $total = $d->{total};

	# The current reading is appended as a final point so the line reaches
	# "now" and agrees with the Disk bar above it — see status.txt. Copied
	# rather than pushed onto $d->{series}, which is shared.
	my @P = @$pts;
	if (defined $d->{used} && defined $d->{sampled_at} && $P[-1][1] < $d->{sampled_at}) {
		push @P, [ int($d->{sampled_at} / $step) * $step, $d->{sampled_at}, $d->{used} ];
	}
	$pts = \@P;

	# The axis compresses to whatever history exists, up to the 30-day window
	# (see status.txt). first_ts is the real moment collection began; clamped
	# to the earliest point regardless, so nothing can fall left of the axis.
	my $begin = $d->{first_ts};
	$begin = $pts->[0][1] if !defined $begin || $begin > $pts->[0][1];
	my $start = $end - $win;
	$start = $begin if $begin > $start;
	my $span = $end - $start;
	return '' if $span <= 0;

	# 8% headroom above capacity so the dashed ceiling and its label are never
	# clipped by the top edge of the viewBox.
	my $ymax = $total * 1.08;

	my $pw = G_W - G_L - G_R;
	my $ph = G_H - G_T - G_B;

	# Plotted against ABSOLUTE time, not against position in the array. If the
	# history is younger than the window the line simply starts partway across,
	# which is the honest picture; rescaling the axis to fit would make three
	# days of data look like a month.
	my $X = sub { sprintf '%.1f', G_L + ($_[0] - $start) / $span * $pw };
	my $Y = sub { sprintf '%.1f', G_T + (1 - $_[0] / $ymax) * $ph };

	# Break the line wherever the sampler missed more than one bucket, so a
	# reboot or stopped timer reads as a gap rather than a straight line
	# through data never taken. Detected on the bucket ($p->[0]), not the plot
	# time ($p->[1]) — see status.txt for why only the grid is reliable.
	my (@seg, @cur, $prev);
	for my $p (@$pts) {
		next if $p->[1] < $start;
		if (defined $prev && $p->[0] - $prev > $step * 1.5) {
			push @seg, [@cur] if @cur;
			@cur = ();
		}
		push @cur, $p;
		$prev = $p->[0];
	}
	push @seg, [@cur] if @cur;
	return '' unless @seg;

	my ($first, $last) = ($pts->[0], $pts->[-1]);
	my ($lo, $hi) = ($first->[2], $first->[2]);
	for my $p (@$pts) {
		$lo = $p->[2] if $p->[2] < $lo;
		$hi = $p->[2] if $p->[2] > $hi;
	}

	my $cap_y  = $Y->($total);
	my $base_y = $Y->(0);

	# The accessible name and description carry the same information as the
	# picture, because for a screen reader they ARE the picture.
	# Both of these describe the span ACTUALLY DRAWN, not the nominal window,
	# so they stay true while the axis is still compressed.
	my $desc = sprintf 'Disk used on the root filesystem over the last %s: '
	         . '%s GB at the start, %s GB now, ranging between %s and %s GB, '
	         . 'against a capacity of %s GB.',
	         dur($span), gb($first->[2]), gb($last->[2]), gb($lo), gb($hi), gb($total);

	my $s = qq{<svg viewBox="0 0 } . G_W . qq{ } . G_H . qq{" role="img" }
	      . qq{aria-labelledby="dgt dgd"><title id="dgt">Disk usage over the last }
	      . esc(dur($span)) . qq{</title><desc id="dgd">} . esc($desc) . qq{</desc>};

	# Baseline and capacity ceiling. Both currentColor; the ceiling is dashed
	# and faded so it never competes with the data line.
	$s .= sprintf qq{<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="currentColor" }
	            . qq{stroke-opacity=".35"/>},
	            G_L, $base_y, G_W - G_R, $base_y;
	$s .= sprintf qq{<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="currentColor" }
	            . qq{stroke-opacity=".45" stroke-dasharray="4 4"/>},
	            G_L, $cap_y, G_W - G_R, $cap_y;

	# Interior gridlines at round GB values, at most five of them, drawn before
	# the data and fainter than either axis line. See status.txt.
	my @grid;
	{
		my $cap_gb = $total / 1048576;
		my $stepg;
		for my $n (1, 2, 2.5, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000) {
			$stepg = $n, last if $cap_gb / $n <= 5;
		}
		if ($stepg) {
			for (my $v = $stepg; $v < $cap_gb; $v += $stepg) {
				my $y = $Y->($v * 1048576);
				# Skip anything that would land on top of the baseline or the
				# capacity line, whose labels are already there and would
				# overprint.
				next if abs($y - $cap_y) < 10 || abs($y - $base_y) < 10;
				push @grid, [ $y, sprintf('%g', $v) ];
			}
		}
	}
	$s .= sprintf qq{<line x1="%s" y1="%s" x2="%s" y2="%s" stroke="currentColor" }
	            . qq{stroke-opacity=".15"/>},
	            G_L, $_->[0], G_W - G_R, $_->[0] for @grid;

	# Axis labels. text-anchor rather than manual offsets so they stay put when
	# the value width changes (9.8 GB vs 19.0 GB).
	my $lab = qq{font-size="12" fill="currentColor" fill-opacity=".7"};
	$s .= sprintf qq{<text x="%s" y="%s" text-anchor="end" %s>%s GB</text>},
	              G_L - 6, $cap_y + 4, $lab, gb($total);
	$s .= sprintf qq{<text x="%s" y="%s" text-anchor="end" %s>0</text>},
	              G_L - 6, $base_y + 4, $lab;
	$s .= sprintf qq{<text x="%s" y="%s" text-anchor="end" %s>%s</text>},
	              G_L - 6, $_->[0] + 4, $lab, $_->[1] for @grid;
	# These two labels are the only temporal context on the page, so the left
	# one switches to a clock below a two-day span and a date above it — see
	# status.txt for why the clock carries "UTC" and the date does not.
	my @lt = gmtime($start);
	my $left = $span < 172800 ? sprintf('%02d:%02d UTC', $lt[2], $lt[1]) : daystamp($start);
	$s .= sprintf qq{<text x="%s" y="%s" %s>%s</text>},
	              G_L, G_H - 6, $lab, esc($left);
	$s .= sprintf qq{<text x="%s" y="%s" text-anchor="end" %s>now</text>},
	              G_W - G_R, G_H - 6, $lab;

	# Each segment twice: a faded fill down to the baseline, then the line
	# itself. Same solid/faded idiom as the bars above it.
	for my $g (@seg) {
		if (@$g < 2) {
			# A lone bucket between two gaps: a polyline of one point draws
			# nothing at all, so mark it rather than silently dropping a real
			# measurement.
			$s .= sprintf qq{<circle cx="%s" cy="%s" r="2" fill="currentColor"/>},
			              $X->($g->[0][1]), $Y->($g->[0][2]);
			next;
		}
		my $pl = join ' ', map { $X->($_->[1]) . ',' . $Y->($_->[2]) } @$g;
		$s .= sprintf qq{<polygon points="%s,%s %s %s,%s" fill="currentColor" }
		            . qq{fill-opacity=".15"/>},
		            $X->($g->[0][1]), $base_y, $pl, $X->($g->[-1][1]), $base_y;
		$s .= qq{<polyline points="$pl" fill="none" stroke="currentColor" }
		    . qq{stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>};
	}

	$s .= qq{</svg>};
	return $s;
}

sub render {
	my ($d, $stale, $err) = @_;
	my $age = int(time - ($d->{generated} // time));
	my $out = '';

	# --muted replaces the GrayText system colour, which renders as "disabled"
	# under forced-colors even though this text is real content. See status.txt.
	my $css = <<'CSS';
html{color-scheme:light dark;--muted:#595959}
body{padding:1rem;font:100%/1.5 system-ui,sans-serif;max-width:60rem;margin-inline:auto}
.skip:not(:focus){position:absolute;left:-100vw}
h1{margin-bottom:.25rem}
.stamp{color:var(--muted);margin-top:0}
.warn{border:2px solid;border-radius:.5rem;padding:.75rem 1rem;margin-block:1rem;font-weight:600}
section{margin-block:2rem}
.metrics{display:grid;grid-template-columns:7rem 1fr auto;gap:.5rem 1rem;align-items:center;margin-block:.5rem}
.metric{display:contents}
.bar{display:block;height:1rem;border:1px solid;border-radius:.25rem;overflow:hidden;display:flex}
.bar i,.bar u{display:block;height:100%;text-decoration:none}
.bar i{background:currentColor}
.bar u{background:currentColor;opacity:.3}
.bar u.far{margin-left:auto}
.mval{font-variant-numeric:tabular-nums;white-space:nowrap}
figure.graph{margin:1rem 0 0}
figure.graph svg{display:block;width:100%;height:auto;overflow:visible}
.koo{color:#A80030}
table{border-collapse:collapse;width:100%}
caption{text-align:left;padding:.5em 0}
th,td{padding:.4em .5em;border:1px solid #888;text-align:left}
td.st{white-space:nowrap;font-weight:600}
.up{color:#0a7a28}.down{color:#c00}.unknown{color:var(--muted)}
@media(prefers-color-scheme:dark){html{--muted:#a6a6a6}.up{color:#4ade80}.down{color:#f87171}}
dl{display:grid;grid-template-columns:auto 1fr;gap:.4rem 1rem;margin:0}
dt{font-weight:600}dd{margin:0;font-variant-numeric:tabular-nums}
.scroll{overflow-x:auto}
footer{margin-top:3rem;color:var(--muted);font-size:.9rem}
a{overflow-wrap:anywhere}
:focus-visible{outline:2px solid;outline-offset:2px}
CSS
	$css =~ s/\s*\n\s*/ /g;

	$out .= qq{<!DOCTYPE html>\n<html lang="en">\n<head>\n<meta charset="utf-8">\n};
	$out .= qq{<meta name="viewport" content="width=device-width, initial-scale=1">\n};
	$out .= qq{<title>Service status ⁂ Robin Reel</title>\n};
	$out .= qq{<meta name="description" content="Live status of the public services running on dreamstation.systems.">\n};
	$out .= qq{<link rel="canonical" href="https://dreamstation.systems/professional/status">\n};
	$out .= qq{<style>$css</style>\n</head>\n<body>\n};
	$out .= qq{<a class="skip" href="#main">Skip to main content</a>\n};

	# The measured-at stamp lives in the footer, not here. The stale/failed
	# banners below still lead with the age, because in those cases the age IS
	# the headline and burying it would be dishonest.
	$out .= qq{<header>\n<h1>Service status</h1>\n};
	$out .= qq{<p><a href="/professional/"><span aria-hidden="true">←</span> Robin Reel</a></p>\n</header>\n};

	if ($err) {
		$out .= qq{<p class="warn down"><span aria-hidden="true">⚠</span> Could not refresh: } . esc($err)
		      . qq{. Showing the last successful measurement, } . esc(dur($age)) . qq{ old.</p>\n};
	} elsif ($stale) {
		$out .= qq{<p class="warn down"><span aria-hidden="true">⚠</span> This data is } . esc(dur($age))
		      . qq{ old and may no longer be accurate.</p>\n};
	}
	if ($d->{deadline_hit}) {
		$out .= qq{<p class="warn unknown">Some services were not probed: the sweep hit its time budget. }
		      . qq{They are shown as unknown rather than assumed healthy.</p>\n};
	}

	$out .= qq{<main id="main">\n};

	# ----- host
	$out .= qq{<section aria-labelledby="host"><h2 id="host">Host</h2>\n};
	# Static, and deliberately so: this is what the box IS, not what it is doing.
	# The measured figures live in the bars below and in the Time service section.
	# The ꩜ is decoration and is aria-hidden, so a screen reader reads the two
	# halves as one phrase rather than announcing "khmer sign koomuut".
	$out .= qq{<p>Debian 13 <span class="koo" aria-hidden="true">꩜</span> }
	      . qq{RackNerd 1&nbsp;vCPU, 1&nbsp;GB RAM <span aria-hidden="true">🖱️</span> Mouseover bar segments for details.</p>\n};

	# THE METRIC ROWS ARE BUILT SEPARATELY so they can share ONE grid: a
	# .metric{display:contents} row on the wrapper's grid puts every row on
	# the same three tracks, so the value column is sized to the widest value
	# across all of them and every bar ends up the same width. Deliberately
	# not a fixed rem width for that column: these strings grow (a swap
	# figure reaching 1024 / 3072 MB, a resized disk going to three digits),
	# and a guessed width would clip them or waste space.
	my $rows = '';

	if ($d->{cpu}) {
		# Δ, not an instantaneous reading: the bar is a delta between the first
		# and last samples in cpu.hist. iowait is named explicitly because
		# folding it into idle is a judgement call, not a given — see the
		# sampler. The span is already beside the bar ("4m avg"), so the title
		# says "sampled window" rather than repeating a number.
		$rows .= qq{<div class="metric"><span>CPU</span>}
		      . bar($d->{cpu}{pct}, undef, 0,
		            [ T_CPU, undef ])
		      . sprintf(qq{<span class="mval">%.0f%% · %s avg</span></div>\n},
		                $d->{cpu}{pct}, dur($d->{cpu}{span}));
	}
	if ($d->{mem}) {
		my $m = $d->{mem};
		# Both bars are two-segment: solid = genuinely occupied, faded = the
		# part that is cheap to reclaim (reclaimable cache for memory, pages
		# still resident in RAM for swap). The number beside each bar is the
		# SOLID segment only, matching htop.
		#
		# The hover titles below are the only place on the page that says what
		# each segment is, and give the arithmetic verbatim rather than a
		# friendly paraphrase — the exact meminfo fields are the whole answer
		# to "why does this disagree with free(1)". See read_mem().
		$rows .= qq{<div class="metric"><span>Memory</span>}
		      . bar(100 * $m->{used} / $m->{total}, 100 * $m->{cache} / $m->{total}, 0,
		            [ T_MEM_USED, T_MEM_CACHE ])
		      . sprintf(qq{<span class="mval">%s / %s MB</span></div>\n}, mb($m->{used}), mb($m->{total}));
		if ($m->{swap_total}) {
			$rows .= qq{<div class="metric"><span>Swap</span>}
			      . bar(100 * $m->{swap_used} / $m->{swap_total},
			            100 * ($m->{swap_cache} // 0) / $m->{swap_total}, 0,
			            [ T_SWAP_USED, T_SWAP_CACHE ])
			      . sprintf(qq{<span class="mval">%s / %s MB</span></div>\n},
			                mb($m->{swap_used}), mb($m->{swap_total}));
		}
	}
	if ($d->{disk}) {
		my $k = $d->{disk};
		# df's Used plus Available does NOT add up to Size — the difference is
		# ext4's reserve, still free. It shrinks toward zero if root ever
		# writes into it, which is a signal, not a bug. Drawn at the far end
		# of the bar (third arg to bar()), not adjacent like memory/swap's
		# faded segment — see status.txt for why.
		my $reserve_free = $k->{total} - $k->{used} - ($k->{avail} // 0);
		$reserve_free = 0 if $reserve_free < 0;
		$rows .= qq{<div class="metric"><span>Disk</span>}
		      . bar(100 * $k->{used} / $k->{total}, 100 * $reserve_free / $k->{total}, 1,
		            [ T_DISK_USED, T_DISK_RSVD ])
		      . sprintf(qq{<span class="mval">%s / %s GB</span></div>\n},
		                gb($k->{used}), gb($k->{total}));
	}
	# Wrapper only if there is something to put in it — on the degraded path
	# where neither /proc read succeeded, an empty grid would still be an
	# empty element in the markup.
	$out .= qq{<div class="metrics">\n$rows</div>\n} if length $rows;

	$out .= qq{<p>Uptime } . esc(dur($d->{uptime})) . qq{.</p>\n} if $d->{uptime};

	# NO FIGCAPTION: the axis labels give the span, the dashed line is
	# labelled with the capacity figure it sits at, and a five-minute sample
	# interval is invisible at two-hour buckets — nothing here needs restating
	# outside the drawing. The <title>/<desc> inside the SVG are the text
	# alternative for anyone who cannot see it.
	if ($d->{disk} && (my $svg = disk_graph($d->{disk}))) {
		$out .= qq{<figure class="graph">\n$svg\n</figure>\n};
	}
	$out .= qq{</section>\n};

	# ----- services
	my ($n_up, $n_tot) = (0, scalar @SERVICES);
	$n_up += ($d->{svc}{ $_->[0] }{state} // '') eq 'up' ? 1 : 0 for @SERVICES;

	$out .= qq{<section aria-labelledby="svc"><h2 id="svc">Services</h2>\n};
	$out .= qq{<p>$n_up of $n_tot responding.</p>\n};
	# aria-labelledby names this table from the "Services" heading above, so
	# it is not anonymous to a screen reader.
	# tabindex+role ON THE SCROLL CONTAINER, NOT DECORATION. .scroll is
	# overflow-x:auto, and Chrome and Safari do not put a scroll container in the
	# tab order on their own (Firefox does), so on a narrow viewport a keyboard-
	# only user could not scroll to the Notes column at all — WCAG 2.1.1. A
	# focusable scroll region must also have an accessible name or it is
	# announced as an anonymous stop, which is why the role and the label come
	# with the tabindex rather than the tabindex going on alone.
	$out .= qq{<div class="scroll" role="region" aria-labelledby="svc" tabindex="0">};
	$out .= qq{<table aria-labelledby="svc">\n};
	$out .= qq{<thead><tr><th scope="col">Service</th><th scope="col">Status</th>};
	$out .= qq{<th scope="col">Notes</th></tr></thead>\n<tbody>\n};

	# The probed port is deliberately NOT a column. For half these rows the one
	# port we probe is not the whole story — Web is 80 AND 443, Mail is 25/587/143,
	# Time is 123/udp with NTS-KE merely riding along on 4460, OpenGET answers on
	# 4151 but is only reachable through nginx. A port column would read as "this
	# is where the service lives", which for those rows is simply false. Where the
	# ports matter they are stated in the note, in prose that can be accurate.
	for my $s (@SERVICES) {
		my ($id, $label, $note) = @{$s}[0, 1, 5];
		my $r     = $d->{svc}{$id} || { state => 'unknown', detail => 'no data' };
		my $state = $r->{state} // 'unknown';
		my $word  = $state eq 'up' ? 'up' : $state eq 'down' ? 'DOWN' : 'unknown';

		my @notes = grep { length } ($note, $r->{detail});
		push @notes, "unit $r->{unit}" if ($r->{unit} // '') ne 'active' && ($r->{unit} // '') ne 'unknown';

		$out .= qq{<tr><th scope="row">} . esc($label) . qq{</th>};
		$out .= qq{<td class="st $state"><span aria-hidden="true">$MARK{$state}</span> }
		      . esc($word) . qq{</td>};
		$out .= qq{<td>} . esc(join ' · ', @notes) . qq{</td></tr>\n};
	}
	$out .= qq{</tbody></table></div>\n</section>\n};

	# ----- time service detail
	my $c = $d->{chrony} || {};
	$out .= qq{<section aria-labelledby="ntp"><h2 id="ntp">Time service</h2>\n<dl>\n};
	if (defined $c->{stratum}) {
		$out .= qq{<dt>Stratum</dt><dd>} . esc($c->{stratum}) . qq{</dd>\n};
		$out .= qq{<dt>Leap status</dt><dd>} . esc($c->{leap} // '—') . qq{</dd>\n} if $c->{leap};
		$out .= sprintf qq{<dt>Offset from reference</dt><dd>%+.0f µs</dd>\n}, $c->{offset} * 1_000_000
			if defined $c->{offset};
	}
	if ($d->{qps}) {
		$out .= qq{<dt>Queries per second</dt><dd>} . commify(sprintf '%.0f', $d->{qps}{now}) . qq{ now}
			if $d->{qps}{now};
		$out .= sprintf qq{, %s average over %s}, commify(sprintf '%.0f', $d->{qps}{avg}), dur($d->{qps}{avg_span})
			if $d->{qps}{avg};
		$out .= qq{</dd>\n} if $d->{qps}{now};
	}
	if ($d->{seen}) {
		my $share = $d->{seen} ? sprintf('%.1f', 3_700_000_000 / $d->{seen}) : '';
		$out .= qq{<dt>Distinct clients seen</dt><dd>} . commify($d->{seen})
		      . qq{ — about one in every $share routable IPv4 addresses</dd>\n};
	}
	if (defined $c->{nts_ke_accepted}) {
		# The window matters as much as the count — see chronyd_uptime(). If we
		# could not determine it, say the vaguer thing rather than a number that
		# looks lifetime and is not.
		$out .= qq{<dt>NTS key exchanges</dt><dd>} . commify($c->{nts_ke_accepted})
		      . ($c->{uptime}
		         ? qq{ accepted in } . esc(dur($c->{uptime})) . qq{ (since chronyd started)}
		         : qq{ accepted since chronyd started})
		      . qq{</dd>\n};
	}
	$out .= qq{<dt>External pool monitoring</dt><dd><a href="} . POOL_URL . qq{">ntppool.org</a></dd>\n};
	$out .= qq{</dl>\n</section>\n};

	$out .= qq{</main>\n<footer>\n};
	$out .= qq{<p>Probes run from the server against loopback.</p>\n};
	$out .= qq{<p>Generated by <code>status.cgi</code>, at most once every } . CACHE_TTL . qq{ seconds.</p>\n};
	$out .= qq{<p class="stamp">Measured <strong>} . esc(dur($age)) . qq{</strong> ago};
	$out .= sprintf ' · sweep took %.0fms', ($d->{took} // 0) * 1000 if $d->{took};
	$out .= qq{</p>\n};
	$out .= qq{</footer>\n</body>\n</html>\n};
	return $out;
}

# ---------------------------------------------------------------- box render

# A compact fragment for the top of /professional/, pulled in server-side by
# nginx SSI (see snippets/status-cgi.conf).
#
# It deliberately does NOT probe and does NOT touch the cache. /professional/
# is a static page that serves in 3.5ms and it is the first thing a reader
# lands on; making it wait on a 1.4s sweep to decorate a corner would be a bad
# trade. read_cpu() and read_mem() are two small file reads, so the whole
# fragment costs about as much as perl takes to start.
#
# That is also why there is NO service count here: a count needs a sweep, and
# a count that is only occasionally correct is worse than the link beside it.
#
# The <aside> element itself comes from HERE rather than being wrapped around
# the include in index.html, so that when this fails nginx's ssi_silent_errors
# leaves nothing at all behind. An empty bordered box on the resume page would
# look worse than no box.
sub render_box {
	my $cpu = read_cpu();
	my $mem = read_mem();
	return '' unless $cpu || $mem;

	my $out = qq{<aside class="statbox" aria-label="Server vitals">\n};
	if ($cpu) {
		$out .= qq{<div class="sbrow"><span>CPU</span>}
		      . bar($cpu->{pct}, undef, 0, [ T_CPU, undef ])
		      . sprintf(qq{<span class="sbval">%.0f%%</span></div>\n}, $cpu->{pct});
	}
	if ($mem) {
		# Same decomposition as the full page: solid = in use, faded =
		# reclaimable cache. Percentages only — an absolute MB figure does not
		# earn its width at this size.
		#
		# The hover titles ARE the same strings as the full page, deliberately.
		# The box shows no absolute figures, so the tooltip is the only thing
		# here that says what the faded segment is; giving it different wording
		# from the page it links to would be worse than giving it none.
		my $pct = 100 * $mem->{used} / $mem->{total};
		$out .= qq{<div class="sbrow"><span>RAM</span>}
		      . bar($pct, 100 * $mem->{cache} / $mem->{total}, 0,
		            [ T_MEM_USED, T_MEM_CACHE ])
		      . sprintf(qq{<span class="sbval">%.0f%%</span></div>\n}, $pct);
	}
	$out .= qq{<p class="sbmore"><a href="/professional/status">→ full status page</a></p>\n};
	$out .= qq{</aside>\n};
	return $out;
}

# --------------------------------------------------------------------- main

# Box mode, set by nginx as a fastcgi_param. Handled before anything else so
# it can never fall through into the sweep-or-cache path below.
if (($ENV{STATUS_MODE} // '') eq 'box') {
	my $frag = eval { render_box() } // '';
	print "Content-Type: text/html; charset=utf-8\r\n";
	print "Cache-Control: no-store\r\n";
	print "Content-Length: " . length($frag) . "\r\n";
	print "\r\n";
	print $frag;
	exit 0;
}

my $body;
eval {
	my $cached = cache_read();
	my $fresh  = $cached && (time - $cached->{generated}) < CACHE_TTL;

	my ($data, $stale, $err);
	if ($fresh) {
		$data = $cached;
	} else {
		my $d = eval { sweep() };
		if ($d) {
			cache_write($d);
			$data = $d;
		} elsif ($cached) {
			# Sweep blew up but we have history: show it, loudly labelled.
			# Never render stale data as if it were current.
			my $why = $@ || 'sweep failed';
			$why =~ s/\s+$//;
			($data, $stale, $err) = ($cached, 1, $why);
		} else {
			die $@ || "no data and sweep failed\n";
		}
	}

	# DISK DELIBERATELY BYPASSES THE CACHE, on every path, fresh or stale: it's
	# one small tmpfs read, cheaper than round-tripping through cache.txt, and
	# it means the figures are never up to CACHE_TTL stale. See status.txt.
	$data->{disk} = read_disk();
	$body = render($data, $stale, $err);
	1;
} or do {
	# Last resort: a valid, honest page rather than a die() that fcgiwrap
	# turns into a 502. The static /professional/status-down.html backstop
	# exists for the case where this script cannot run at all.
	my $e = $@ || 'unknown error';
	$e =~ s/\s+$//;
	$body = qq{<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8">}
	      . qq{<meta name="viewport" content="width=device-width, initial-scale=1">}
	      . qq{<title>Service status — unavailable</title></head><body>}
	      . qq{<h1>Service status is unavailable</h1>}
	      . qq{<p>The status page could not collect data: } . esc($e) . qq{</p>}
	      . qq{<p>This does not necessarily mean the services themselves are down — }
	      . qq{it means this page failed. <a href="/professional/">Back to Robin Reel</a>.</p>}
	      . qq{</body></html>\n};
};

# no-store: a browser-cached status page is a wrong status page.
print "Content-Type: text/html; charset=utf-8\r\n";
print "Cache-Control: no-store\r\n";
print "Content-Length: " . length($body) . "\r\n";
print "\r\n";
print $body;
