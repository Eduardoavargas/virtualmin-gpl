#!/usr/local/bin/perl
# Runs all Virtualmin tests

package virtual_server;
use POSIX;
if (!$module_name) {
	$main::no_acl_check++;
	$ENV{'WEBMIN_CONFIG'} ||= "/etc/webmin";
	$ENV{'WEBMIN_VAR'} ||= "/var/webmin";
	if ($0 =~ /^(.*)\/[^\/]+$/) {
		chdir($pwd = $1);
		}
	else {
		chop($pwd = `pwd`);
		}
	$0 = "$pwd/functional-test.pl";
	require './virtual-server-lib.pl';
	$< == 0 || die "functional-test.pl must be run as root";
	}
$ENV{'PATH'} = "$module_root_directory:$ENV{'PATH'}";

# Make sure wget doesn't use a cache
$ENV{'http_proxy'} = undef;
$ENV{'ftp_proxy'} = undef;

$test_domain = "example.com";	# Never really exists
$test_rename_domain = "examplerename.com";
$test_target_domain = "exampletarget.com";
$test_subdomain = "example.net";
$test_parallel_domain1 = "example1.net";
$test_parallel_domain2 = "example2.net";
$test_ip_address = &get_default_ip();
$test_user = "testy";
$test_alias = "testing";
$test_alias_two = "yetanothertesting";
$test_reseller = "testsel";
$test_plan = "Test plan";
$timeout = 120;			# Longest time a test should take
$nowdate = strftime("%Y-%m-%d", localtime(time()));
$yesterdaydate = strftime("%Y-%m-%d", localtime(time()-24*60*60));
$wget_command = "wget -O - --cache=off --proxy=off --no-check-certificate  ";
$migration_dir = "/usr/local/webadmin/virtualmin/migration";
$migration_ensim_domain = "apservice.org";
$migration_ensim = "$migration_dir/$migration_ensim_domain.ensim.tar.gz";
$migration_cpanel_domain = "hyccchina.com";
$migration_cpanel = "$migration_dir/$migration_cpanel_domain.cpanel.tar.gz";
$migration_plesk_domain = "requesttosend.com";
$migration_plesk = "$migration_dir/$migration_plesk_domain.plesk.txt";
$migration_plesk_windows_domain = "sbcher.com";
$migration_plesk_windows = "$migration_dir/$migration_plesk_windows_domain.plesk_windows.psa";
$test_backup_file = "/tmp/$test_domain.tar.gz";
$test_incremental_backup_file = "/tmp/$test_domain.incremental.tar.gz";
$test_backup_dir = "/tmp/functional-test-backups";
$test_email_dir = "/usr/local/webadmin/virtualmin/testmail";
$spam_email_file = "$test_email_dir/spam.txt";
$virus_email_file = "$test_email_dir/virus.txt";
$ok_email_file = "$test_email_dir/ok.txt";
$supports_fcgid = defined(&supported_php_modes) &&
		  &indexof("fcgid", &supported_php_modes()) >= 0;

@create_args = ( [ 'limits-from-plan' ],
		 [ 'no-email' ],
		 [ 'no-slaves' ],
	  	 [ 'no-secondaries' ] );

# Cleanup backup dir
system("rm -rf $test_backup_dir");
system("mkdir -p $test_backup_dir");

# Parse command-line args
while(@ARGV > 0) {
	local $a = shift(@ARGV);
	if ($a eq "--domain") {
		$test_domain = shift(@ARGV);
		}
	elsif ($a eq "--sub-domain") {
		$test_subdomain = shift(@ARGV);
		}
	elsif ($a eq "--test") {
		push(@tests, shift(@ARGV));
		}
	elsif ($a eq "--skip-test") {
		push(@skips, shift(@ARGV));
		}
	elsif ($a eq "--no-cleanup") {
		$no_cleanup = 1;
		}
	elsif ($a eq "--output") {
		$output = 1;
		}
	elsif ($a eq "--migrate") {
		$migrate = shift(@ARGV);
		}
	elsif ($a eq "--user") {
		$webmin_user = shift(@ARGV);
		}
	elsif ($a eq "--pass") {
		$webmin_pass = shift(@ARGV);
		}
	else {
		&usage();
		}
	}
$webmin_wget_command = "wget -O - --cache=off --proxy=off --http-user=$webmin_user --http-passwd=$webmin_pass --user-agent=Webmin ";
&get_miniserv_config(\%miniserv);
$webmin_proto = "http";
if ($miniserv{'ssl'}) {
	eval "use Net::SSLeay";
	if (!$@) {
		$webmin_proto = "https";
		}
	}
$webmin_port = $miniserv{'port'};
$webmin_url = "$webmin_proto://localhost:$webmin_port";
if ($webmin_proto eq "https") {
	$webmin_wget_command .= "--no-check-certificate ";
	}

($test_domain_user) = &unixuser_name($test_domain);
($test_rename_domain_user) = &unixuser_name($test_rename_domain);
$prefix = &compute_prefix($test_domain, $test_domain_user, undef, 1);
$rename_prefix = &compute_prefix($test_rename_domain, $test_rename_domain_user,
				 undef, 1);
%test_domain = ( 'dom' => $test_domain,
		 'prefix' => $prefix,
		 'user' => $test_domain_user,
		 'group' => $test_domain_user,
		 'template' => &get_init_template() );
$test_full_user = &userdom_name($test_user, \%test_domain);
($test_target_domain_user) = &unixuser_name($test_target_domain);
$test_domain{'home'} = &server_home_directory(\%test_domain);
$test_domain_db = &database_name(\%test_domain);
$test_domain_cert = &default_certificate_file(\%test_domain, "cert");
$test_domain_key = &default_certificate_file(\%test_domain, "key");
%test_rename_domain = ( 'dom' => $test_rename_domain,
		        'prefix' => $rename_prefix,
       		        'user' => $test_rename_domain_user,
		        'group' => $test_rename_domain_user,
		        'template' => &get_init_template() );
$test_rename_full_user = &userdom_name($test_user, \%test_drename_omain);

# Create PostgreSQL password file
$pg_pass_file = "/tmp/pgpass.txt";
open(PGPASS, ">$pg_pass_file");
print PGPASS "*:*:*:$test_domain_user:smeg\n";
close(PGPASS);
$ENV{'PGPASSFILE'} = $pg_pass_file;
chmod(0600, $pg_pass_file);

# Build list of test types
$domains_tests = [
	# Make sure domain creation works
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to admin mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_domain_user.'@'.$test_domain ] ],
	},

	# Check IMAP and POP3 for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.':smeg@localhost:'.
		       $webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	$config{'postgres'} ? (
		# Check PostgreSQL login
		{ 'command' => 'psql -U '.$test_domain_user.' -h localhost '.$test_domain_db },
		) : ( ),

	# Check PHP execution
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Switch PHP mode to CGI
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'cgi' ] ],
	},

	# Check PHP running via CGI
	{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
	  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
	},

	$supports_fcgid ? (
		# Switch PHP mode to fCGId
		{ 'command' => 'modify-web.pl',
		  'args' => [ [ 'domain' => $test_domain ],
			      [ 'mode', 'fcgid' ] ],
		},

		# Check PHP running via fCGId
		{ 'command' => $wget_command.'http://'.$test_domain.'/test.php',
		  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
		},
		) : ( ),

	# Disable a feature
	{ 'command' => 'disable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webalizer' ] ],
	},

	# Re-enable a feature
	{ 'command' => 'enable-feature.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'webalizer' ] ],
	},

	# Change some attributes
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'desc' => 'New description' ],
		      [ 'pass' => 'newpass' ],
		      [ 'quota' => 555*1024 ],
		      [ 'bw' => 666*1024 ] ],
	},

	# Check attribute changes
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'Password: newpass',
		      'Description: New description',
		      'Server quota: 555',
		      'Bandwidth limit: 666', ],
	},

	# Check new Webmin password
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.
		       ':newpass@localhost:'.$webmin_port.'/',
	},

	# Disable the whole domain
	{ 'command' => 'disable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Make sure website is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Test home page',
	},

	# Re-enable the domain
	{ 'command' => 'enable-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	},

	# Check website again
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Validate all features
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'webalizer' ], [ 'mysql' ], [ 'logrotate' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],
	},

	# Make sure it worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'Description: Test sub-domain',
		      'Parent domain: '.$test_domain ],
	},

	# Cleanup the domains
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	];

# Mailbox tests
$mailbox_tests = [
	# Create a domain for testing
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mail' ], [ 'mysql' ],
		      @create_args, ],
        },

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Make sure the mailbox exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Check Unix account
	{ 'command' => $gconfig{'os_type'} =~ /-linux/ ? 
			'su -s /bin/sh '.$test_full_user.' -c "id -a"' :
			'id -a '.$test_full_user,
	  'grep' => 'uid=',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_full_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check SMTP to mailbox
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	},

	# Check IMAP and POP3 for mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Modify the user
	{ 'command' => 'modify-user.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'pass' => 'newpass' ],
		      [ 'real' => 'New name' ],
		      [ 'add-mysql' => $test_domain_user ],
		      [ 'add-email' => 'extra@'.$test_domain ] ],
	},

	# Validate the modifications
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'user' => $test_user ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Password: newpass',
		      'Real name: New name',
		      'Databases:.*'.$test_domain_user,
		      'Extra addresses:.*extra@'.$test_domain, ],
	},

	# Check user's MySQL login
	{ 'command' => 'mysql -u '.$test_full_user.' -pnewpass '.$test_domain_db.' -e "select version()"',
	},

	# Delete the user
	{ 'command' => 'delete-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user' => $test_user ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Alias tests
$alias_tests = [
	# Create a domain for the aliases
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mail' ], [ 'dns' ],
		      @create_args, ],
        },

	# Add a test alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@webmin.com' ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Make sure it was created
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_domain,
		      '^ *nobody@webmin.com',
		      '^ *nobody@virtualmin.com' ],
	},

	# Create another alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias_two ],
		      [ 'to', 'nobody@webmin.com' ] ],
	},

	# Make sure the mail server sees it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_alias.'@'.$test_domain ] ],
	},

	# Delete the alias
	{ 'command' => 'delete-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from' => $test_alias ] ],
	},

	# Make sure the server no longer sees it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_alias.'@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Make sure the other alias still exists
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_alias_two.'@'.$test_domain,
	},

	# Create a simple autoreply alias
	{ 'command' => 'create-simple-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'autoreply', 'Test autoreply' ] ],
	},

	# Make sure it was created
	{ 'command' => 'list-simple-aliases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Autoreply message: Test autoreply' ],
	},

	# Cleanup the aliases and domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Reseller tests
$reseller_tests = [
	# Create a reseller
	{ 'command' => 'create-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test reseller' ],
		      [ 'email', $test_reseller.'@'.$test_domain ] ],
	},

	# Verify that he exists
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'multiline' ] ],
	  'grep' => [ '^'.$test_reseller,
		      'Description: Test reseller',
		      'Email: '.$test_reseller.'@'.$test_domain,
		    ],
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_reseller.
		       ':smeg@localhost:'.$webmin_port.'/',
	},

	# Make changes
	{ 'command' => 'modify-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'desc', 'New description' ],
		      [ 'email', 'newmail@'.$test_domain ],
		      [ 'max-doms', 66 ],
		      [ 'allow', 'web' ],
		      [ 'logo', 'http://'.$test_domain.'/logo.gif' ],
		      [ 'link', 'http://'.$test_domain ] ],
	},

	# Check new reseller details
	{ 'command' => 'list-resellers.pl',
	  'args' => [ [ 'multiline' ] ],
	  'grep' => [ 'Description: New description',
		      'Email: newmail@'.$test_domain,
		      'Maximum domains: 66',
		      'Allowed features:.*web',
		      'Logo URL: http://'.$test_domain.'/logo.gif',
		      'Logo link: http://'.$test_domain,
		    ],
	},

	# Delete the reseller
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ] ],
	  'cleanup' => 1 },
	];

# Script tests
$script_tests = [
	# Create a domain for the scripts
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'mysql' ], [ 'dns' ],
		      @create_args, ],
        },

	# List all scripts
	{ 'command' => 'list-available-scripts.pl',
	  'grep' => 'WordPress',
	},

	# Install Wordpress
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'path', '/wordpress' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'version', 'latest' ] ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/wordpress/',
	  'grep' => 'WordPress installation',
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ] ],
	},

	# Install SugarCRM
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'sugarcrm' ],
		      [ 'path', '/' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'opt', 'demo 1' ],
		      [ 'version', 'latest' ] ],
	},

	# Check that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/',
	  'grep' => 'SugarCRM',
	},

	# Un-install
	{ 'command' => 'delete-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'sugarcrm' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Database tests
$database_tests = [
	# Create a domain for the databases
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      @create_args, ],
        },

	# Add a MySQL database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	# Check that we can login to MySQL
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	# Make sure the MySQL database appears
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => '^'.$test_domain_user.'_extra',
	},

	# Drop the MySQL database
	{ 'command' => 'delete-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_user.'_extra' ] ],
	},

	$config{'postgres'} ?
	(
		# Create a PostgreSQL database
		{ 'command' => 'create-database.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'type', 'postgres' ],
			      [ 'name', $test_domain_user.'_extra2' ] ],
		},

		# Make sure the PostgreSQL database appears
		{ 'command' => 'list-databases.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'multiline' ] ],
		  'grep' => '^'.$test_domain_user.'_extra2',
		},

		# Check that we can login
		{ 'command' => 'psql -U '.$test_domain_user.' -h localhost '.$test_domain_user.'_extra2' },

		# Drop the PostgreSQL database
		{ 'command' => 'delete-database.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'type', 'postgres' ],
			      [ 'name', $test_domain_user.'_extra2' ] ],
		},
	) : ( ),

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Proxy tests
$proxy_tests = [
	# Create the domain for proxies
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ],
		      @create_args, ],
        },

	# Create a proxy to Google
	{ 'command' => 'create-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ],
		      [ 'url', 'http://www.google.com/' ] ],
	},

	# Test that it works
	{ 'command' => $wget_command.'http://'.$test_domain.'/google/',
	  'grep' => '<title>Google',
	},

	# Check the proxy list
	{ 'command' => 'list-proxies.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => '/google/',
	},

	# Delete the proxy
	{ 'command' => 'delete-proxy.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'path', '/google/' ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Migration tests
$migrate_tests = [
	# Migrate an ensim backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'ensim' ],
		      [ 'source', $migration_ensim ],
		      [ 'domain', $migration_ensim_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_ensim_domain,
		      'migrated\s+5\s+aliases' ],
	  'migrate' => 'ensim',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure ensim migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_ensim_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: apservice',
		      'Features: unix dir mail dns web webalizer',
		      'Server quota:\s+30\s+MB' ],
	  'migrate' => 'ensim',
	},

	# Cleanup the ensim domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_ensim_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'ensim',
	},

	# Migrate a cPanel backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'cpanel' ],
		      [ 'source', $migration_cpanel ],
		      [ 'domain', $migration_cpanel_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_cpanel_domain,
		      'migrated\s+4\s+mail\s+users',
		      'created\s+1\s+list',
		      'created\s+1\s+database',
		    ],
	  'migrate' => 'cpanel',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure cPanel migration worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_cpanel_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: adam',
		      'Features: unix dir mail dns web webalizer mysql',
		    ],
	  'migrate' => 'cpanel',
	},

	# Cleanup the cpanel domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_cpanel_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'cpanel',
	},

	# Migrate a Plesk for Linux backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'plesk' ],
		      [ 'source', $migration_plesk ],
		      [ 'domain', $migration_plesk_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.$migration_plesk_domain,
		      'migrated\s+3\s+users',
		      'migrated\s+1\s+alias',
		      'migrated\s+1\s+databases,\s+and\s+created\s+1\s+user',
		    ],
	  'migrate' => 'plesk',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: rtsadmin',
		      'Features: unix dir mail dns web webalizer logrotate mysql spam virus',
		    ],
	  'migrate' => 'plesk',
	},

	# Cleanup the plesk domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_plesk_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'plesk',
	},

	# Migrate a Plesk for Windows backup
	{ 'command' => 'migrate-domain.pl',
	  'args' => [ [ 'type', 'plesk' ],
		      [ 'source', $migration_plesk_windows ],
		      [ 'domain', $migration_plesk_windows_domain ],
		      [ 'pass', 'smeg' ] ],
	  'grep' => [ 'successfully migrated\s+:\s+'.
			$migration_plesk_windows_domain,
		      'migrated\s+2\s+users',
		      'migrated\s+1\s+alias',
		    ],
	  'migrate' => 'plesk_windows',
	  'timeout' => 180,
	  'always_cleanup' => 1,
	},

	# Make sure the Plesk domain worked
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $migration_plesk_windows_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Username: sbcher',
		      'Features: unix dir mail dns web logrotate spam',
		    ],
	  'migrate' => 'plesk_windows',
	},

	# Cleanup the plesk domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $migration_plesk_windows_domain ] ],
	  'cleanup' => 1,
	  'migrate' => 'plesk_windows',
	},

	];
if (!-d $migration_dir) {
	$migrate_tests = [ { 'command' => 'echo Migration files under '.$migration_dir.' were not found in this system' } ];
	}

# Move domain tests
$move_tests = [
	# Create a parent domain to be moved
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a domain to be the target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'spod' ],
		      [ 'dir' ], [ 'unix' ], [ 'mysql' ],
		      @create_args, ],
        },

	# Add a user to the domain being moved
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Move under the target
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'parent', $test_target_domain ] ],
	},

	# Make sure the old Unix user is gone
	{ 'command' => 'grep ^'.$test_domain_user.': /etc/passwd',
	  'fail' => 1,
	},

	# Make sure the website still works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Check MySQL login under new owner
	{ 'command' => 'mysql -u '.$test_target_domain_user.' -pspod '.$test_domain_db.' -e "select version()"',
	},

	# Make sure MySQL is gone under old owner
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	  'fail' => 1,
	},

	# Make sure the parent domain and user are correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => [ 'Parent domain: '.$test_target_domain,
		      'Username: '.$test_target_domain_user ],
	},

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Move back to top-level
	{ 'command' => 'move-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'newuser', $test_domain_user ],
		      [ 'newpass', 'smeg' ] ],
	},

	# Make sure the Unix user is back
	{ 'command' => 'grep ^'.$test_domain_user.': /etc/passwd',
	},

	# Make sure the website still works
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Make sure MySQL is back
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Make sure the parent domain and user are correct
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'multiline' ],
		      [ 'domain', $test_domain ] ],
	  'grep' => 'Username: '.$test_domain_user,
	  'antigrep' => 'Parent domain:',
	},

	# Cleanup the domain being moved
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1 },
	];

# Alias domain tests
$aliasdom_tests = [
	# Create a domain to be the alias target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test alias target page' ],
		      @create_args, ],
        },

	# Create the alias domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'alias', $test_target_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test alias target page',
	},

	# Enable aliascopy mode
	{ 'command' => 'modify-mail.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'alias-copy' ] ],
	},

	# Create a mailbox in the target
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Test SMTP to him in the alias domain
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	},

	# Test SMTP to a missing user
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', 'bogus@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Convert to sub-server
	{ 'command' => 'unalias-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Validate to make sure it worked
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Create a web page, and make sure it can be fetched
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test un-aliased page' ] ],
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test un-aliased page',
	},

	# Make sure mail to the user no longer works
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'to', $test_user.'@'.$test_domain ] ],
	  'fail' => 1,
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1 },
	];

# Backup tests
@post_restore_tests = (
	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test home page',
	},

	# Check FTP login
	{ 'command' => $wget_command.
		       'ftp://'.$test_domain_user.':smeg@localhost/',
	  'antigrep' => 'Login incorrect',
	},

	# Check Webmin login
	{ 'command' => $wget_command.'--user-agent=Webmin '.
		       ($webmin_proto eq "https" ? '--no-check-certificate '
						 : '').
		       $webmin_proto.'://'.$test_domain_user.
		       ':smeg@localhost:'.$webmin_port.'/',
	},

	# Check MySQL login
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},
	{ 'command' => 'mysql -u '.$test_domain_user.' -psmeg '.$test_domain_db.'_extra -e "select version()"',
	},

	$config{'postgres'} ? (
		# Check PostgreSQL login
		{ 'command' => 'psql -U '.$test_domain_user.' -h localhost '.$test_domain_db },
		) : ( ),

	# Make sure the mailbox still exists
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => "^$test_user",
	},

	# Make sure the mailbox has the same settings
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'multiline' ],
		      [ 'user' => $test_user ] ],
	  'grep' => [ 'Password: smeg',
		      'Email address: '.$test_user.'@'.$test_domain,
		      'Home quota: 777' ],
	},

	# Test DNS lookup of sub-domain
	{ 'command' => 'host '.$test_subdomain,
	  'grep' => &get_default_ip(),
	},

	# Test HTTP get of sub-domain
	{ 'command' => $wget_command.'http://'.$test_subdomain,
	  'grep' => 'Test home page',
	},

	# Check that extra database exists
	{ 'command' => 'list-databases.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'grep' => $test_domain_db.'_extra',
	},

	# Check for allowed DB host
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Allowed mysql hosts:.*1\\.2\\.3\\.4',
	},
	);
$backup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ], [ 'spam' ], [ 'virus' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'webmin' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Test that everything will works
	@post_restore_tests,

	# Delete the domain, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Re-create from backup
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$multibackup_tests = [
	# Create a parent domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ],
		      $config{'postgres'} ? ( [ 'postgres' ] ) : ( ),
		      [ 'spam' ], [ 'virus' ], [ 'webmin' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Add a user to the domain being backed up
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 777*1024 ],
		      [ 'mail-quota', 777*1024 ] ],
	},

	# Add an extra database
	{ 'command' => 'create-database.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'name', $test_domain_db.'_extra' ] ],
	},

	# Add an allowed database host
	{ 'command' => 'modify-database-hosts.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'mysql' ],
		      [ 'add-host', '1.2.3.4' ] ],
	},

	# Create a sub-server to be included
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
	},

	# Back them both up to a directory
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', $test_backup_dir ] ],
	},

	# Delete web page
	{ 'command' => 'rm -f ~'.$test_domain_user.'/public_html/index.*',
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Test that everything will works
	@post_restore_tests,

	# Delete the domains, in preparation for re-creation
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore with the domain still in place
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_dir ] ],
	},

	# Run various tests again
	@post_restore_tests,

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	];

$remote_backup_dir = "/home/$test_target_domain_user";
$ssh_backup_prefix = "ssh://$test_target_domain_user:smeg\@localhost".
		     $remote_backup_dir;
$ftp_backup_prefix = "ftp://$test_target_domain_user:smeg\@localhost".
		     $remote_backup_dir;
$remotebackup_tests = [
	# Create a domain for the backup target
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },
	
	# Create a simple domain to be backed up
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      @create_args, ],
	},

	# Backup via SSH
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$ssh_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain via SSH
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Delete the backups file
	{ 'command' => "rm -rf /home/$test_target_domain_user/$test_domain.tar.gz" },

	# Backup via FTP
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'dest', "$ftp_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Restore via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_domain.tar.gz" ] ],
	},

	# Restore sub-domain via FTP
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/$test_subdomain.tar.gz" ] ],
	},

	# Backup via SSH in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore via SSH in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
	},

	# Delete the backups dir
	{ 'command' => "rm -rf /home/$test_target_domain_user/backups" },

	# Backup via FTP in home format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ftp_backup_prefix/backups" ] ],
	},

	# Restore via FTP in home format
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'source', "$ftp_backup_prefix/backups" ] ],
	},

	# Delete the backups dir
	{ 'command' => "rm -rf /home/$test_target_domain_user/backups" },

	# Backup via SSH one-by-one
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_subdomain ],
		      [ 'all-features' ],
		      [ 'onebyone' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/backups" ] ],
	},

	# Restore via SSH, all domains
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'all-domains' ],
		      [ 'all-features' ],
		      [ 'source', "$ssh_backup_prefix/backups" ] ],
	},

	# Cleanup the target domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},

	# Cleanup the backup domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$incremental_tests = [
	# Create a test domain
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ], [ 'mail' ],
		      [ 'mysql' ], [ 'webmin' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Install Wordpress to use up some disk
	{ 'command' => 'install-script.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'type', 'wordpress' ],
		      [ 'path', '/wordpress' ],
		      [ 'db', 'mysql '.$test_domain_db ],
		      [ 'version', 'latest' ] ],
	},

	# Backup to a temp file
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'dest', $test_backup_file ] ],
	},

	# Apply a content style change
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'style' => 'rounded' ],
		      [ 'content' => 'New website content' ] ],
	},

	# Create an incremental backup
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'incremental' ],
		      [ 'dest', $test_incremental_backup_file ] ],
	},

	# Make sure the incremental is smaller than the full
	{ 'command' =>
		"full=`du -k $test_backup_file | cut -f 1` ; ".
		"incr=`du -k $test_incremental_backup_file | cut -f 1` ; ".
		"test $incr -lt $full"
	},

	# Delete the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	},

	# Restore the full backup
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_backup_file ] ],
	},

	# Restore the incremental
	{ 'command' => 'restore-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'source', $test_incremental_backup_file ] ],
	},

	# Verify that the latest files were restored
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'New website content',
	},
	{ 'command' => $wget_command.'http://'.$test_domain.'/wordpress/',
	  'grep' => 'WordPress installation',
	},

	# Finally delete to clean up
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},
	];

$purge_tests = [
	# Create a test domain to backup
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Create a domain for the backup target via SSH
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_target_domain ],
		      [ 'desc', 'Test target domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      @create_args, ],
        },

	# Backup to a date-based directory that is a lie
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'dest', $test_backup_dir.'/1973-12-12' ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(124531200, 124531200, \"$test_backup_dir/1973-12-12\")'"
	},

	# Do another strftime-format backup with purging, to remove the old dir
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'mkdir' ],
		      [ 'strftime' ],
		      [ 'purge', 30 ],
		      [ 'dest', $test_backup_dir.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting directory',
	},

	# Make sure the right dir got deleted
	{ 'command' => 'ls -ld '.$test_backup_dir.'/1973-12-12',
	  'fail' => 1 },
	{ 'command' => 'ls -ld '.$test_backup_dir.'/'.$nowdate },

	# Backup via SSH to a date-based directory that is a lie
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/1973-12-12" ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(124531200, 124531200, \"$remote_backup_dir/1973-12-12\")'"
	},

	# Do another SSH strftime-format backup with purging
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'strftime' ],
		      [ 'purge', 30 ],
		      [ 'dest', $ssh_backup_prefix.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting file',
	},

	# Backup via FTP to a date-based directory that is a lie, but only
	# one day ago to exercise the different date format
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'dest', "$ssh_backup_prefix/$yesterdaydate" ] ],
	},

	# Fake the time on that directory
	{ 'command' => "perl -e 'utime(time()-24*60*60, time()-24*60*60, \"$remote_backup_dir/$yesterdaydate\")'"
	},

	# Do another FTP strftime-format backup with purging
	{ 'command' => 'backup-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'all-features' ],
		      [ 'newformat' ],
		      [ 'strftime' ],
		      [ 'purge', '0.5' ],
		      [ 'dest', $ftp_backup_prefix.'/%Y-%m-%d' ] ],
	  'grep' => 'Deleting FTP file',
	},

	# Finally delete to clean up
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'domain', $test_target_domain ] ],
	  'cleanup' => 1,
	},
	];

$mail_tests = [
	# Create a domain to get spam
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'mail' ],
		      [ 'spam' ], [ 'virus' ],
		      @create_args, ],
	},

	# Setup spam and virus delivery
	{ 'command' => 'modify-spam.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'virus-delete' ],
		      [ 'spam-file', 'spam' ],
		      [ 'spam-no-delete-level' ] ],
	},

	# Add a mailbox to the domain
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ],
		      [ 'no-creation-mail' ] ],
	},

	# If spamd is running, make it restart so that it picks up the new user
	{ 'command' => $gconfig{'os_type'} eq 'solaris' ?
			'pkill -HUP spamd' : 'killall -HUP spamd',
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	  'ignorefail' => 1,
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

        # Send some reasonable mail to him
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	},

	# Check if the mail arrived
	{ 'command' => 'list-mailbox.pl',
	  'args' => [ [ 'domain', $test_domain ],
                      [ 'user', $test_user ] ],
	  'grep' => [ 'Hello World', 'X-Spam-Status:' ],
	},

	# Use IMAP and POP3 to count mail - should be two or more
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
	},
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	  'grep' => '[23] messages',
	},

	-r $virus_email_file ? (
		# Add empty lines to procmail.log
		{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
		},

		# Send a virus message, if we have one
		{ 'command' => 'test-smtp.pl',
		  'args' => [ [ 'from', 'virus@virus.com' ],
			      [ 'to', $test_user.'@'.$test_domain ],
			      [ 'data', $virus_email_file ] ],
		},

		# Check procmail log for virus detection
		{ 'command' => 'while [ "`tail -5 /var/log/procmail.log |grep '.
			       'To:'.$test_user.'@'.$test_domain.
			       ' | grep Mode:Virus`" = "" ]; do '.
			       'sleep 5; done',
		  'timeout' => 60,
		},

		# Make sure it was NOT delivered
		{ 'command' => 'list-mailbox.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'user', $test_user ] ],
		  'antigrep' => 'Virus test',
		},
		) : ( ),

	-r $spam_email_file ? (
		# Add the spammer's address to this domain's blacklist
		{ 'command' => 'echo blacklist_from spam@spam.com >'.
			       $module_config_directory.'/spam/'.
			       '`./list-domains.pl --domain '.$test_domain.
			       ' --id-only`/virtualmin.cf',
		},

		# Add empty lines to procmail.log
		{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
		},

		# Send a spam message, if we have one
		{ 'command' => 'test-smtp.pl',
		  'args' => [ [ 'from', 'spam@spam.com' ],
			      [ 'to', $test_user.'@'.$test_domain ],
			      [ 'data', $spam_email_file ] ],
		},

		# Check procmail log for spam detection
		{ 'command' => 'while [ "`tail -5 /var/log/procmail.log |grep '.
			       'To:'.$test_user.'@'.$test_domain.
			       ' | grep Mode:Spam`" = "" ]; do '.
			       'sleep 5; done',
		  'timeout' => 60,
		},

		# Make sure it went to the spam folder
		{ 'command' => 'grep "Spam test" ~'.$test_full_user.'/spam',
		},
		) : ( ),

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },
	];

$prepost_tests = [
	# Create a domain just to see if scripts run
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_DOM >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_DOM >>/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure pre and post creation scripts run
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE '.$test_domain,
		      'AFTER '.$test_domain ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	# Change the password
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'pass', 'quux' ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_PASS $VIRTUALSERVER_NEWSERVER_PASS >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_PASS $VIRTUALSERVER_OLDSERVER_PASS >>/tmp/prepost-test.out' ],
		    ],
	},

	# Make sure the pre and post change scripts run
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE smeg quux',
		      'AFTER quux smeg' ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'pre-command' => 'echo BEFORE $VIRTUALSERVER_DOM >/tmp/prepost-test.out' ],
		      [ 'post-command' => 'echo AFTER $VIRTUALSERVER_DOM >>/tmp/prepost-test.out' ],
		    ],
        },

	# Check the pre and post deletion scripts for the deletion
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'BEFORE '.$test_domain,
		      'AFTER '.$test_domain ],
	},
	{ 'command' => 'rm -f /tmp/prepost-test.out' },

	# Create a reseller for the new domain
	{ 'command' => 'create-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test reseller' ],
		      [ 'email', $test_reseller.'@'.$test_domain ] ],
	},

	# Re-create the domain, capturing all variables
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'reseller', $test_reseller ],
		      [ 'dir' ], [ 'unix' ], [ 'dns' ], [ 'web' ],
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( [ 'virtualmin-awstats' ] ) : ( ),
		      [ 'post-command' => 'env >/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure all important variables were set
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'VIRTUALSERVER_ACTION=CREATE_DOMAIN',
		      'VIRTUALSERVER_DOM='.$test_domain,
		      'VIRTUALSERVER_USER='.$test_domain_user,
		      'VIRTUALSERVER_OWNER=Test domain',
		      'VIRTUALSERVER_UID=\d+',
		      'VIRTUALSERVER_GID=\d+',
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( 'VIRTUALSERVER_VIRTUALMIN_AWSTATS=1' ) : ( ),
		      'RESELLER_NAME='.$test_reseller,
		      'RESELLER_DESC=Test reseller',
		      'RESELLER_EMAIL='.$test_reseller.'@'.$test_domain,
		    ]
	},

	# Set a custom field
	{ 'command' => 'modify-custom.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'allow-missing' ],
		      [ 'set', 'myfield foo' ] ],
	},

	# Create a sub-server, capturing all variables
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'post-command' => 'env >/tmp/prepost-test.out' ],
		      @create_args, ],
	},

	# Make sure parent variables work
	{ 'command' => 'cat /tmp/prepost-test.out',
	  'grep' => [ 'VIRTUALSERVER_ACTION=CREATE_DOMAIN',
		      'VIRTUALSERVER_DOM='.$test_subdomain,
		      'VIRTUALSERVER_OWNER=Test sub-domain',
		      'PARENT_VIRTUALSERVER_USER='.$test_domain_user,
		      'PARENT_VIRTUALSERVER_DOM='.$test_domain,
		      'PARENT_VIRTUALSERVER_OWNER=Test domain',
		      'PARENT_VIRTUALSERVER_FIELD_MYFIELD=foo',
		      &indexof('virtualmin-awstats', @plugins) >= 0 ?
			( 'PARENT_VIRTUALSERVER_VIRTUALMIN_AWSTATS=1' ) : ( ),
		      'RESELLER_NAME='.$test_reseller,
		      'RESELLER_DESC=Test reseller',
		      'RESELLER_EMAIL='.$test_reseller.'@'.$test_domain,
		    ]
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
        },

	# Cleanup the reseller
	{ 'command' => 'delete-reseller.pl',
	  'args' => [ [ 'name', $test_reseller ] ],
	  'cleanup' => 1 },
	];

$webmin_tests = [
	# Make sure the main Virtualmin page can be displayed
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}".
		       "/virtual-server/",
	  'grep' => [ 'Virtualmin Virtual Servers', 'Delete Selected' ],
	},

	# Create a test domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/domain_setup.cgi?dom=$test_domain&vpass=smeg&template=0&plan=0&dns_ip_def=1&vuser_def=1&email_def=1&mgroup_def=1&group_def=1&prefix_def=1&db_def=1&quota=100&quota_units=1048576&uquota=120&uquota_units=1048576&bwlimit_def=0&bwlimit=100&bwlimit_units=MB&mailboxlimit_def=1&aliaslimit_def=0&aliaslimit=34&dbslimit_def=0&dbslimit=10&domslimit_def=0&domslimit=3&nodbname=0&field_purpose=&field_amicool=&unix=1&dir=1&logrotate=1&mail=1&dns=1&web=1&webalizer=1&mysql=1&webmin=1&proxy_def=1&fwdto_def=1&virt=0&ip=&content_def=1'",
	  'grep' => [ 'Adding new virtual website', 'Saving server details' ],
	},

	# Make sure the domain was created
	{ 'command' => 'list-domains.pl',
	  'grep' => "^$test_domain",
	},

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/virtual-server/delete_domain.cgi\\?dom=`./list-domains.pl --domain $test_domain --id-only`\\&confirm=1",
	  'grep' => [ 'Deleting virtual website', 'Deleting server details' ],
	  'cleanup' => 1,
	},

	];

$remote_tests = [
	# Test domain creation via remote API
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=create-domain&domain=$test_domain&pass=smeg&dir=&unix=&web=&dns=&mail=&webalizer=&mysql=&logrotate=&".join("&", map { $_->[0]."=" } @create_args)."'",
	  'grep' => 'Exit status: 0',
	},

	# Make sure it was created
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=list-domains'",
	  'grep' => [ "^$test_domain", 'Exit status: 0' ],
	},

	# Delete the domain
	{ 'command' => $webmin_wget_command.
		       "'${webmin_proto}://localhost:${webmin_port}/virtual-server/remote.cgi?program=delete-domain&domain=$test_domain'",
	  'grep' => [ 'Exit status: 0' ],
	},
	];

if (!$webmin_user || !$webmin_pass) {
	$webmin_tests = [ { 'command' => 'echo Webmin tests cannot be run unless the --user and --pass parameters are given' } ];
	$remote_tests = [ { 'command' => 'echo Remote API tests cannot be run unless the --user and --pass parameters are given' } ];
	}

$ssl_tests = [
	# Create a domain with SSL and a private IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'allocate-ip' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL home page' ],
		      @create_args, ],
        },

	# Test DNS lookup
	{ 'command' => 'host '.$test_domain,
	  'antigrep' => &get_default_ip(),
	},

	# Test HTTP get
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL home page',
	},

	# Test HTTPS get
	{ 'command' => $wget_command.'https://'.$test_domain,
	  'grep' => 'Test SSL home page',
	},

	# Test SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Check PHP execution via HTTPS
	{ 'command' => 'echo "<?php phpinfo(); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'https://'.$test_domain.'/test.php',
	  'grep' => 'PHP Version',
	},

	# Switch PHP mode to CGI
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'mode', 'cgi' ] ],
	},

	# Check PHP running via CGI via HTTPS
	{ 'command' => 'echo "<?php system(\'id -a\'); ?>" >~'.
		       $test_domain_user.'/public_html/test.php',
	},
	{ 'command' => $wget_command.'https://'.$test_domain.'/test.php',
	  'grep' => 'uid=[0-9]+\\('.$test_domain_user.'\\)',
	},

	# Test generation of a new self-signed cert
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'self' ],
		      [ 'size', 1024 ],
		      [ 'days', 365 ],
		      [ 'cn', $test_domain ],
		      [ 'c', 'US' ],
		      [ 'st', 'California' ],
		      [ 'l', 'Santa Clara' ],
		      [ 'o', 'Virtualmin' ],
		      [ 'ou', 'Testing' ],
		      [ 'email', 'example@'.$test_domain ],
		      [ 'alt', 'test_subdomain' ] ],
	},

	# Test generated SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'C=US', 'ST=California', 'L=Santa Clara',
		      'O=Virtualmin', 'OU=Testing', 'CN='.$test_domain ],
	},

	# Test generation of a CSR
	{ 'command' => 'generate-cert.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'csr' ],
		      [ 'size', 1024 ],
		      [ 'days', 365 ],
		      [ 'cn', $test_domain ],
		      [ 'c', 'US' ],
		      [ 'st', 'California' ],
		      [ 'l', 'Santa Clara' ],
		      [ 'o', 'Virtualmin' ],
		      [ 'ou', 'Testing' ],
		      [ 'email', 'example@'.$test_domain ],
		      [ 'alt', 'test_subdomain' ] ],
	},

	# Testing listing of keys, certs and CSR
	{ 'command' => 'list-certs.pl',
	  'args' => [ [ 'domain' => $test_domain ] ],
	  'grep' => [ 'BEGIN CERTIFICATE', 'END CERTIFICATE',
		      'BEGIN RSA PRIVATE KEY', 'END RSA PRIVATE KEY',
		      'BEGIN CERTIFICATE REQUEST', 'END CERTIFICATE REQUEST' ],
	},

	# Test re-installation of the cert and key
	{ 'command' => 'install-cert.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'cert', $test_domain_cert ],
		      [ 'key', $test_domain_key ] ],
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Shared IP address tests
$shared_tests = [
	# Allocate a shared IP
	{ 'command' => 'create-shared-address.pl',
	  'args' => [ [ 'allocate-ip' ], [ 'activate' ] ],
	},

	# Get the IP
	{ 'command' => './list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host '.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test shared home page',
	},
	
	# Change to the default IP
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'shared-ip', &get_default_ip() ] ],
	},

	# Test DNS and website again
	{ 'command' => 'host '.$test_domain,
	  'grep' => &get_default_ip(),
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test shared home page',
	},

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },

	# Remove the shared IP
	{ 'command' => 'delete-shared-address.pl',
	  'args' => [ [ 'ip', '$SHARED_IP' ], [ 'deactivate' ] ],
	  'cleanup' => 1,
	},
	];

# Tests with SSL on shared IP
$wildcard_tests = [
	# Allocate a shared IP
	{ 'command' => 'create-shared-address.pl',
	  'args' => [ [ 'allocate-ip' ], [ 'activate' ] ],
	},

	# Get the IP
	{ 'command' => './list-shared-addresses.pl --name-only | tail -1',
	  'save' => 'SHARED_IP',
	},

	# Create a domain with SSL on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test SSL shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared home page' ],
		      @create_args, ],
        },

	# Test DNS and website
	{ 'command' => 'host '.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test SSL shared home page',
	},

	# Test SSL cert
	{ 'command' => 'openssl s_client -host '.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL shared domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Create a sub-domain with SSL on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', "sslsub.".$test_domain ],
		      [ 'desc', 'Test SSL shared sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared sub-domain home page' ],
		      @create_args, ],
        },

	# Test DNS and website for the sub-domain
	{ 'command' => 'host '.'sslsub.'.$test_domain,
	  'grep' => '$SHARED_IP',
	},
	{ 'command' => $wget_command.'http://sslsub.'.$test_domain,
	  'grep' => 'Test SSL shared sub-domain home page',
	},

	# Test sub-domain SSL cert
	{ 'command' => 'openssl s_client -host '.'sslsub.'.$test_domain.
		       ' -port 443 </dev/null',
	  'grep' => [ 'O=Test SSL shared domain', 'CN=(\\*\\.)?'.$test_domain ],
	},

	# Try to create a domain on the same IP with a conflicting name,
	# which should fail.
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'desc', 'Test SSL shared clash' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ], [ 'ssl' ],
		      [ 'parent', $test_domain ],
		      [ 'shared-ip', '$SHARED_IP' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test SSL shared clash' ],
		      @create_args, ],
	  'fail' => 1,
        },

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1,
	},

	# Remove the shared IP
	{ 'command' => 'delete-shared-address.pl',
	  'args' => [ [ 'ip', '$SHARED_IP' ], [ 'deactivate' ] ],
	  'cleanup' => 1,
	},
	];

# Tests for concurrent domain creation
$parallel_tests = [
	# Create a domain not in parallel
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test serial domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test serial home page' ],
		      @create_args, ],
        },

	# Create two domains in background processes
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ],
		      [ 'desc', 'Test parallel domain 1' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test parallel 1 home page' ],
		      @create_args, ],
	  'background' => 1,
        },
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ],
		      [ 'desc', 'Test parallel domain 2' ],
		      [ 'parent', $test_domain ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      [ 'mail' ], [ 'mysql' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test parallel 2 home page' ],
		      @create_args, ],
	  'background' => 2,
        },

	# Wait for background processes to complete
	{ 'wait' => [ 1, 2 ] },

	# Make sure the domains were created
	{ 'command' => 'list-domains.pl',
	  'grep' => [ "^$test_parallel_domain1", "^$test_parallel_domain2" ],
	},

	# Validate all the domains
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'domain' => $test_parallel_domain1 ],
		      [ 'domain' => $test_parallel_domain2 ],
		      [ 'all-features' ] ],
	},

	# Delete the two domains in background processes
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain1 ] ],
	  'background' => 3,
	},
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_parallel_domain2 ] ],
	  'background' => 4,
	},

	# Wait for background processes to complete
	{ 'wait' => [ 3, 4 ] },

	# Make sure the domains were deleted
	{ 'command' => 'list-domains.pl',
	  'antigrep' => [ "^$test_parallel_domain1",
			  "^$test_parallel_domain2" ],
	},

	# Validate the parent domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'all-features' ] ],
	},

	# Remove the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$plans_tests = [
	# Create a test plan
	{ 'command' => 'create-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 7777 ],
		      [ 'admin-quota', 8888 ],
		      [ 'max-doms', 7 ],
		      [ 'max-bw', 77777777 ],
		      [ 'features', 'mail dns web' ],
		      [ 'capabilities', 'users aliases scripts' ],
		      [ 'nodbname' ] ],
	},

	# Make sure it worked
	{ 'command' => 'list-plans.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 7777',
		      'Administrator block quota: 8888',
		      'Maximum doms: 7',
		      'Maximum bw: 77777777',
		      'Allowed features: mail dns web',
		      'Edit capabilities: users aliases scripts',
		      'Can choose database names: No' ],
	},

	# Modify the plan
	{ 'command' => 'modify-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 8888 ],
		      [ 'no-admin-quota' ],
		      [ 'max-doms', 8 ],
		      [ 'auto-features' ],
		      [ 'auto-capabilities' ],
		      [ 'no-nodbname' ] ],
	},

	# Make sure the modification worked
	{ 'command' => 'list-plans.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 8888',
		      'Administrator block quota: Unlimited',
		      'Maximum doms: 8',
		      'Maximum bw: 77777777',
		      'Allowed features: Automatic',
		      'Edit capabilities: Automatic',
		      'Can choose database names: Yes' ],
	},

	# Delete the plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	},

	# Make sure it is gone
	{ 'command' => 'list-plans.pl',
	  'antigrep' => $plan_name,
	},

	# Re-create it
	{ 'command' => 'create-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 7777 ],
		      [ 'admin-quota', 8888 ],
		      [ 'max-doms', 7 ],
		      [ 'max-bw', 77777777 ],
		      [ 'features', 'mail dns web' ],
		      [ 'capabilities', 'users aliases scripts' ],
		      [ 'nodbname' ] ],
	},
	
	# Create a domain on the plan
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ],
		      [ 'plan', $test_plan ],
		      @create_args, ],
        },

	# Make sure the plan limits were applied
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 7777',
		      'User block quota: 8888',
		      'Maximum sub-servers: 7',
		      'Bandwidth limit: 74.17',
		      'Allowed features: mail dns web',
		      'Edit capabilities: users aliases scripts',
		      'Can choose database names: No' ],
	},

	# Modify the plan and apply
	{ 'command' => 'modify-plan.pl',
	  'args' => [ [ 'name', $test_plan ],
		      [ 'quota', 8888 ],
		      [ 'no-admin-quota' ],
		      [ 'max-doms', 8 ],
		      [ 'max-bw', 88888888 ],
		      [ 'features', 'mail dns web webalizer' ],
		      [ 'no-nodbname' ],
		      [ 'apply' ] ],
	},

	# Verify the new limits on the domain
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Server block quota: 8888',
		      'User block quota: Unlimited',
		      'Maximum sub-servers: 8',
		      'Bandwidth limit: 84.77',
		      'Allowed features: mail dns web webalizer',
		      'Can choose database names: Yes' ],
	},

	# Remove the domain and plan
	{ 'command' => 'delete-plan.pl',
	  'args' => [ [ 'name', $test_plan ] ],
	  'cleanup' => 1 },
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

$plugin_tests = [
	# Create a domain on the plan
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test home page' ],
		      @create_args, ],
        },

	# Test Mailman plugin enable
	&indexof('virtualmin-mailman', @plugins) >= 0 ? (
		# Turn on mailman feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-mailman' ] ]
		},

		# Test mailman URL
		{ 'command' => $wget_command.'http://'.$test_domain.'/mailman/listinfo',
		  'grep' => 'Mailing Lists',
		},

		# Turn off mailman feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-mailman' ] ]
		},
		) :
		( { 'command' => 'echo Mailman plugin not enabled' }
		),

	# Test AWstats plugin
	&indexof('virtualmin-awstats', @plugins) >= 0 ? (
		# Turn on awstats feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-awstats' ] ]
		},

		# Test AWstats web UI
		{ 'command' => $wget_command.'http://'.$test_domain_user.':smeg@'.$test_domain.'/cgi-bin/awstats.pl',
		  'grep' => 'AWStats',
		},

		# Check for Cron job
		{ 'command' => 'crontab -l',
		  'grep' => 'awstats.pl '.$test_domain
		},

		# Turn off mailman feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-awstats' ] ]
		},
		) :
		( { 'command' => 'echo AWstats plugin not enabled' }
		),

	# Test SVN plugin
	&indexof('virtualmin-svn', @plugins) >= 0 ? (
		# Turn on SVN feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-svn' ] ]
		},

		# Test SVN URL
		{ 'command' => $wget_command.'-S http://'.$test_domain.'/svn',
		  'ignorefail' => 1,
		  'grep' => 'Authorization Required',
		},

		# Check for SVN config files
		{ 'command' => 'cat ~'.$test_domain_user.'/etc/svn-access.conf',
		},
		{ 'command' => 'cat ~'.$test_domain_user.'/etc/svn.*.passwd',
		},

		# Turn off SVN feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-svn' ] ]
		},
		) :
		( { 'command' => 'echo SVN plugin not enabled' }
		),

	# Test DAV plugin
	&indexof('virtualmin-dav', @plugins) >= 0 ? (
		# Turn on SVN feature
		{ 'command' => 'enable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-dav' ] ]
		},

		# Test DAV URL
		{ 'command' => $wget_command.'-S http://'.$test_domain_user.':smeg@'.$test_domain.'/dav/',
		},

		# Turn off SVN feature
		{ 'command' => 'disable-feature.pl',
		  'args' => [ [ 'domain', $test_domain ],
			      [ 'virtualmin-dav' ] ]
		},
		) :
		( { 'command' => 'echo DAV plugin not enabled' }
		),

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1 },
	];

# Website API tests
$web_tests = [
	# Create a domain on the shared IP
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test shared domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test web page' ],
		      @create_args, ],
	},

	# Enable matchall
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'matchall' ] ],
	},

	# Test foo.domain wget
	{ 'command' => $wget_command.'http://foo.'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Disable matchall
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-matchall' ] ],
	},

	# Test foo.domain wget, which should fail now
	{ 'command' => $wget_command.'http://foo.'.$test_domain,
	  'fail' => 1,
	},

	# Enable proxying
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'proxy', 'http://www.google.com/' ] ],
	},

	# Test wget for proxy
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Google',
	},

	# Disable proxying
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-proxy' ] ],
	},

	# Test wget to make sure proxy is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'antigrep' => 'Google',
	},

	# Enable frame forwarding
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'framefwd', 'http://www.google.com/' ] ],
	},

	# Test wget for frame
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => [ 'http://www.google.com/', 'frame' ],
	},

	# Disable frame forwarding
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'no-framefwd' ] ],
	},

	# Test wget to make sure frame is gone
	{ 'command' => $wget_command.'http://'.$test_domain,
	  'grep' => 'Test web page',
	},

	# Make this the default website
	{ 'command' => 'modify-web.pl',
	  'args' => [ [ 'domain' => $test_domain ],
		      [ 'default-website' ] ],
	},

	# Test request to IP
	{ 'command' => $wget_command.'http://'.$test_ip_address,
	  'grep' => 'Test web page',
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$ip6_tests = [
	# Create a domain with an IPv6 address
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test IPv6 domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ],
		      [ 'allocate-ip6' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test IPv6 home page' ],
		      @create_args, ],
	},

	# Delay needed for v6 address to become routable
	{ 'command' => 'sleep 10' },

	# Test DNS lookup for v6 entry
	{ 'command' => 'host '.$test_domain,
	  'grep' => 'IPv6 address',
	},

	# Test HTTP get to v6 address
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Test removal of v6 address
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'no-ip6' ] ],
	},

	# Make sure DNS entries are gone
	{ 'command' => 'host '.$test_domain,
	  'antigrep' => 'IPv6 address',
	},

	# Make sure HTTP get to v6 address no longer works
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'fail' => 1,
	},

	# But v4 address should still work
	{ 'command' => $wget_command.' --inet4 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Re-allocate an address
	{ 'command' => 'modify-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'allocate-ip6' ] ],
	},

	# Re-check HTTP get
	{ 'command' => $wget_command.' --inet6 http://'.$test_domain,
	  'grep' => 'Test IPv6 home page',
	},

	# Cleanup the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];
if (!&supports_ip6()) {
	$ip6_tests = [ { 'command' => 'echo IPv6 is not supported' } ];
	}

# Tests for renaming a virtual server
$rename_tests = [
	# Create a domain that will get renamed
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test rename domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'mysql' ], [ 'status' ], [ 'spam' ], [ 'virus' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test rename page' ],
		      @create_args, ],
	},

	# Create a mailbox
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Create an alias
	{ 'command' => 'create-alias.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'from', $test_alias ],
		      [ 'to', 'nobody@virtualmin.com' ] ],
	},

	# Get the domain ID
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'id-only' ] ],
	  'save' => 'DOMID',
	},

	# Call the rename CGI
	{ 'command' => $webmin_wget_command.
		       "${webmin_proto}://localhost:${webmin_port}/virtual-server/rename.cgi\\?dom=\$DOMID\\&new=$test_rename_domain\\&user_mode=1\\&home_mode=1\\&group_mode=1",
	   'grep' => 'Saving server details',
	},

	# Validate the domain
	{ 'command' => 'validate-domains.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'all-features' ] ],
	},

	# Make sure DNS works
	{ 'command' => 'host '.$test_rename_domain,
	  'grep' => &get_default_ip(),
	},

	# Make sure website works
	{ 'command' => $wget_command.'http://'.$test_rename_domain,
	  'grep' => 'Test rename page',
	},

	# Make sure MySQL login works
	{ 'command' => 'mysql -u '.$test_rename_domain_user.' -psmeg '.$test_domain_db.' -e "select version()"',
	},

	# Validate renamed mailbox
	{ 'command' => 'list-users.pl',
	  'args' => [ [ 'domain' => $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ 'Unix username: '.$test_rename_full_user ],
	},
	
	# Validate renamed alias
	{ 'command' => 'list-aliases.pl',
	  'args' => [ [ 'domain', $test_rename_domain ],
		      [ 'multiline' ] ],
	  'grep' => [ '^'.$test_alias.'@'.$test_rename_domain ],
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_rename_domain ] ],
	  'cleanup' => 1
        },
	];

# Tests for web, mail and FTP bandwidth accounting.
# Uses a different domain to prevent re-reading of old mail logs.
$test_bw_domain = time().$test_domain;
$test_bw_domain_user = time().$test_domain_user;
$bw_tests = [
	# Create a domain for bandwidth loggin
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'user', $test_bw_domain_user ],
		      [ 'prefix', $prefix ],
		      [ 'desc', 'Test rename domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test bandwidth page' ],
		      @create_args, ],
	},

	# Run bw.pl once to skip to the end of logs
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Create a 1M file in the domain's directory
	{ 'command' => 'dd if=/dev/zero of=/home/'.$test_bw_domain_user.'/public_html/huge bs=1024 count=1024 && chown '.$test_bw_domain_user.': /home/'.$test_bw_domain_user.'/public_html/huge',
	},

	# Fetch the file 5 times with wget
	{ 'command' => join(" ; ", map { $wget_command.'http://'.$test_bw_domain.'/huge >/dev/null' } (0..4)),
	},

	# Fetch 1 time with FTP
	{ 'command' => $wget_command.
		       'ftp://'.$test_bw_domain_user.':smeg@localhost/public_html/huge >/dev/null',
	},

	# Create a 1M test file
	{ 'command' => '(cat '.$ok_email_file.' ; head -c250000 /dev/zero | od -c -v) >/tmp/random.txt',
	},

	# Send email to the domain's user
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_bw_domain_user.'@'.$test_bw_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Check IMAP for admin mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check POP3 for admin mailbox
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_bw_domain_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Run bw.pl on this domain
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Check separate web, FTP and mail usage
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'grep' => [ 'web:5[0-9]{6}',
		      'ftp:1[0-9]{6}',
		      'mail:1[0-9]{6}', ],
	},

	# Get usage from list-domains
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Bandwidth usage: 7(\\.[0-9]+)?\s+MB',
	},

	# Create a sub-server
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_subdomain ],
		      [ 'parent', $test_bw_domain ],
		      [ 'prefix', 'example2' ],
		      [ 'desc', 'Test sub-domain' ],
		      [ 'dir' ], [ 'web' ], [ 'dns' ],
		      @create_args, ],
	},

	# Create a 1M file in the sub-domain's directory
	{ 'command' => 'dd if=/dev/zero of=/home/'.$test_bw_domain_user.'/domains/'.$test_subdomain.'/public_html/huge bs=1024 count=1024 && chown '.$test_bw_domain_user.': /home/'.$test_bw_domain_user.'/domains/'.$test_subdomain.'/public_html/huge',
	},

	# Fetch the file 5 times with wget
	{ 'command' => join(" ; ", map { $wget_command.'http://'.$test_subdomain.'/huge >/dev/null' } (0..4)),
	},

	# Run bw.pl on the parent domain
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Check web usage in sub-domain
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_subdomain ] ],
	  'grep' => [ 'web:5[0-9]{6}' ],
	},

	# Get usage from list-domains again
	{ 'command' => 'list-domains.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'multiline' ] ],
	  'grep' => 'Bandwidth usage: 12(\\.[0-9]+)?\s+MB',
	},

	# Check separate usage in parent domain
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'include-subservers' ] ],
	  'grep' => [ 'web:10[0-9]{6}',
		      'ftp:1[0-9]{6}',
		      'mail:1[0-9]{6}', ],
	},

	# Create a mailbox with FTP access
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_bw_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 100*1024 ],
		      [ 'ftp' ],
		      [ 'mail-quota', 100*1024 ] ],
	},

	# Send a 1M email to it
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_bw_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Check IMAP for mailbox
	{ 'command' => 'test-imap.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Check POP3 for mailbox
	{ 'command' => 'test-pop3.pl',
	  'args' => [ [ 'user', $test_full_user ],
		      [ 'pass', 'smeg' ],
		      [ 'server', &get_system_hostname() ] ],
	},

	# Re-run bw.pl to pick up that email
	{ 'command' => $module_config_directory.'/bw.pl '.$test_bw_domain,
	},

	# Check that the email was counted
	{ 'command' => 'list-bandwidth.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'grep' => [ 'mail:2[0-9]{6}', ],
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_bw_domain ] ],
	  'cleanup' => 1
        },
	];

$blocks_per_mb = int(1024*1024 / &quota_bsize("home"));
$quota_tests = [
	# Create a domain with a 10M quota
	{ 'command' => 'create-domain.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'desc', 'Test quota domain' ],
		      [ 'pass', 'smeg' ],
		      [ 'quota', 10*$blocks_per_mb ],
		      [ 'uquota', 10*$blocks_per_mb ],
		      [ 'dir' ], [ 'unix' ], [ 'web' ], [ 'dns' ], [ 'mail' ],
		      [ 'style' => 'construction' ],
		      [ 'content' => 'Test quota page' ],
		      (grep { $_->[0] ne 'limits-from-plan' } @create_args), ],
	},

	# Make sure 20M file creation fails
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=20480'",
	  'fail' => 1,
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Make sure 5M file creation works
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=5120'",
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Up quota to 30M
	{ 'command' => 'modify-domain.pl',
 	  'args' => [ [ 'domain', $test_domain ],
		      [ 'quota', 30*$blocks_per_mb ],
		      [ 'uquota', 30*$blocks_per_mb ],
		    ],
	},

	# Make sure 20M file creation now works
	{ 'command' => "su $test_domain_user -c 'dd if=/dev/zero of=/home/$test_domain_user/junk bs=1024 count=20480'",
	},
	{ 'command' => "rm -f /home/$test_domain_user/junk" },

	# Create a mailbox with 5M quota
	{ 'command' => 'create-user.pl',
	  'args' => [ [ 'domain', $test_domain ],
		      [ 'user', $test_user ],
		      [ 'pass', 'smeg' ],
		      [ 'desc', 'Test user' ],
		      [ 'quota', 5*$blocks_per_mb ],
		      [ 'mail-quota', 5*$blocks_per_mb ] ],
	},

	# Make sure 20M file creation fails
	{ 'command' => &command_as_user($test_full_user, 0, "dd if=/dev/zero of=/home/$test_domain_user/homes/$test_user/junk bs=1024 count=20480"),
	  'fail' => 1,
	},
	{ 'command' => "rm -f /home/$test_domain_user/homes/$test_user/junk" },

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send one email to him, so his mailbox gets created and then procmail
	# runs as the right user. This is to work around a procmail bug where
	# it can drop privs too soon!
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', $ok_email_file ] ],
	},

	# Check procmail log for delivery, for at most 60 seconds
	{ 'command' => 'while [ "`tail -5 /var/log/procmail.log | grep '.
		       'To:'.$test_user.'@'.$test_domain.'`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	  'ignorefail' => 1,
	},

	# Create a large test email
	{ 'command' => '(cat '.$ok_email_file.' ; head -c2000000 /dev/zero | od -c -v) >/tmp/random.txt',
	},

	# Add empty lines to procmail.log, to prevent later false matches
	{ 'command' => '(echo ; echo ; echo ; echo ; echo) >>/var/log/procmail.log',
	},

	# Send email to the new mailbox, which won't get delivered
	{ 'command' => 'test-smtp.pl',
	  'args' => [ [ 'from', 'jcameron@webmin.com' ],
		      [ 'to', $test_user.'@'.$test_domain ],
		      [ 'data', '/tmp/random.txt' ] ],
	},

	# Wait for delivery to fail due to lack of quota
	{ 'command' => 'while [ "`tail -10 /var/log/procmail.log | grep '.
		       'Quota.exceeded`" = "" ]; do '.
		       'sleep 5; done',
	  'timeout' => 60,
	},

	# Get rid of the domain
	{ 'command' => 'delete-domain.pl',
	  'args' => [ [ 'domain', $test_domain ] ],
	  'cleanup' => 1
        },
	];

$alltests = { 'domains' => $domains_tests,
	      'web' => $web_tests,
	      'mailbox' => $mailbox_tests,
	      'alias' => $alias_tests,
	      'aliasdom' => $aliasdom_tests,
	      'reseller' => $reseller_tests,
	      'script' => $script_tests,
	      'database' => $database_tests,
	      'proxy' => $proxy_tests,
	      'migrate' => $migrate_tests,
	      'move' => $move_tests,
	      'backup' => $backup_tests,
	      'multibackup' => $multibackup_tests,
	      'remotebackup' => $remotebackup_tests,
	      'purge' => $purge_tests,
	      'incremental' => $incremental_tests,
              'mail' => $mail_tests,
	      'prepost' => $prepost_tests,
	      'webmin' => $webmin_tests,
	      'remote' => $remote_tests,
	      'ssl' => $ssl_tests,
	      'shared' => $shared_tests,
	      'wildcard' => $wildcard_tests,
	      'parallel' => $parallel_tests,
	      'plans' => $plans_tests,
	      'plugin' => $plugin_tests,
	      'ip6' => $ip6_tests,
	      'rename' => $rename_tests,
	      'bw' => $bw_tests,
	      'quota' => $quota_tests,
	    };

# Run selected tests
$total_failed = 0;
if (!@tests) {
	@tests = sort { $a cmp $b } (keys %$alltests);
	}
@tests = grep { &indexof($_, @skips) < 0 } @tests;
@failed_tests = ( );
foreach $tt (@tests) {
	print "Running $tt tests ..\n";
	@tts = @{$alltests->{$tt}};
	$allok = 1;
	$count = 0;
	$failed = 0;
	$total = 0;
	local $i = 0;
	foreach $t (@tts) {
		$t->{'index'} = $i++;
		}
	if ($migrate) {
		# Limit migration tests to one type
		@tts = grep { !$_->{'migrate'} ||
			      $_->{'migrate'} eq $migrate } @tts;
		}
	$lastt = undef;
	foreach $t (@tts) {
		$lastt = $t;
		$total++;
		$ok = &run_test($t);
		if (!$ok) {
			$allok = 0;
			$failed++;
			last;
			}
		$count++;
		}
	if (!$allok && ($count || $lastt->{'always_cleanup'}) && !$no_cleanup) {
		# Run cleanups
		@cleaners = grep { $_->{'cleanup'} &&
				    $_->{'index'} >= $lastt->{'index'} } @tts;
		foreach $cleaner (@cleaners) {
			if ($cleaner ne $lastt) {
				$total++;
				&run_test($cleaner);
				}
			}
		}
	$skip = @tts - $total;
	print ".. $count OK, $failed FAILED, $skip SKIPPED\n\n";
	$total_failed += $failed;
	if ($failed) {
		push(@failed_tests, $tt);
		}
	}

if ($total_failed) {
	print "!!!!!!!!!!!!! $total_failed TESTS FAILED !!!!!!!!!!!!!!\n";
	print "!!!!!!!!!!!!! FAILURES : ",join(" ", @failed_tests,),"\n";
	}
exit($total_failed);

sub run_test
{
local ($t) = @_;
if ($t->{'wait'}) {
	# Wait for a background process to exit
	local @waits = ref($t->{'wait'}) ? @{$t->{'wait'}} : ( $t->{'wait'} );
	local $ok = 1;
	foreach my $w (@waits) {
		print "    Waiting for background process $w ..\n";
		local $pid = $backgrounds{$w};
		if (!$pid) {
			print "    .. already exited, or never started!\n";
			$ok = 0;
			}
		waitpid($pid, 0);
		if ($?) {
			print "    .. PID $pid failed : $?\n";
			$ok = 0;
			}
		else {
			print "    .. PID $pid done\n";
			}
		delete($backgrounds{$w});
		}
	return $ok;
	}
elsif ($t->{'background'}) {
	# Run a test, but in the background
	print "    Backgrounding test ..\n";
	local $pid = fork();
	if ($pid < 0) {
		print "    .. fork failed : $!\n";
		return 0;
		}
	if (!$pid) {
		local $rv = &run_test_command($t);
		exit($rv ? 0 : 1);
		}
	$backgrounds{$t->{'background'}} = $pid;
	print "    .. backgrounded as $pid\n";
	return 1;
	}
else {
	# Run a regular test command
	return &run_test_command($t);
	}
}

sub run_test_command
{
local $cmd = "$t->{'command'}";
foreach my $a (@{$t->{'args'}}) {
	if (defined($a->[1])) {
		if ($a->[1] =~ /\s/) {
			$cmd .= " --".$a->[0]." '".$a->[1]."'";
			}
		else {
			$cmd .= " --".$a->[0]." ".$a->[1];
			}
		}
	else {
		$cmd .= " --".$a->[0];
		}
	}
print "    Running $cmd ..\n";
sleep($t->{'sleep'});
if ($gconfig{'os_type'} !~ /-linux$/ && &has_command("bash")) {
	# Force use of bash
	$cmd = "bash -c ".quotemeta($cmd);
	}
local $out = &backquote_with_timeout("($cmd) 2>&1 </dev/null",
				     $t->{'timeout'} || $timeout);
if (!$t->{'ignorefail'}) {
	if ($? && !$t->{'fail'} || !$? && $t->{'fail'}) {
		print $out;
		if ($t->{'fail'}) {
			print "    .. failed to fail\n";
			}
		else {
			print "    .. failed : $?\n";
			}
		return 0;
		}
	}
if ($t->{'grep'}) {
	# One line must match all regexps
	local @greps = ref($t->{'grep'}) ? @{$t->{'grep'}} : ( $t->{'grep'} );
	foreach my $grep (@greps) {
		$grep = &substitute_template($grep, \%saved_vars);
		local $match = 0;
		foreach my $l (split(/\r?\n/, $out)) {
			if ($l =~ /$grep/) {
				$match = 1;
				}
			}
		if (!$match) {
			print $out;
			print "    .. no match on $grep\n";
			return 0;
			}
		}
	}
if ($t->{'antigrep'}) {
	# No line must match all regexps
	local @greps = ref($t->{'antigrep'}) ? @{$t->{'antigrep'}}
					     : ( $t->{'antigrep'} );
	foreach my $grep (@greps) {
		$grep = &substitute_template($grep, \%saved_vars);
		local $match = 0;
		foreach my $l (split(/\r?\n/, $out)) {
			if ($l =~ /$grep/) {
				$match = 1;
				}
			}
		if ($match) {
			print $out;
			print "    .. unexpected match on $grep\n";
			return 0;
			}
		}
	}
print $out if ($output);
if ($t->{'save'}) {
	# Save output to variable
	$out =~ s/^\s*//;
	$out =~ s/\s*$//;
	$ENV{$t->{'save'}} = $out;
	$saved_vars{$t->{'save'}} = $out;
	print "    .. saved $t->{'save'} value $out\n";
	}
print $t->{'fail'} ? "    .. successfully failed\n"
		   : "    .. success\n";
return 1;
}

sub usage
{
print "$_[0]\n\n" if ($_[0]);
local $mig = join("|", @migration_types);
print "Runs some or all Virtualmin functional tests.\n";
print "\n";
print "usage: functional-tests.pl [--domain test.domain]\n";
print "                           [--test type]*\n";
print "                           [--skip-test type]*\n";
print "                           [--no-cleanup]\n";
print "                           [--output]\n";
print "                           [--migrate $mig]\n";
print "                           [--user webmin-login --pass password]\n";
exit(1);
}


