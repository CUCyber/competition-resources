#!/usr/bin/env perl

=head1 NAME

services_audit.pl - Perform actions (start/stop/enable/disable) on systemd services

=head1 SYNOPSIS

  perl services_audit.pl [start|stop|enable|disable] [--color]
  ./services_audit.pl [start|stop|enable|disable] [--color]

=head1 DESCRIPTION

Run script to select the desired services to perform the action on.
Run without any commands or arguments to view.
Use the --color flag to add color.

=cut

use strict;
use warnings;

my $srv_start = '';
my $srv_end = '';
my $bin_start = '';
my $bin_end = '';
if (grep { $_ =~ /^-?-color$/ } @ARGV) {
	$srv_start = "\033[95;1m";
	$srv_end = "\033[0m";
	$bin_start = "\033[92;1m";
	$bin_end = "\033[0m";

	@ARGV = grep { $_  !~ /^-?-color$/  } @ARGV;
}

my $state_arg, my $verb;
if (@ARGV == 0) {
    $verb = '';
    $state_arg = '';
} elsif ($ARGV[0] eq 'stop') {
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
	die "Usage: $0 [start|stop|enable|disable] [--fmt]\n";
}

my @services = `systemctl $verb --type=service $state_arg --plain --no-legend`;

for my $service (@services) {
	if ($service =~ /^(.+?)\s+/) {
    	print "$srv_start$1$srv_end\n";

		my $path = `systemctl show $1 --property=ExecStart`;
		if ($path =~ /^ExecStart=\{ (.*) \}$/) {
			my @service_argv = split ' ; ', $1;
			my $prg_argv = substr($service_argv[1], 7);
			my $index = index($prg_argv, ' ');
			my $prg_bin = $index == -1 ? $prg_argv : substr($prg_argv, 0, $index);
			my $prg_flags = $index == -1 ? '' : substr($prg_argv, $index + 1);

			print "\t$bin_start$prg_bin$bin_end $prg_flags\n\n";
		}
	}
}
