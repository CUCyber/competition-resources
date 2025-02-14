#!/usr/bin/env perl

=head1 NAME

reset_passwords.pl - Reset passwords for all users

=head1 SYNOPSIS

  perl reset_passwords.pl
  ./reset_passwords.pl

=head1 DESCRIPTION

Run the script to reset all the passwords to the specified password. The desired
password can be specified, and upon reset the passwords will be printed and
uploaded to the specified URL.

=cut

use strict;
use warnings;

our @excluded_users = qw(git gold-team);

# can use...
my @chars = ('a'..'z', 'A'..'Z', '0'..'9', qw(! @ $ % ^ & * 0 ( ) . ? / [ ] { } < > ; ' "));
sub get_pass {
	join '', map { $chars[rand @chars] } 1..shift;
}

my @data = ();
while (my @entry = getpwent()) {
    my ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $home, $shell) = @entry;

	if (grep { $_ eq $name } @excluded_users || ($shell =~ /^\/usr\/s?bin\/nologin$/ && $gid != $uid)) {
		continue;
	}

	push @data, (
		"$name:" . 'NewSecurePassword123!' # OR get_pass 13
	);
}

my $str = join "\n", @data;

my $fh;

open($fh, '|-', 'sudo chpasswd') or die "can't open chpasswd pipe: $!";
print $fh $str;
close $fh;

# open($fh, '|-', 'curl -v -F "c=@-" "https://fars.ee/?u=1"') or die "can't open curl pipe: $!";
# print $fh $str;
# close $fh;
