#!/usr/bin/perl
#
# cookie.cgi — one random fortune, as text/plain.
#
#   GET /cookie          from all files
#   GET /cookie/<name>   from that file only; 404 if there is no such file (or
#                        it has no fortunes)
#
# Deployed to /srv/cgi/cookie.cgi by promoteSite.sh; served at
# http(s)://fortunes.dreamstation.systems/cookie via fcgiwrap, with NO auth:
# the rest of that vhost is the password-protected fortunes.cgi, but this is
# read-only and the files are already public under dreamstation.systems/fortunes/.
# Kept apart from fortunes.cgi on purpose, so no code that can write to the data
# directory is reachable without the password. See ~/configNotes/fortunes.txt.
#
# Uniform over every fortune in every file, which is what fortune(6) does by
# default (each file weighted by its count). Positions come from the .dat files
# fortunes.cgi keeps up to date, so a request reads a few headers and one
# fortune rather than every file. A .dat that is missing or does not match its
# file's size (a hand edit) is ignored and that file is parsed directly.

use strict;
use warnings;

my $DIR     = '/srv/http/fortunes';
my $NAME_RE = qr/^[A-Za-z0-9_-]{1,64}$/;    # same rule as fortunes.cgi

sub respond {
	my ($status, $body) = @_;
	print "Status: $status\r\nContent-Type: text/plain; charset=utf-8\r\n",
		"Cache-Control: no-store\r\n\r\n";
	print $body unless ($ENV{REQUEST_METHOD} // 'GET') eq 'HEAD';
	exit 0;
}

my $method = $ENV{REQUEST_METHOD} // 'GET';
respond('405 Method Not Allowed', "Method not allowed.\n")
	unless $method eq 'GET' || $method eq 'HEAD';

# Start offsets of each fortune in a file: from its .dat if that is current,
# otherwise by scanning the file the same way strfile does (empty entries are
# not fortunes).
sub offsets {
	my $name = shift;
	my $size = -s "$DIR/$name" // return;
	if (open my $d, '<:raw', "$DIR/$name.dat") {
		local $/;
		my $dat = <$d> // '';
		close $d;
		if (length $dat >= 24) {
			my ($ver, $n) = unpack 'N2', $dat;
			my @o = unpack 'N*', substr($dat, 24);
			return @o[0 .. $n - 1]
				if $ver == 2 && @o == $n + 1 && $o[-1] == $size;
		}
	}
	open(my $in, '<:raw', "$DIR/$name") or return;
	my ($pos, $start, @offs) = (0, 0);
	while (my $line = <$in>) {
		if ($line =~ /^%\n?\z/) {
			push @offs, $start if $pos > $start;
			$start = $pos + length $line;
		}
		$pos += length $line;
	}
	close $in;
	push @offs, $start if $pos > $start;
	return @offs;
}

opendir(my $dh, $DIR) or respond('500 Internal Server Error', "No fortunes.\n");
my @files = sort grep { /$NAME_RE/ && -f "$DIR/$_" } readdir $dh;
closedir $dh;

# /cookie/<name>: nginx passes whatever follows /cookie/ (already URL-decoded)
# as COOKIE_FILE. It must be exactly one of the fortune files listed above,
# which is also the path-traversal guard. Unset means plain /cookie: all files.
my $want = $ENV{COOKIE_FILE};
if (defined $want) {
	respond('404 Not Found', "No such fortune file.\n")
		unless grep { $_ eq $want } @files;
	@files = ($want);
}

my (@pool, $total);
for my $f (@files) {
	my @o = offsets($f);
	next unless @o;
	push @pool, [$f, \@o];
	$total += @o;
}
unless ($total) {
	respond('404 Not Found', "No fortunes in $want.\n") if defined $want;
	respond('503 Service Unavailable', "No fortunes.\n");
}

my $k = int rand $total;
my ($file, $off);
for (@pool) {
	my ($f, $o) = @$_;
	if ($k < @$o) { ($file, $off) = ($f, $o->[$k]); last }
	$k -= @$o;
}

open(my $in, '<:raw', "$DIR/$file") or respond('500 Internal Server Error', "No fortunes.\n");
seek($in, $off, 0);
my $text = '';
while (my $line = <$in>) {
	last if $line =~ /^%\n?\z/;
	$text .= $line;
}
close $in;
$text .= "\n" unless $text =~ /\n\z/;
respond('200 OK', $text);
