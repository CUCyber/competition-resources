#!/usr/bin/env perl

=head1 NAME

priv_files.pl - Find files with elevated SGID/SUID permissions

=head1 SYNOPSIS

  perl priv_files.pl [-i|--interactive]
  ./priv_files.pl [-i|--interactive]

=head1 DESCRIPTION

Run script to remove elevated permissions from files on system. If state of
clean machine is known, add list of files that should have elevated permissions
to @default_elevated variable.

=cut

use strict;
use warnings;

my @default_elevated = qw(/usr/bin/sudo /usr/bin/pkexec /usr/bin/umount /usr/bin/su /usr/bin/gpasswd /usr/bin/newgrp /usr/bin/fusermount /usr/bin/at /usr/bin/chsh /usr/bin/passwd /usr/bin/chfn /usr/bin/mount);
my @reset_suid_files = ();
my @reset_sgid_files = ();

my $interactive = 0;

if (@ARGV > 1 && $ARGV[1] =~ /--?(?:i|nteractive)/) {
	$interactive = 1;
}

print STDERR "SUID BINARIES: \n";

# find suid executables
open my $fh, '-|', 'sudo find / -perm -4000 -type f 2>/dev/null' or die "could not open pipe: $!";
while (my $bin = <$fh>) {
    chomp($bin);
	if (!grep { $bin eq $_ } @default_elevated) {
		if ($interactive) {
			# prompt user if not in default elevated binaries
			print "reset $bin? [Y/n]\n";
			chomp(my $choice = <STDIN>);
			if ($choice =~ /^Y|y$/ || length $choice == 0) {
				push @reset_suid_files, $bin;
				`sudo chmod u-s $bin`;
			}
		} else {
			peinr("")
		}
	}
}
close $fh or warn "could not close pipe: $!";

print STDERR "SGID BINARIES: \n";

# find sgid binaries
open $fh, '-|', 'sudo find / -perm -2000 -type f 2>/dev/null' or die "could not open pipe: $!";
while (my $bin = <$fh>) {
    chomp($bin);
	if (!grep { $bin eq $_ } @default_elevated) {
		print "reset $bin? [Y/n]\n";
		chomp(my $choice = <STDIN>);
		if ($choice =~ /^Y|y$/ || length $choice == 0) {
			push @reset_sgid_files, $bin;
			`sudo chmod g-s $bin`;
		}
	}
}
close $fh or warn "could not close pipe: $!";

print 'reset SUID files: ' . join ', ', @reset_suid_files . "\n";
print 'reset SGID files: ' . join ', ', @reset_sgid_files . "\n";
