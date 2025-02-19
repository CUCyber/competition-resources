#!/usr/bin/env perl

=head1 NAME

services_audit+fzf.pl - Perform actions (start/stop/enable/disable) on systemd services with fzf

=head1 SYNOPSIS

  perl services_audit.pl [start|stop|enable|disable]
  ./services_audit.pl [start|stop|enable|disable]

=head1 DESCRIPTION

Run script to select the desired services to perform the action on. Utilize the
preview window to see the details about the service.

=cut

use strict;
use warnings;

if (@ARGV != 1) {
    die "Usage: $0 [start|stop|enable|disable]\n";
}

my $state_arg, my $verb;
if ($ARGV[0] eq 'stop') {
    $verb = 'list-units';
    $state_arg = '--state=running';
} elsif ($ARGV[0] eq 'start') {
    $verb = 'list-units';
    $state_arg = '--state=failed';
} elsif ($ARGV[0] eq 'disable') {
    $verb = 'list-unit-files';
    $state_arg = '--state=enabled';
} elsif ($ARGV[0] eq 'enable') {
    $verb = 'list-unit-files';
    $state_arg = '--state=disabled';
} else {
	die "Usage: $0 --action [start|stop|enable|disable]\n";
}

my $command = "SYSTEMD_COLORS=true systemctl $verb --type=service $state_arg";
open(my $fzf, '|-', 'fzf --ansi --header-lines=1 --reverse --multi --preview="systemctl show {1}"') or die "Could not open fzf: $!";

open(my $fh, '-|', $command) or die "Could not execute command: $!";
while (my $line = <$fh>) {
    print $fzf $line;
}

close($fh);
close($fzf);
