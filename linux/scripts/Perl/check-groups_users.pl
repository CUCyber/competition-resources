#!/usr/bin/env perl

use strict;
use warnings;

my @users_list;
while (my ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $dir, $shell) = getpwent) {
    push @users_list, $name if ($name eq 'root' || ($uid >= 1000 && $name ne 'nobody'));
}
endpwent;

my @expected_users = ();
my %expected_group_members = ();
while (my $line = <>) {
	chomp $line if defined $line;

	my ($user, $group) = split ',', $line;

	push @expected_users, $user if ! grep { $_ eq $user } @expected_users;
	if (defined $group) {
		push @{$expected_group_members{$group}}, $user;
	}
}

my @to_remove = grep { my $outer = $_; ! grep { $outer eq $_ } @expected_users } @users_list;
my @to_add = grep { my $outer = $_; ! grep { $outer eq $_ } @users_list } @expected_users;

print STDERR "\033[36;1mREMOVE (LOCK) USERS:\033[0m\n";
print((join "\n", map { "usermod -L $_" } @to_remove) . "\n\n");

print STDERR "\033[36;1mADD USERS:\033[0m\n";
print((join "\n", map { "useradd -m $_" } @to_add) . "\n\n");

my @groups = ();
while (my ($name, $passwd, $gid, $members) = getgrent()) {
	if (! grep { $name eq $_ } @groups) {
		push @groups, $name;
	}
}
endgrent();

print STDERR "\033[36;1mCREATE GROUPS:\033[0m\n";
print((join "\n", map { "groupadd $_" } grep {
			my $outer = $_; ! grep { $outer eq $_ } @groups
		} keys %expected_group_members) . "\n\n");

print STDERR "\033[36;1mSET GROUP MEMBERS:\033[0m\n";
for my $group (keys %expected_group_members) {
	print('gpasswd -M ' . (join ',', @{$expected_group_members{$group}}) . " $group\n");
}
