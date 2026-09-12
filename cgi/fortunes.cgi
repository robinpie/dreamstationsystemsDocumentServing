#!/usr/bin/perl
#
# fortunes.cgi — add a fortune to a file, or download them all as a tarball.
#
# Deployed to /srv/cgi/fortunes.cgi by promoteSite.sh; served as the whole of
# https://fortunes.dreamstation.systems/ via fcgiwrap, behind basic auth in
# the nginx vhost (this script does no auth of its own). Runs as www-data.
#
# The data lives in /srv/http/fortunes/, which is NOT in the repo: promote
# carves it out of both its --delete and its chown/chmod, because www-data
# must be able to write there. See ~/configNotes/fortunes.txt.
#
#   GET  /            the form
#   POST /            file=<name>&fortune=<text>  append, rebuild the .dat
#   GET  /?download   fortunes.tar.gz of the whole directory

use strict;
use warnings;

my $DIR  = '/srv/http/fortunes';
my $SELF = 'https://fortunes.dreamstation.systems';

# Fortune files are the non-.dat regular files; the name check doubles as the
# path-traversal guard for the POSTed file= value.
sub fortune_files {
	opendir(my $dh, $DIR) or return ();
	my @f = sort grep { /^[A-Za-z0-9_-]+$/ && -f "$DIR/$_" } readdir $dh;
	closedir $dh;
	return @f;
}

sub html_escape {
	my $s = shift;
	$s =~ s/&/&amp;/g; $s =~ s/</&lt;/g; $s =~ s/>/&gt;/g; $s =~ s/"/&quot;/g;
	return $s;
}

sub url_decode {
	my $s = shift // '';
	$s =~ tr/+/ /;
	$s =~ s/%([0-9A-Fa-f]{2})/chr hex $1/ge;
	return $s;
}

# "Last fortune added", from the newest mtime among the fortune files (not the
# .dat files), in Central Time. A hand edit to a file counts too: nothing
# records adds separately.
sub last_added {
	my ($newest, $when);
	for my $f (fortune_files()) {
		my $m = (stat "$DIR/$f")[9] // next;
		($newest, $when) = ($f, $m) if !defined $when || $m > $when;
	}
	return '' unless defined $when;
	require POSIX;
	local $ENV{TZ} = 'America/Chicago';
	POSIX::tzset();
	my $ts = POSIX::strftime('%Y-%m-%d %H:%M:%S %Z', localtime $when);
	return '<p>Last fortune added: ' . html_escape("$ts ($newest)") . "</p>\n";
}

sub page {
	my ($status, $msg, $selected) = @_;
	$selected //= '';
	my $opts = join '', map {
		my $e = html_escape($_);
		"<option" . ($_ eq $selected ? ' selected' : '') . ">$e</option>\n"
	} fortune_files();
	my $note = defined $msg ? '<p>' . html_escape($msg) . "</p>\n" : '';
	$note .= last_added();
	print "Status: $status\r\nContent-Type: text/html; charset=utf-8\r\n",
		"Cache-Control: no-store\r\n\r\n";
	print <<"EOF";
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><title>fortunes</title></head>
<body>
<h1>fortunes</h1>
$note<form method="post" action="/">
<p><select name="file">
$opts</select></p>
<p><textarea name="fortune" rows="10" cols="72"></textarea></p>
<p><button type="submit">Add fortune</button></p>
</form>
<form method="get" action="/">
<p><button type="submit" name="download" value="1">Download all fortunes</button></p>
</form>
</body>
</html>
EOF
	exit 0;
}

# strfile(1), version 2, no flags — byte-identical to what fortune-mod's
# strfile writes for these files, so fortune-mod does not need installing.
# Header: version, count, longest, shortest, flags, delim + 3 pad bytes; then
# count+1 big-endian offsets (each entry's start, then end of file).
sub write_dat {
	my $name = shift;
	open(my $in, '<:raw', "$DIR/$name") or die "open $name: $!";
	my (@offs, $long, $short);
	my ($pos, $start) = (0, 0);
	my $take = sub {
		my $len = shift;
		return if $len <= 0;
		push @offs, $start;
		$long  = $len if !defined $long  || $len > $long;
		$short = $len if !defined $short || $len < $short;
	};
	while (my $line = <$in>) {
		if ($line =~ /^%\n?\z/) {
			$take->($pos - $start);
			$start = $pos + length $line;
		}
		$pos += length $line;
	}
	close $in;
	$take->($pos - $start);
	my $dat = pack('N5 a1 x3 N*', 2, scalar @offs, $long // 0, $short // 0, 0,
		'%', @offs, $pos);
	my $tmp = "$DIR/.$name.dat.$$";
	open(my $out, '>:raw', $tmp) or die "open $tmp: $!";
	print $out $dat;
	close $out or die "close $tmp: $!";
	chmod 0664, $tmp;
	rename $tmp, "$DIR/$name.dat" or die "rename $tmp: $!";
}

# Offline use: `fortunes.cgi --strfile <name>` rebuilds one .dat.
if (@ARGV == 2 && $ARGV[0] eq '--strfile') {
	write_dat($ARGV[1]);
	exit 0;
}

my $method = $ENV{REQUEST_METHOD} // 'GET';
my $query  = $ENV{QUERY_STRING}   // '';

if ($method eq 'GET' || $method eq 'HEAD') {
	if ($query =~ /(?:^|&)download(?:=|&|$)/) {
		my @stamp = gmtime;
		my $fn = sprintf 'fortunes-%04d%02d%02d.tar.gz',
			$stamp[5] + 1900, $stamp[4] + 1, $stamp[3];
		$| = 1;
		print "Content-Type: application/gzip\r\n",
			"Content-Disposition: attachment; filename=\"$fn\"\r\n",
			"Cache-Control: no-store\r\n\r\n";
		exit 0 if $method eq 'HEAD';
		exec 'tar', '-czf', '-', '-C', '/srv/http', '--exclude', 'fortunes/.*',
			'fortunes';
		die "exec tar: $!";
	}
	page('200 OK');
}

page('405 Method Not Allowed', 'Method not allowed.') unless $method eq 'POST';

# Basic auth credentials ride along on cross-site requests too, so a page
# elsewhere could otherwise POST here on a logged-in browser's behalf.
my $origin = $ENV{HTTP_ORIGIN};
if (defined $origin && $origin ne '' && $origin ne $SELF) {
	page('403 Forbidden', 'Cross-origin POST refused.');
}

my $clen = $ENV{CONTENT_LENGTH} // 0;
page('413 Content Too Large', 'Too long.') if $clen > 65536;
my $body = '';
read(STDIN, $body, $clen) if $clen > 0;

my %p;
for my $pair (split /&/, $body) {
	my ($k, $v) = split /=/, $pair, 2;
	$p{url_decode($k)} = url_decode($v);
}

my $file = $p{file} // '';
page('400 Bad Request', 'No such fortune file.')
	unless grep { $_ eq $file } fortune_files();

my $text = $p{fortune} // '';
$text =~ s/\r\n?/\n/g;
$text =~ s/[ \t]+$//mg;    # trailing whitespace on every line
$text =~ s/\A\n+//;        # leading blank lines
$text =~ s/\n+\z//;        # trailing blank lines
page('400 Bad Request', 'Empty fortune, nothing added.', $file)
	if $text !~ /\S/;
# A line that is just "%" is the delimiter and would split this into two.
page('400 Bad Request', 'A line consisting only of "%" is not allowed.', $file)
	if $text =~ /^%$/m;

open(my $fh, '+<:raw', "$DIR/$file") or page('500 Internal Server Error', "Cannot open $file: $!", $file);
flock($fh, 2) or page('500 Internal Server Error', "Cannot lock $file: $!", $file);
seek($fh, 0, 2);
my $size = tell $fh;
my $sep = '';
if ($size > 0) {
	seek($fh, $size - 1, 0);
	read($fh, my $last, 1);
	$sep = ($last eq "\n" ? '' : "\n") . "%\n";
	seek($fh, 0, 2);
}
print $fh $sep, $text, "\n";
close $fh or page('500 Internal Server Error', "Cannot write $file: $!", $file);
# The .dat is rebuilt after the lock is released; two near-simultaneous adds
# to one file each rebuild from the whole file, so the last rename wins with
# a .dat that covers both.
eval { write_dat($file); 1 }
	or page('500 Internal Server Error', "Added, but rebuilding $file.dat failed: $@", $file);

page('200 OK', "Added to $file.", $file);
