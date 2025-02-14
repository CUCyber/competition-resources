#!/usr/bin/env perl

=head1 NAME

rotate_ssh_keys.pl - Rotate SSH keys for all users

=head1 SYNOPSIS

  perl rotate_ssh_keys.pl [public_key_file]
  ./rotate_ssh_keys.pl [public_key_file]

=head1 DESCRIPTION

Run the script to rotate the SSH keys for the desired users. If a public key
file is not supplied, a public-private key pair will be generated. Add the users
to skip rotating keys for to the @ignore_users variable, and keys from owners to
ignore to the @ignore_key_owners variable. If the names of the keys to ignore
are unknown, run the command find /home -name authorized_keys -exec cat {} \; to
find the owners of keys to ignore; the other keys will be commented out in order
to maintain security.

=cut

use strict;
use warnings;

# users to ignore (simply add users separated by spaces)
my @ignore_users = qw(gold-team ansible);

# key owners (trailing comment) in authorized_keys to avoid commenting out (add
# owners separated by spaces; in case you do not know which keys you will need
# to ignore, run the command find /home -name authorized_keys -exec cat {} \; 
# and add the respective owners below)
my @ignore_key_owners = qw(scorekeeping@gold-team);

my $key_file = 'generated_key';
my $pub_key_file = "$key_file.pub";

if (@ARGV < 1) {
	print 'would you like to generate a set of new keys? [y|N] ';
	my $input = <STDIN>;

	chomp $input;
	if ($input =~ /^[Y|y](?:[E|e][Ss])?$/) {
		system("ssh-keygen -t ed25519 -f $key_file -N '' -q");
	} else {
		print "Exiting...\n";
		exit;
	}
} else {
	$pub_key_file = $ARGV[0];

	if ($pub_key_file !~ /\.pub$/) {
		print "are you sure you supplying a public key? [y|N] ";

		my $input = <STDIN>;
		chomp $input;
		if ($input !~ /^[Y|y](?:[E|e][Ss])?$/) {
			print "Exiting...\n";
			exit 1;
		}
	}
}

# create list of public keys
my @pub_key_keys = ();
open my $pub_fh, '<', $pub_key_file or die "could not open '$pub_key_file': $!";
while (my $pub_key = <$pub_fh>) {
	chomp $pub_key;
	push @pub_key_keys, $pub_key;
}
close $pub_fh;

while (my @entry = getpwent()) {
    my ($name, $passwd, $uid, $gid, $quota, $comment, $gcos, $home, $shell) = @entry;

	if (grep { $_ eq $name } @ignore_users) {
		# user ignored
		next;
	}

	my $user_ssh_dir = "/home/$name/.ssh";
	if (-d $user_ssh_dir) {
		my $auth_fname = "$user_ssh_dir/authorized_keys";
		my @lines = ();

		# attempt getting keys
		open(my $auth_fh_in, '<', $auth_fname) or print "could not open file '$auth_fname': $!";
		if (defined $auth_fh_in) {
			@lines = <$auth_fh_in>;
			close $auth_fh_in;
		}

		# comment out keys
		for my $line (@lines) {
			chomp $line;
			# comment if key was not already commented out and if key is not in ignore list
			if ($line !~ /^\s*#/ && ! grep { $line =~ /$_$/ } @ignore_key_owners) {
				$line = "# $line";
			}
		}

		# append the public key to authorized_keys
		push @lines, @pub_key_keys;

		# write the modified key list
		open(my $auth_fh_out, '>', $auth_fname) or print "could not open file '$auth_fname' for writing: $!";
		chmod 0600, $auth_fname or print "could not change permissions of '$auth_fname': $!";
		for my $line (@lines) {
			print $auth_fh_out "$line\n";
		}
		close $auth_fh_out;

		print "rotated key for $name\n";
	}
}
