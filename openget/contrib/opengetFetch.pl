#!/usr/bin/perl
# SPDX-License-Identifier: GPL-2.0-only
# Copyright (C) 2026 robinpie
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; version 2 of the License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# opengetFetch.pl — shared helper for every OpenGET retro frontend script.
#
# Each retro protocol (Gopher CGI, Gemini CGI, Spartan, finger) asks the
# local daemon to render a page and prints the body; all rendering stays
# in Go so these scripts stay small. Not a module — `do`-ed by the scripts,
# so nothing to install. See openget.txt (RETRO FRONTENDS) for why.

use strict;
use warnings;

our $OPENGET_BASE = $ENV{OPENGET_BASE} || 'http://127.0.0.1:4151';
our $OPENGET_TIMEOUT = $ENV{OPENGET_TIMEOUT} || 5;

# og_fetch(PATH) -> (BODY, ERROR)
# Returns the response body, or undef plus a human-readable error.
sub og_fetch {
    my ($path) = @_;
    my $url = $OPENGET_BASE . $path;

    # HTTP::Tiny is core Perl (5.14+), so there is nothing to install on the box and nothing to keep up to date.
    require HTTP::Tiny;
    my $http = HTTP::Tiny->new(
        timeout => $OPENGET_TIMEOUT,
        agent   => 'openget-retro/1.0 (local)',
    );
    my $res = $http->get($url);

    unless ($res->{success}) {
        my $why = $res->{status} == 599
            ? ($res->{content} // 'connection failed')
            : "HTTP $res->{status} $res->{reason}";
        chomp $why;
        return (undef, $why);
    }
    return ($res->{content}, undef);
}

# og_escape(STRING) -> percent-encoded for a query string.
sub og_escape {
    my ($s) = @_;
    $s = '' unless defined $s;
    $s =~ s/([^A-Za-z0-9\-_.~])/sprintf('%%%02X', ord($1))/ge;
    return $s;
}

# og_clean(STRING) -> the query with anything alarming removed.
#
# The daemon is the real validator, but a request that cannot contain control characters or newlines cannot smuggle a header or a gophermap field separator into the reply either.
sub og_clean {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/[\r\n\t\0]//g;
    $s =~ s/^\s+|\s+$//g;
    $s = substr($s, 0, 64) if length($s) > 64;
    return $s;
}

1;
