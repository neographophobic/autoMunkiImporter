#!/usr/bin/perl

######## NAME #################################################################
# autoMunkiImporter.pl - Automatically import apps into Munki

######## DESCRIPTION ##########################################################
# This script will, based on the input data, determine if there is a new 
# version of an application available. If a new version is available it will 
# download the new file, extract it, and then import it into Munki.

# It can handle static URLs, dynamic URLs where the URL or link to the URL 
# changes based off the version (it can also handle landing pages before the 
# actual download), and Sparkle RSS feeds. This generic approach should allow 
# you to monitor most applications.

# It supports downloads in flat PKGs, DMG (including support for disk images 
# with licence agreements), ZIP, TAR, TAR.GZ, TGZ, and TBZ. It will import a 
# single item (Application or PKG) from anywhere within the download, so the 
# content doesn't have to be in the top level folder. This is achieved by using 
# find to locate the item (e.g. the Adobe Flash Player.pkg from within the 
# Adobe Flash download).

######### COMMENTS ############################################################
# Detailed documentation is provided at the end of the script and at the
# associated website located at:-
# http://neographophobic.github.com/autoMunkiImporter/index.html

# The best way of accessing the documentation within this script is via:-

# perldoc /path/to/autoMunkiImporter.pl

######### LICENCE #############################################################
# The licence for this script is included in the documentation at the end of
# the script. It's licensed under the BSD 3-Clause Licence. 

######### AUTHOR ##############################################################
# Adam Reed <adam.reed@anu.edu.au>

# Import Perl Modules, additional non standard modules are imported via 
# the checkPerlDependencies() function
use strict;
use warnings;
use version;
use Foundation;
use URI::Escape;
use URI::URL;
use File::Temp;
use File::Basename;
use File::Copy;
use Getopt::Long;
use Pod::Usage;
use POSIX;
use Term::UI;
use Term::ReadLine;

###############################################################################
# User Editable Configuration Variables
###############################################################################

# Default User Settings file
my $defaultSettingsPlistPath = "/Library/Application Support/autoMunkiImporter/_DefaultSettings.plist";

# Default Log fole
my $logFile = "/Library/Logs/autoMunkiImporter/autoMunkiImporter.log";

# Declare paths to required tools
my %tools = ();
$tools{'curl'} = "/usr/bin/curl";
$tools{'munkiimport'} = "/usr/local/munki/munkiimport";
$tools{'makecatalogs'} = "/usr/local/munki/makecatalogs";
$tools{'grep'} = "/usr/bin/grep";
$tools{'ditto'} = "/usr/bin/ditto";
$tools{'tar'} = "/usr/bin/tar";
$tools{'find'} = "/usr/bin/find";
$tools{'hdiutil'} = "/usr/bin/hdiutil";
$tools{'echo'} = "/bin/echo";
$tools{'awk'} = "/usr/bin/awk";
$tools{'cp'} = "/bin/cp";
$tools{'yes'} = "/usr/bin/yes";
$tools{'plutil'} = "/usr/bin/plutil";
$tools{'git'} = "/usr/bin/git";			# Used if git support is enabled
$tools{'make'} = "/usr/bin/make";		# Used when installing perl modules
$tools{'gcc'} = "/usr/bin/gcc";			# Used when installing perl modules
$tools{'perl'} = "/usr/bin/perl";		# Used when installing perl modules

# CPANM location
my $cpanmURL = "http://cpanmin.us";

###############################################################################
# Configuration Variables - Don't change
###############################################################################

# Data Plists
my @dataPlists = ();
my $dataPlistPath = undef;
my $dataPlist = undef;
my $type = undef;
my $dataPlistSourceIsDir = 0; # Whether the data plist(s) came from a dir listing

# Status Plist
my $statusPlist = undef;

# Default User Settings Plist
my $defaultSettingsPlist = undef;

# Script version
my $scriptVersion = "v0.3.0";

# Munki Repo Path
my $repo_path = undef;

# Command Line options 
my $downloadOnly = 0; # Do a download only, without importing the package (0 = false)
my $verbose = 0; # Verbose output to STDOUT in addition to the log (0 = false)
my $silent = 0; # Suppress all output (0 = false)
my $help = 0; # Show help info (0 = false)
my $reset = 0; # Reset the modification date (0 = false)
my $ignoreModDate = 0; # Ignore modification date (0 = false)
my $installPerlDependencies = 0; # Whether to attempt to install perl modules (0 = false)
my $forceInstallPerlDependencies = 0; # Whether to force install perl modules (0 = false)
my $showScriptVersion = 0; # Show script version (0 = false)
my $testScript = 0; # Test the script has the appropriate items (0 = false)

# Global Variables for Default User Settings
my $name = undef;					# App Name for item being imported
my $userAgent = undef; 				# Web User Agent to present to sites
my $userCookie = undef;             # User Cookie present to sites
my $logFileMaxSizeInMBs = undef;	# Upper size of log files before they are rolled
my $maxNoOfLogsToKeep = undef;		# No of log files to preserve
my $emailReports = undef;			# Whether to email reports (0 = false, 1 = true)
my $fromAddress = undef;			# From email address for reports
my $toAddress = undef				# To email address for reports
my $smtpServer = undef;				# SMTP Server to use for email reports
my $subjectPrefix = undef;			# Prefix for subject line of email reports
my $statusPlistPath = undef;		# Path to the status plist
my $makecatalogs = undef;			# Whether to run makecatalogs (0 = false, 1 = true)
my $gitEnabled = undef;             # Whether to add and commit to git any updated packages
my $gitPullAndPush = undef;         # Whether to pull and push to a remote git repo

# Supported Download Types
my @supportedDownloadTypes = ("pkg", "mpkg", "dmg", "zip", "tar", "tar.gz", "tgz", "tbz");

# Logging level and constants
my $logLevel = undef;
use constant {
    LOG         => 1,
    LOG_WARNING => 2,
    LOG_ERROR   => 3,
    LOG_NORMAL  => 4,
    LOG_VERBOSE => 5,
    LOG_DEBUG   => 6,
    LOG_SILENT  => 7,
};

###############################################################################
# Helper Functions - Dependencies
###############################################################################

sub installPerlDependencies {
	# Disable Silent mode if enabled
	if ($logLevel == LOG_SILENT) {
		$logLevel = LOG_NORMAL;
	}

	# Check for the Xcode command line tools.
	if ( ! -e $tools{'make'} || ! -e $tools{'gcc'} ) {
		logMessage(LOG_ERROR, "Installation of Perl Modules requires the Xcode Command Line tools to be installed.", $logFile);
		logMessage(LOG_ERROR, " - Please install these tools and try again. If the tools are installed, update the scripts ", $logFile);
		logMessage(LOG_ERROR, "   location for make and gcc. ", $logFile);
		exit 1;
	}
	
	# Check for cURL
	if ( ! -e $tools{'curl'} ) {
		logMessage(LOG_ERROR, "cURL not found at $tools{'curl'}. cURL is required to install the perl modules", $logFile);
		exit 1;
	}

	if (! $forceInstallPerlDependencies ) {
		# Prompt user to continue
		logMessage(LOG_WARNING, "You are attempting to install the required Perl modules...", $logFile);
		logMessage(LOG_WARNING, "This uses the CPANM script from $cpanmURL, and will prompt for a root password to install the modules at the system level", $logFile);
	
		my $question = Term::ReadLine->new('');
		my $answer = $question->ask_yn(
							prompt => 'Are you sure you would like to continue?',
							default => 'n',
					 );
		
		if (! $answer ) {
			# User selected no - so bail
			logMessage(LOG, "Exited without attempting to install the modules...", $logFile);
			exit 0;
		} else {
			logMessage(LOG, "Attempting installation of require Perl Modules and their dependencies...", $logFile);
		}
	}
	
	# Download CPANM
 	my $cpanmTempFile = File::Temp->new();
 	my $cpanm = $cpanmTempFile->filename;	
	system("$tools{'curl'} --location -o $cpanm $cpanmURL");
	
	# Check download is a valid perl script
	system("$tools{'perl'} -c $cpanm 2> /dev/null");
	if ( $? >> 8 != 0 ) {
		logMessage(LOG_ERROR, "CPANM download from $cpanmURL has failed... Please manually check the URL leads to a valid perl script, or installing the required modules via normal CPAN.", $logFile);
		exit 1;		
	} else {
		# It is so set it to being executable
		chmod 0755, $cpanm;
	}
	
	# Attempt to install the required modules and any associated dependencies
	my $moduleInstallOutput = "";
	my $quietMode = "--quiet";
	if ($logLevel == LOG_VERBOSE) {
		$quietMode = "";
	} elsif ($logLevel > LOG_VERBOSE) {
		$quietMode = "--verbose";
	}

	logMessage(LOG, "Installing Date::Parse", $logFile);
	$moduleInstallOutput = `$cpanm --sudo $quietMode Date::Parse 2>&1`;
	logMessage(LOG, $moduleInstallOutput, $logFile);

	logMessage(LOG, "Installing Mail::Mailer", $logFile);
	$moduleInstallOutput = `$cpanm --sudo $quietMode Mail::Mailer 2>&1`;
	logMessage(LOG, $moduleInstallOutput, $logFile);

	logMessage(LOG, "Installing URI::Escape", $logFile);
	$moduleInstallOutput = `$cpanm --sudo $quietMode URI::Escape 2>&1`;
	logMessage(LOG, $moduleInstallOutput, $logFile);

	logMessage(LOG, "Installing URI::URL", $logFile);
	$moduleInstallOutput = `$cpanm --sudo $quietMode URI::URL 2>&1`;
	logMessage(LOG, $moduleInstallOutput, $logFile);

	logMessage(LOG, "Installing WWW::Mechanize", $logFile);
	$moduleInstallOutput = `$cpanm --sudo $quietMode WWW::Mechanize 2>&1`;
	logMessage(LOG, $moduleInstallOutput, $logFile);

	logMessage(LOG, "Attempted installation of required modules complete...", $logFile);

	# Run the check to determine if it's worked or not
	my $dependencyCheck = checkPerlDependencies();
	if ($dependencyCheck) {
		logMessage(LOG, "All of the required perl modules have been sucessfully installed...", $logFile);
		exit 0;
	} else {
		exit 1;
	}
}

sub checkPerlDependencies {
	my $missingDependencies = 0;
	my $perlPlistLib = dirname($0) . "/perlplist.pl";
	
	logMessage(LOG_DEBUG, "Checking Perl Dependencies", $logFile);

	eval { require Date::Parse;    }; $missingDependencies = 1 if $@;
	eval { require Mail::Mailer;   }; $missingDependencies = 1 if $@;
	eval { require URI::Escape;    }; $missingDependencies = 1 if $@;
	eval { require URI::URL;       }; $missingDependencies = 1 if $@;
	eval { require WWW::Mechanize; }; $missingDependencies = 1 if $@;
	
	if ($missingDependencies) {
		logMessage(LOG_ERROR, "Required Perl Modules were not found (you can attempt to install them by running autoMunkiImporter.pl --install-dependencies ).", $logFile);
		logMessage(LOG_ERROR, " - Please ensure that Date::Parse, Mail::Mailer, URI::Escape, URI::URL, and WWW::Mechanize are installed.", $logFile);
		exit 1;
	} else {
		eval { require $perlPlistLib;  }; $missingDependencies = 1 if $@;
		if ($missingDependencies) {
			logMessage(LOG_ERROR, "perlplist.pl needs to be in the same directory as this script.", $logFile);
			exit 1;
		} else {
			use Date::Parse;
			return 1;
		}
	}
		
	return 0;
}

sub checkMunkiRepoIsAvailable {

	logMessage(LOG_DEBUG, "Determining Munki Repo Location", $logFile);

	# Get the Munki Repo Path from the munkiimport --config plist
	my $munkiImportConfigPlist = loadDefaults( expandFilePath("~/Library/Preferences/com.googlecode.munki.munkiimport.plist") );
	if ( ! defined($munkiImportConfigPlist)) {
		# Error reading the Munki Import Config Plist. Display an error and exit
		logMessage(LOG_ERROR, "Munki Repo path can't be found because the munkiimport plist file can't be read.", $logFile);
		sendEmail(subject => "ERROR: Repo not found", message => "Munki Repo could not be found because the munkiimport plist file can't be read. Script terminated...");

		exit 1;
	} else {
		$repo_path = perlValue(getPlistObject($munkiImportConfigPlist, "repo_path"));
		logMessage(LOG_VERBOSE, "Using Munki Repo: $repo_path", $logFile);

		if ( -d "$repo_path" && -w "$repo_path/pkgs" && -w "$repo_path/pkgsinfo") {
			# Munki repo is available and include pkgs and pkgsinfo directories
			return 1;
		} else {
			logMessage(LOG_ERROR, "Munki Repo isn't available or is missing pkgs and pkgsinfo directories.", $logFile);
			sendEmail(subject => "ERROR: Repo not available", message => "Munki Repo isn't available or is missing pkgs and pkgsinfo directories. Script terminated...");
			exit 1;
		}
	}
	return 0;
}

sub checkTools {
	logMessage(LOG_DEBUG, "Checking Required Tools exist", $logFile);

	for my $key ( keys %tools ) {
		if ( ! -e $tools{$key} ) {
			# Tool wasn't found
			logMessage(LOG_ERROR, "Required tool $key not found at $tools{$key}.", $logFile);
			exit 1;
		}
	}
	return 1;
}

sub checkPermissions {

	logMessage(LOG_DEBUG, "Checking Permissions", $logFile);

	# Check Log is writable
	my $logFileDir = dirname($logFile);
	if (! -w "$logFileDir") {
		logMessage(LOG_WARNING, "Can't write to log file: $logFile", undef);		
	}

	# Check Data dir is writable
	if (! -w "$dataPlistPath") {
		logMessage(LOG_ERROR, "Can't write to data plist: $dataPlistPath.", $logFile);		
		next;
	}
}

###############################################################################
# Helper Functions - Logging
###############################################################################

sub prepareLog {
	# Check if the existing log file needs rotating
	if (-e "$logFile") {
		my $sizeOfLog = -s expandFilePath($logFile);
		if ($sizeOfLog / 1024 / 1024 > $logFileMaxSizeInMBs) {
			logMessage(LOG_VERBOSE, "Log file has reached maximum allowed size. Rotating logs...", $logFile);
			rotateLog($logFile);
		}
	}

	# Create the log file, and pad it.
	my $pad = "\n---------------------------------------------------";
	logMessage(LOG, $pad, $logFile);
}

sub rotateLog {
	# Rotate existing rotated logs up by 1, until maxNoOfLogs
	my $count;
	for ($count = $maxNoOfLogsToKeep - 1; $count >= 1; $count--) {
		my $toCount = $count + 1;
		my $currentLog = $logFile . "." . $count;
		my $toLog = $logFile . "." . $toCount;
		if (-e "$currentLog") { 
			move("$currentLog", "$toLog"); 
		}
	}
	
	# Move the newest log into the rotation pool
	if (-e "$logFile") {
		move("$logFile", "$logFile.1"); 
	}
}

sub logMessage {
	my ($type, $message, $logFile) = @_;
	# Required data to log event wasn't provided, so just skip it
	if ( ! defined($type) and ! defined($message) ) {
		return;
	}

	# Write message to the log file, if provided
	if ( defined($logFile) and $logFile ne "/dev/null" ) {
		my $logType = " ";
		my $nowString = localtime;
	
		if ($type == LOG_WARNING) {
			$logType = " [WARNING] ";
		} elsif ($type == LOG_ERROR) {
			$logType = " [ERROR] ";
		}
	
		# Format output to log
		my $output = "";
		if ($message =~ /^\n/) {
			# Spacer, so don't include date and type info
			$output =  $message;
		} else {
			$output =  $nowString . $logType . $message;
		}
		chomp($output);
		
		my $logFileDir = dirname($logFile);
		if (! -w "$logFileDir" || (-e "$logFile" && ! -w "$logFile")) {
			print STDERR "[WARNING] Can't write \"$message\" to log file \"$logFile\"\n";		
		} else {
			if ($type != LOG_DEBUG) {
				# Write the message to the log
				system("$tools{'echo'} \"$output\" >> $logFile");			
			} else {
				# Write the debug message to the log only if debug logging is enabled
				if ($logLevel == LOG_DEBUG) {
					system("$tools{'echo'} \"$output\" >> $logFile");	
				}
			}
		}
	}
	
	# Print log message to the screen based of it's level, and the level of logging enabled	
	if ($type <= $logLevel) {
		if ($type == LOG_ERROR) {
			print STDERR "[ERROR] $message\n";
		} elsif ($type == LOG_WARNING and $logLevel != LOG_SILENT) {
			print STDOUT "[WARNING] $message\n";
		} elsif ($logLevel != LOG_SILENT) {
			print STDOUT "$message\n";
		}		
	}
}

###############################################################################
# Helper Functions - Plists
###############################################################################

sub readDataPlist {
	my ($dataPlistPath) = @_;

	logMessage(LOG_VERBOSE, "Attempting to read data plist $dataPlistPath", $logFile);

	# Get the config data
	my $dataPlist = loadDefaults( expandFilePath($dataPlistPath) );
	if ( ! defined($dataPlist)) {
		# Error reading the Plist. Display an error and exit
		logMessage(LOG_ERROR, "The data plist can't be parsed", $logFile);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	} else {
		checkDataPlistForRequiredKeys($dataPlist);
		return $dataPlist;
	}
}

sub readStatusPlist {
	my ($statusPlistPath) = @_;
	my $statusPlist = undef;

	logMessage(LOG_DEBUG, "Attempting to read status plist $statusPlistPath", $logFile);

	if ( -e expandFilePath($statusPlistPath) ) {
		$statusPlist = loadDefaults( expandFilePath($statusPlistPath) );
	} 
	
	if ( ! defined ($statusPlist) ) {
		$statusPlist = NSMutableDictionary->dictionary();
		logMessage(LOG_DEBUG, "Status Plist could not be read. Creating a new plist.", $logFile);
	}

	return $statusPlist;
}

sub readDefaultSettingsPlist {
	my ($defaultSettingsPlistPath) = @_;

	logMessage(LOG_VERBOSE, "Attempting to read Default Settings plist $defaultSettingsPlistPath", $logFile);
	
	my $defaultSettingsPlist = loadDefaults( expandFilePath($defaultSettingsPlistPath) );
	if ( ! defined($defaultSettingsPlist)) {
		# Error reading the Plist. Display an error and exit
		logMessage(LOG_ERROR, "The default settings plist ($defaultSettingsPlistPath) can't be parsed", $logFile);
		exit 1;
	}

	checkDefaultSettingsPlist($defaultSettingsPlist);
	return $defaultSettingsPlist;
}

sub checkDataPlistForRequiredKeys {
	my ($dataPlist) = @_;
	
	logMessage(LOG_DEBUG, "Checking data plist contains required keys", $logFile);
	
	my $missingKeys = 0;
	my $dummyVar = undef;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "URLToMonitor")); }; $missingKeys = 1 if $@;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "name"));         }; $missingKeys = 1 if $@;
	eval { $type     = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "type"));         }; $missingKeys = 1 if $@;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "itemToImport")); }; $missingKeys = 1 if $@;
	
	if ($missingKeys) {
		# Ensure that the required keys were present
		logMessage(LOG_ERROR, "Missing Keys in Data Plist. Require autoMunkiImporter dict, with URLToMonitor, name, type, and itemToImport strings.", $logFile);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	} 
	
	# Check the "type" key, and any additional required items
	getType($type);
	if ($type eq "dynamic") {
		eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "downloadLinkRegex")); }; $missingKeys = 1 if $@;
		if ($missingKeys) {
			logMessage(LOG_ERROR, "Missing Keys in Data Plist. Require autoMunkiImporter dict, with downloadLinkRegex when type = dynamic.", $logFile);
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}
	} else {
		# Static or Sparkle - no additional keys required
	}	
}

sub getType {
	my ($type) = @_;

	logMessage(LOG_DEBUG, "Pattern matching type string from data plist", $logFile);

	if ($type =~ /static/i) {
		$type = "static";
	} elsif ($type =~ /dynamic/i) {
		$type = "dynamic";	
	} elsif ($type =~ /sparkle/i) {
		$type = "sparkle";	
	} else {
		logMessage(LOG_ERROR, "Type: \"$type\" is unsupported. Supported types are static, dynamic, or sparkle.", $logFile);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
}

sub checkDefaultSettingsPlist {
	my ($defaultSettingsPlist) = @_;

	logMessage(LOG_DEBUG, "Checking Default Settings plist contains required keys", $logFile);
	
	my @expectedKeys = ("userAgent", "logFile", "logFileMaxSizeInMBs", "maxNoOfLogsToKeep", 
						"statusPlistPath", "emailReports", "smtpServer", "fromAddress", 
						"toAddress", "subjectPrefix", "makecatalogs", "dataPlistPath");

	foreach my $key (@expectedKeys) {
		my $dummyVar = "";
		eval { $dummyVar = perlValue(getPlistObject($defaultSettingsPlist, "$key")); }; 
		if ($dummyVar eq "" || $dummyVar =~ /REPLACE_ME/i) {
			logMessage(LOG_ERROR, "Key: $key does not have an appropriate value in the default settings plist. Exiting...", $logFile);
			exit 1;
		}
	}
}

###############################################################################
# Helper Functions - Finding Download URLs
###############################################################################

sub findFinalURLAfterRedirects {
	my ($url) = @_;
	
	my $checkForRedirect = 1; # True
	my %seenURLs = ();
	
	$seenURLs{$url} = 1;
	
	while ($checkForRedirect) {
		my $newURL = handleRedirect($url);
		if ($newURL eq $url) {
			$checkForRedirect = 0;
		} else {
			if (exists($seenURLs{$newURL})) {
				logMessage(LOG_ERROR, "Redirect Loop found", $logFile);
				sendEmail(subject => "ERROR: $name - Redirect Loop found", message => "While determining the URL of the download a redirect loop was detected.\nScript terminated...");
				if ($dataPlistSourceIsDir) {
					return undef;
				} else {
					exit 1;
				}						
			} else {
				$seenURLs{$newURL} = 1;
				$url = $newURL;
			}	
		}
	}
	
	return $url;
}

sub handleRedirect {
	my ($url) = @_;
	my $initialURL = $url;

    my $cookieString = "";
    if (defined $userCookie && ! $userCookie eq ""){
        $cookieString = "--cookie \"$userCookie\"";
    }
    my $headers = `$tools{'curl'} --head --location $cookieString --user-agent \"$userAgent\" \"$url\" 2>/dev/null`;
	$headers =~ s/\r/\n/gi;
		
	# Search for the Location field
	my @headers = split /\n/, $headers;
	foreach my $line (@headers) {
		if ($line =~ /Location:\s/i) {
			# Found so update URL
			$url = $';
		}
	}
	
	# Return URL
	if ($initialURL ne $url) {
		logMessage(LOG_VERBOSE, "Redirect(s) found. New URL is: $url", $logFile);
	}
	
	$url = escapeURL($url);
	return $url
	
}

sub escapeURL {
	my ($url) = @_;
	
	my $escapedURL = URI->new($url);
	return $escapedURL->as_string();	
}

sub findURL {
	my ($url, $mech, $searchPattern) = @_;

	logMessage(LOG_DEBUG, "Searching $url for link that matches $searchPattern", $logFile);

	my $foundLink = $mech->find_link( text_regex => qr/$searchPattern/i );
	my $uri = undef;
	if (defined $foundLink) {
		# Matching link found
		$uri = $mech->uri;
		if ($foundLink->url =~ /^\//) {
			# Full path for server
			$foundLink = $uri->scheme . "://" . $uri->host . $foundLink->url;
		} elsif ($foundLink->url =~ /^http/i) {
			# Full URL
			$foundLink = $foundLink->url;
		} else {
			# Relative to current document
			if ($uri =~ /\.htm(l)?$/) {
				# Trim the document name if it's part of the path
				$uri = dirname($uri);
			}
			$foundLink = addTrailingSlash($uri) . $foundLink->url;
		}
		logMessage(LOG_DEBUG, "Match found via WWW::Mechanize", $logFile);
	} else {
		# Link not found (most likely using Javascript, so revert to straight regex
		my $thePage = $mech->content();
		$thePage =~ m/$searchPattern/gi;
		$thePage = $&;
		$foundLink = $thePage;
		if (! defined $foundLink) {
			return undef; # No URL found, so bail
		}
		# Convert relative to absolute links
		if ($foundLink =~ /^\//) {
			my $uriObj = URI->new($url);
			$foundLink = $uriObj->scheme . "://" . $uriObj->host . $foundLink;
		}
		if ($foundLink =~ m/('|")(.+?)('|")/) {
			# Final URL is the result of previous step, minus the quotes
			$foundLink = substr($&, 1, -1);		
		}
		
		logMessage(LOG_DEBUG, "Match found via regex", $logFile);
	}
	
	return $foundLink;
}

sub findDownloadLinkOnPage {
	my ($url, $dataPlist) = @_;
	
	my $foundLink = undef;
	
	# Download the page, using our provided user agent
	my $mech = WWW::Mechanize->new();
	$mech->agent($userAgent);
	logMessage(LOG_VERBOSE, "Using User Agent: " . $mech->agent, $logFile);

    if (defined $userCookie && ! $userCookie eq ""){
        $mech->add_header( 'Set-Cookie' => $userCookie);
        logMessage(LOG_VERBOSE, "Using User Cookie: " . $userCookie, $logFile);
    }
    
	eval { $mech->get($url); };
	if ($@) {
		logMessage(LOG_ERROR, "Can't download content of URL. Error was: $@", $logFile);
		sendEmail(subject => "ERROR: $name - Can't download content of URL", message => "Can't download content of URL. Error returned was:-\n$@\nScript terminated...");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}		
	}
	
	# Find the link
	my $downloadLinkRegex = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "downloadLinkRegex"));
	$foundLink = findURL($url, $mech, $downloadLinkRegex);
	if (!defined($foundLink)) {
		return undef;
	}
	
	# URL can have spaces, so encode them
	$foundLink = escapeURL($foundLink);
	
	logMessage(LOG_VERBOSE, "Download Link found: $foundLink", $logFile);
	
	# Determine if the link is to the actual download, or another page
	# by first walking all of the redirects until we get to the final content
	$foundLink = findFinalURLAfterRedirects($foundLink);
	
	my $headers = `$tools{'curl'} --head --user-agent \"$userAgent\" \"$foundLink\" 2>/dev/null`;

	# Check if the final URL is to a web page
	if ($headers =~ /Content-Type: text/ig) {	
		# Link is to a second web page, so find the real link

		# Get new page	
		eval { $mech->get($foundLink); };
		if ($@) {
			if (!defined($foundLink)) {
				return undef;
			}
		}
		
		# Find the link
		my $secondLinkRegex = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "secondLinkRegex"));
		$foundLink = findURL($url, $mech, $secondLinkRegex);

		# Ensure there aren't any additional redirects
		$foundLink = findFinalURLAfterRedirects($foundLink);
		# URL can have spaces, so encode them
		$foundLink = escapeURL($foundLink);
		logMessage(LOG_VERBOSE, "Download Link found: $foundLink", $logFile);
	}

	return $foundLink;
}

sub findDownloadLinkFromSparkleFeed {
	my ($url) = @_;
	my $feedURL = findFinalURLAfterRedirects($url);

	my $feed = `$tools{'curl'} "$feedURL" 2>/dev/null`;

	# Setup variables used when parsing the rss
	my $pubDate = "";	# Date item was released
	my $version = "";	# Version of the item
	my $finalUrl = "";	# URL to the specific version
	
	# Temp variables used in parsing the rss
	my $itemVer = undef;
	my $itemURL = undef;
	my $itemPubDate = undef;
	
	# Convert line endings to \n, and split the rss into lines
	$feed =~ s/\r/\n/gi;
	my @lines = split /\n/, $feed;
	
	# Parse RSS and find latest version
	foreach my $line (@lines) {
		# Find the version
		if ($line =~ /sparkle:version="(.+?)"/i || $line =~ /sparkle:shortVersionString="(.+?)"/i) {
			$itemVer = $&;
			# Get the specific version number, minus the quotes
			$itemVer =~ m/"(.+?)"/;
			$itemVer = substr($&, 1, -1);
		}
	
		# Find the download URL
		if ($line =~ /url="(.+?)"/i) {
			$itemURL = $&;
			# Get the url without quotes
			$itemURL =~ m/"(.+?)"/;
			$itemURL = substr($&, 1, -1);
		}
		
		# Find the publication date
		if ($line =~ m/<pubdate>(.+)?<\/pubdate>/i) {
			# Get the date, without the xml tags around it
			$itemPubDate = substr($&, 9, -10);
			$itemPubDate = str2time($itemPubDate);
		}
		
		if ($line =~ m/^\s*<\/item>/i) {
			logMessage(LOG_VERBOSE, "Checking: Date: " . timestampToString($itemPubDate) . " ($itemPubDate), Version: $itemVer, URL: $itemURL", $logFile);
			# End of an RSS item, so determine if we should consider it as the version to use
			if (defined $itemVer && defined $itemURL && defined $itemPubDate) {
				# Required elements were found
				
				# Convert version number to something we can compare 
				# (with leading v to work with #.#.# versions)
				$itemVer =~ s/[[:alpha:]]//gi;
				$itemVer =~ s/-//gi;
				$itemVer = "v" . version->parse($itemVer);
								
				if ($itemPubDate ge $pubDate) {
					if ($itemPubDate gt $pubDate) {				
						# Newer release date, so use this instead of any previously found items
						$pubDate = $itemPubDate;
						$version = $itemVer;
						$finalUrl = $itemURL;
						logMessage(LOG_VERBOSE, "Newer version found in feed (by release date)...", $logFile);
					} elsif ($itemVer gt $version) {
						# Release date is the same, but this is a newer version, so use this instead of any previously found items
						# version comparison can be hit and miss, so preference is given to the modification date
						$pubDate = $itemPubDate;
						$version = $itemVer;
						$finalUrl = $itemURL;
						logMessage(LOG_VERBOSE, "Newer version found in feed (by version as release date was the same)...", $logFile);
					}
				}
			}		
		}
	}

	# URL can have spaces, so encode them.
	$finalUrl = escapeURL($finalUrl);
	logMessage(LOG_VERBOSE, "URL for latest sparkle update is: $finalUrl", $logFile);

	# Ensure there aren't any additional redirects
	$finalUrl = findFinalURLAfterRedirects($finalUrl);

	return $finalUrl;
}

###############################################################################
# Helper Functions - General
###############################################################################

sub addTrailingSlash {
	# Add's a trailing slash if required
	my ($str) = @_;

	if ($str =~ m/\/$/) {
		return $str;
	} else {
		return $str . "/";
	}
}	

sub sendEmail {
	my %args = @_;
	
	if ($emailReports) {

		my $mailer = new Mail::Mailer 'smtp', Server => $smtpServer;
	
		# The open() method takes a hash reference with keys which are mail
		# header names and values which are the values of those mail headers
		$mailer->open( {
			From    =>	$fromAddress,
			To      =>	$toAddress,
			Subject =>	$subjectPrefix . " " . $args{subject}
		} );
	
		# We can print to $mailer just as we would print to STDOUT or any other file handle...
		print $mailer $args{message};
		$mailer->close();
		
		logMessage(LOG_DEBUG, "Sending Email to $toAddress with content\n$args{message}", $logFile);
	}
}

sub updateStatus {
	my ($name, $message) = @_;

	logMessage(LOG_DEBUG, "Updating Data and Status Plists with the status from the run, and current date and time", $logFile);

	my $now = time();
	
	# Data Plist
	my @lastStatus_Data  = ("-d", "autoMunkiImporter", "-d", "lastStatus", "-s", $message);
	my @lastRunTime_Data = ("-d", "autoMunkiImporter", "-d", "lastRunTime", "-t", $now);
	setPlistObjectForce( $dataPlist, \@lastStatus_Data );
	setPlistObjectForce( $dataPlist, \@lastRunTime_Data );
	saveDefaults( $dataPlist, $dataPlistPath );
	
	# Status Plist
	my @lastStatus_Status  = ("-d", $name, "-d", "lastStatus", "-s", $message);
	my @lastRunTime_Status = ("-d", $name, "-d", "lastRunTime", "-t", $now);
	setPlistObjectForce( $statusPlist, \@lastStatus_Status );
	setPlistObjectForce( $statusPlist, \@lastRunTime_Status );
	saveDefaults( $statusPlist, $statusPlistPath );
}

sub recordNewVersion {
	my %args = @_;
		
	logMessage(LOG_DEBUG, "Recording a new version in the data and status plists", $logFile);

	# Data Plist	
	my @modifiedDate_Data = ("-d", "autoMunkiImporter", "-d", "Import History", "-d", $args{version}, "-d", "modifiedDate", "-t", $args{modifiedDate});
	my @importDate_Data   = ("-d", "autoMunkiImporter", "-d", "Import History", "-d", $args{version}, "-d", "importDate", "-t", time());
	my @initialURL_Data   = ("-d", "autoMunkiImporter", "-d", "Import History", "-d", $args{version}, "-d", "InitialURL", "-s", $args{initialURL});
	my @finalURL_Data     = ("-d", "autoMunkiImporter", "-d", "Import History", "-d", $args{version}, "-d", "finalURL", "-s", $args{finalURL});
	my @pkginfoPath_Data  = ("-d", "autoMunkiImporter", "-d", "Import History", "-d", $args{version}, "-d", "pkginfoPath", "-s", $args{pkginfoPath});
	setPlistObjectForce( $dataPlist, \@modifiedDate_Data );
	setPlistObjectForce( $dataPlist, \@importDate_Data );
	setPlistObjectForce( $dataPlist, \@initialURL_Data );
	setPlistObjectForce( $dataPlist, \@finalURL_Data );
	setPlistObjectForce( $dataPlist, \@pkginfoPath_Data );
	saveDefaults( $dataPlist, $dataPlistPath );	

	# Status Plist	
	my @modifiedDate_Status = ("-d", $args{name}, "-d", "Import History", "-d", $args{version}, "-d", "modifiedDate", "-t", $args{modifiedDate});
	my @importDate_Status   = ("-d", $args{name}, "-d", "Import History", "-d", $args{version}, "-d", "importDate", "-t", time());
	my @initialURL_Status   = ("-d", $args{name}, "-d", "Import History", "-d", $args{version}, "-d", "InitialURL", "-s", $args{initialURL});
	my @finalURL_Status     = ("-d", $args{name}, "-d", "Import History", "-d", $args{version}, "-d", "finalURL", "-s", $args{finalURL});
	my @pkginfoPath_Status  = ("-d", $args{name}, "-d", "Import History", "-d", $args{version}, "-d", "pkginfoPath", "-s", $args{pkginfoPath});
	setPlistObjectForce( $statusPlist, \@modifiedDate_Status );
	setPlistObjectForce( $statusPlist, \@importDate_Status );
	setPlistObjectForce( $statusPlist, \@initialURL_Status );
	setPlistObjectForce( $statusPlist, \@finalURL_Status );
	setPlistObjectForce( $statusPlist, \@pkginfoPath_Status );
	saveDefaults( $statusPlist, $statusPlistPath );	
	
	updateStatus($name, "v$args{version} imported into Munki - PkgInfo Path: $args{pkginfoPath}");

	my $subject = $args{name} . " (v" . $args{version} . ") has been imported";
	my $message = $args{name} . " (v" . $args{version} . ") has been imported into Munki.\n\nIt's pkginfo file is at $args{pkginfoPath}.";
	sendEmail(subject => $subject, message => $message);

}

sub updateLastModifiedDate {
	logMessage(LOG_DEBUG, "Updating Data and Status Plists with the status from the run, and current date and time", $logFile);

	my ($modifiedDate, $dataPlist, $dataPlistPath) = @_;
	my @modifiedDateArray = ("-d", "autoMunkiImporter", "-d", "modifiedDate", "-t", $modifiedDate);
	setPlistObjectForce( $dataPlist, \@modifiedDateArray );
	saveDefaults($dataPlist, $dataPlistPath);
}

sub hackAroundLicenceAgreementsInDiskImages {
	my ($plistFile) = @_;

	logMessage(LOG_DEBUG, "Trimming any licence text that may appear when mounting some disk images", $logFile);
	
	my $licText = 1;	# Assume True
	my $plistData = "";

	# Read the plist created from hdiutil that may contain the licence text
	open (PLISTFILE, "<", $plistFile);
		while (<PLISTFILE>) {
		 	chomp;
		 	
		 	# Look for the start of the plist
			if ($_ =~ /^<\?xml/) {
				$licText = 0;
			}

			# Once found, add the text to the variable
			if (! $licText) {
	 			$plistData = $plistData . "$_\n";
			}
		}
	close (MYFILE); 

	# Write the plist data back to the file, minus and licence text
	open (PLISTFILE, ">", $plistFile);
	 	print PLISTFILE $plistData;
	close (MYFILE); 
	
	# Run plutil -lint which seems to correct any formatting
	system("$tools{'plutil'} -lint -s \"$plistFile\"");

}

sub getDataPlists {
	my ($path) = @_;

	logMessage(LOG_DEBUG, "Finding Data Plists within directory: $path", $logFile);

	$path = expandFilePath($path);
	$path =~ s/ /\\ /g;
	my @dirContents = <$path/*>;
	my $item;
	foreach $item (@dirContents) {
		if (-f $item && $item =~ /\.plist$/ && basename($item) !~ /^_/ ) {
			# Plist, so add it to the array
			push(@dataPlists, $item);
			logMessage(LOG_DEBUG, "Queued Data Plist: $item", $logFile);
		}
		if (-d $item && basename($item) !~ /^_/) {
			# Directory, so check it's contents
			 getDataPlists($item);
		 }
	} 
}

sub timestampToString {
	my ($timestamp) = @_;
	return strftime("%a, %e %b %Y %H:%M:%S %Z", localtime($timestamp));
}

sub defaultSettings {
	my ($defaultSettingsPlist) = @_;
	
	logMessage(LOG_DEBUG, "(Re)setting the default settings to:-", $logFile);
	
	# Logging
	$logFile = perlValue(getPlistObject($defaultSettingsPlist, "logFile"));
	$logFile = expandFilePath($logFile);
	logMessage(LOG_DEBUG, "  logFile: $logFile", $logFile);
	$logFileMaxSizeInMBs = perlValue(getPlistObject($defaultSettingsPlist, "logFileMaxSizeInMBs"));
	logMessage(LOG_DEBUG, "  logFileMaxSizeInMBs: $logFileMaxSizeInMBs", $logFile);
	$maxNoOfLogsToKeep = perlValue(getPlistObject($defaultSettingsPlist, "maxNoOfLogsToKeep"));
	logMessage(LOG_DEBUG, "  maxNoOfLogsToKeep: $maxNoOfLogsToKeep", $logFile);
	
	# User Agent
	$userAgent = perlValue(getPlistObject($defaultSettingsPlist, "userAgent"));
	logMessage(LOG_DEBUG, "  userAgent: $userAgent", $logFile);

	# Email
	$emailReports = perlValue(getPlistObject($defaultSettingsPlist, "emailReports"));
	logMessage(LOG_DEBUG, "  emailReports: $emailReports", $logFile);
	$smtpServer = perlValue(getPlistObject($defaultSettingsPlist, "smtpServer"));
	logMessage(LOG_DEBUG, "  smtpServer: $smtpServer", $logFile);
	$fromAddress = perlValue(getPlistObject($defaultSettingsPlist, "fromAddress"));
	logMessage(LOG_DEBUG, "  fromAddress: $fromAddress", $logFile);
	$toAddress = perlValue(getPlistObject($defaultSettingsPlist, "toAddress"));
	logMessage(LOG_DEBUG, "  toAddress: $toAddress", $logFile);
	$subjectPrefix = perlValue(getPlistObject($defaultSettingsPlist, "subjectPrefix"));
	logMessage(LOG_DEBUG, "  subjectPrefix: $subjectPrefix", $logFile);

	# Status Plist
	$statusPlistPath = perlValue(getPlistObject($defaultSettingsPlist, "statusPlistPath"));
	logMessage(LOG_DEBUG, "  statusPlistPath: $statusPlistPath", $logFile);

	# Make Catalogs
	$makecatalogs = perlValue(getPlistObject($defaultSettingsPlist, "makecatalogs"));
	logMessage(LOG_DEBUG, "  makecatalogs: $makecatalogs", $logFile);

	# Git
	$gitEnabled = perlValue(getPlistObject($defaultSettingsPlist, "gitEnabled"));
	logMessage(LOG_DEBUG, "  gitEnabled: $gitEnabled", $logFile);
	$gitPullAndPush = perlValue(getPlistObject($defaultSettingsPlist, "gitPullAndPush"));
	logMessage(LOG_DEBUG, "  gitPullAndPush: $gitPullAndPush", $logFile);
	if (!$gitEnabled) {
		delete($tools{'git'});
	}
}

###############################################################################
# Main App - Prep
###############################################################################

# Handle Command Line options
GetOptions ('data=s'     	=> \$dataPlistPath, 
			'settings=s'	=> \$defaultSettingsPlistPath,
			'download'   	=> \$downloadOnly, 
			'verbose|v+'  	=> \$verbose, 
			'silent'		=> \$silent,
			'help|h|?'   	=> \$help, 
			'version'    	=> \$showScriptVersion, 
			'ignoreModDate' => \$ignoreModDate,
			'install-dependencies'       => \$installPerlDependencies,
			'force-install-dependencies' => \$forceInstallPerlDependencies,
			'test' 			=> \$testScript,
			'reset'      	=> \$reset);

# Show the help info if requested
pod2usage(1) if $help;

# Determine the log level to use.
if ($silent) {
	$logLevel = LOG_SILENT;
} elsif ($verbose == 1) {
	$logLevel = LOG_VERBOSE;
} elsif ($verbose > 1) {
	$logLevel = LOG_DEBUG;
} else {
	$logLevel = LOG_NORMAL;
}
my $pad = "\n\n###################################################";
logMessage(LOG_VERBOSE, $pad, $logFile);

# Show the version if requested
if ($showScriptVersion) {
	$logLevel = LOG_NORMAL;
	logMessage(LOG, $scriptVersion, undef);
	exit 0;
}

# Try to install the required dependencies
if ($installPerlDependencies || $forceInstallPerlDependencies) {
	# installPerlDependencies will exit the script regardless of it's outcome.
	installPerlDependencies();
} else {
	# Delete the reference to the tools required for building the perl modules
	# as they are no longer required for the script, and if they aren't present
	# it should not cause a fatal error
	delete($tools{'make'});
	delete($tools{'gcc'});
	delete($tools{'perl'});
}

# Check Pre-reqs are meet
checkPerlDependencies() or die;

# Get default settings
$defaultSettingsPlist = readDefaultSettingsPlist($defaultSettingsPlistPath);
defaultSettings($defaultSettingsPlist);

# Check Munki Repo is available, and that all of the required tools are also available
checkMunkiRepoIsAvailable() or die;
checkTools() or die;

if ($testScript) {
	$logLevel = LOG_NORMAL;
	logMessage(LOG, "All tests passed...", undef);
	exit 0;
}

if (! defined($dataPlistPath) ) {
	# Use the Default Data Plist(s) Path as the user didn't provide one via the command line
	$dataPlistPath = perlValue(getPlistObject($defaultSettingsPlist, "dataPlistPath"));
	$dataPlistPath = expandFilePath($dataPlistPath);
}

if (! -e $dataPlistPath) {
	# Does not exist, bail showing usage
	logMessage(LOG_ERROR, "The data plist or directory of plists does not exist at $dataPlistPath", $logFile);
	exit 1;
}

if (-d $dataPlistPath) {
	# Path to a directory of plists
	getDataPlists($dataPlistPath);
	if (scalar(@dataPlists) == 0) {
		logMessage(LOG_ERROR, "The data plist directory $dataPlistPath does not contain any data plists", $logFile);
		exit 1;	
	} else {
		$dataPlistSourceIsDir = 1;
	}
} else {
	# Path to a specific plist, not a directory
	push(@dataPlists, $dataPlistPath);
	$dataPlistSourceIsDir = 0;
}

# Setup Status Plist
$statusPlist = readStatusPlist($statusPlistPath);

# Loop through each of the data plists that have been found and process them
foreach $dataPlistPath (@dataPlists) {
	prepareLog($logFile);

	# Reset the default settings (which maybe overwritten by the dataPlist
	defaultSettings($defaultSettingsPlist);

	# Read the data plist, which contains config for this script
	$dataPlist = readDataPlist($dataPlistPath);
	
	# Get product name
	$name = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "name"));

	# Get optional Log File name (overwriting the one in the default settings plist)
	eval { $logFile = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "logFile")); logMessage(LOG_DEBUG, "Overriding default logFile with $logFile", $logFile); };	
	# Prepare the log for use
	$logFile = expandFilePath($logFile);

	# Check paths are writable
	checkPermissions();

	logMessage(LOG, "App Name: $name", $logFile);
	logMessage(LOG_VERBOSE, "Processing Type: $type", $logFile);

	# Get optional email settings (overwriting the ones in the default settings plist)
	eval { $emailReports = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "emailReports")); logMessage(LOG_DEBUG, "Overriding default emailReports with $emailReports", $logFile); };
	eval { $fromAddress = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "fromAddress")); logMessage(LOG_DEBUG, "Overriding default fromAddress with $fromAddress", $logFile); };
	eval { $toAddress = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "toAddress")); logMessage(LOG_DEBUG, "Overriding default toAddress with $toAddress", $logFile); };
	
	# Check for optional disabled key
	my $disabled = 0; # False
	eval { $disabled = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "disabled")); };
	if ($disabled) {
		logMessage(LOG, "Automatic Update Check is DISABLED.", $logFile);
		updateStatus($name, "Automatic Update Check is DISABLED.");
		next;
	}
	
	###############################################################################
	# Main App - Step 1: Get the URL for the download
	###############################################################################
	
	logMessage(LOG, "Determining URL of download...", $logFile);
	
	my $url = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "URLToMonitor"));
	if ($url eq "") {
		logMessage(LOG_ERROR, "URL is missing.", $logFile);
		updateStatus($name, "ERROR: URL is missing.");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# Replace the XML encoding of &
	$url =~ s/&amp;/&/g;
	
	my $initialURL = $url;
	logMessage(LOG_VERBOSE, "Initial URL: $initialURL", $logFile);
	
	# Some sites will return different content based off the user agent
	# Optionally overwrite the default user agent if present in the plist
	eval { $userAgent = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "userAgent")); logMessage(LOG_DEBUG, "Overriding default userAgent with $userAgent", $logFile); };
	
	if ($type eq "static") {
		$url = findFinalURLAfterRedirects($url);
	} elsif ($type eq "dynamic") {
		$url = findDownloadLinkOnPage($url, $dataPlist);
	} elsif ($type eq "sparkle") {
		$url = findDownloadLinkFromSparkleFeed($url);
	}
	
	if (! defined $url || $url eq "") {
		logMessage(LOG_ERROR, "Can't determine final URL.", $logFile);
		updateStatus($name, "ERROR: Can't determine final URL.");
		sendEmail(subject => "ERROR: $name - Can't determine final URL", message => "Can't determine final URL from $initialURL. Script terminated...");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	logMessage(LOG_VERBOSE, "Final URL: $url", $logFile);
	
	###############################################################################
	# Main App - Step 2: Determine if file has changed since we last processed it
	###############################################################################
	
	logMessage(LOG_VERBOSE, "Determine if file has changed since we last processed it...", $logFile);
	# Get headers for download
	my $headers = `$tools{'curl'} --head --user-agent \"$userAgent\" \"$url\" 2>&1`;
	# Convert line endings to \n, and split the headers into lines
	$headers =~ s/\r/\n/gi;
	my @headers = split /\n/, $headers;
	logMessage(LOG_DEBUG, "Full Headers:\n$headers", $logFile);
	
	# Search for the Last-Modified date, and ensure that we are getting a HTTP 200 Status Code
	my $modifiedDate = "";
	my $httpCode = 0;
	foreach my $line (@headers) {
		# Flag if we find a HTTP Status Code of 200
		if ($line =~ /HTTP\/\d.\d 200/i) {
			$httpCode = 1;	
		}
	
		# Get the last modified date
		if ($line =~ /Last-Modified/i) {
			# The Last-Modified header may not be on a new line, so find where it starts
			# on the line, then take the rest of the line after it as the mod date
			my $lastModifiedPosition = index($line, "Last-Modified");
			my $lastModifiedDate = substr($line, $lastModifiedPosition + 15);
			$modifiedDate = str2time($lastModifiedDate);
		}
	}
	
	# Die if the HTTP Status code isn't 200 - success
	if (! $httpCode && $url =~ /^http/) {
		logMessage(LOG_ERROR, "Problem accessing file to download", $logFile);
		logMessage(LOG_VERBOSE, "The error and / or headers were\n$headers", $logFile);
		updateStatus($name, "ERROR: Problem accessing file to download.");
		sendEmail(subject => "ERROR: $name - Problem accessing file to download", message => "There was a problem accessing the file to download. The URL $url returned the following error and / or headers:-\n$headers");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# Die if the modification date isn't set
	if ($modifiedDate eq "" || $modifiedDate == 0) {
		logMessage(LOG_ERROR, "Modification date of download not found.", $logFile);
		logMessage(LOG_VERBOSE, "The headers were\n$headers", $logFile);
		updateStatus($name, "ERROR: Modification date of download not found.");
		sendEmail(subject => "ERROR: $name - Modification Date not found", message => "Modification date of download not found, indicating a problem.\n\nThe URL $url returned the following headers\n$headers. Script terminated...");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# If just resetting the modified date, bail at this stage
	if ($reset) {
		updateLastModifiedDate($modifiedDate, $dataPlist, $dataPlistPath);
		logMessage(LOG, "Modification date rest to current modification date of url", $logFile);
		updateStatus($name, "Modification date rest to current modification date of url.");
		next;
	}
	
	# Compare latest modification date to what we have already packaged
	my $currentPackagedModifiedDate = 0;
	if (!$downloadOnly) {
		eval { $currentPackagedModifiedDate = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "modifiedDate")); };
		
		logMessage(LOG_VERBOSE, "Modification Date of Download:                     " . timestampToString($modifiedDate) . " ($modifiedDate)", $logFile);
		logMessage(LOG_VERBOSE, "Modification Date of Previously Packaged Download: " . timestampToString($currentPackagedModifiedDate) . " ($currentPackagedModifiedDate)", $logFile);
	
		if ($modifiedDate <= $currentPackagedModifiedDate) {
			logMessage(LOG, "No new version of $name found...", $logFile);
			updateStatus($name, "No new version found.");
			if (! $ignoreModDate) {
				next;
			}
		} else {
			logMessage(LOG, "New version of $name found...", $logFile);
		}	
	}
	
	###############################################################################
	# Main App - Step 3: Download the new version of the app
	###############################################################################
	
	# Sanity check download to ensure it's of a supported type
	my $validExtension = 0; 
	
	# Get the true base name of the URL, removing any query strings etc
	my $urlURL = url $url;
	my $baseName = basename($urlURL->epath);

	foreach my $supportedDownloadType(@supportedDownloadTypes) {
		if ($baseName =~ m/($supportedDownloadType)$/) {
			$validExtension = 1;	
		}
	}
	
	if (! $validExtension) {
		# URL's basename is unsupported, but it could be a script, so try the end of the
		# query string to double check it is unsupported
		$baseName = basename($url);
		$validExtension = 0;
		foreach my $supportedDownloadType(@supportedDownloadTypes) {
			if ($baseName =~ m/($supportedDownloadType)$/) {
				$validExtension = 1;	
			}
		}
		
		if (! $validExtension) {
			# Download is in an unsupported format.
			logMessage(LOG_ERROR,"Download is in an unsupported format.\n", $logFile);
			updateStatus($name, "ERROR: Download is in an unsupported format.");
			sendEmail(subject => "ERROR: $name - Download is in an unsupported format", message => "URL implies that the download would be in an unsupported format ($url). Script terminated...");
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}	
	}
		
	my $tmpDIR = File::Temp->newdir();
	my $downloadFileName = addTrailingSlash($tmpDIR) . $baseName;
	logMessage(LOG_VERBOSE, "Downloading app to $downloadFileName...", $logFile);
		
	# Show progress if not in silent mode
	my $progressOuptutLocation = "";
	if ($logLevel == LOG_SILENT) {
			$progressOuptutLocation = "2>/dev/null";
	}
	
	system("$tools{'curl'} --user-agent \"$userAgent\" -o \"$downloadFileName\" \"$url\" $progressOuptutLocation");
	logMessage(LOG, "Download complete...", $logFile);
		
	# If download only is set, copy the downloaded file to /tmp and quit
	if ($downloadOnly) {
		# Copy to user defined spot
		my $tmpLocation = "/private/tmp/" . basename($downloadFileName);
		system ("$tools{'cp'} -r \"$downloadFileName\" \"$tmpLocation\"");
	
		updateStatus($name, "Download Only option was selected. File saved to: \"$tmpLocation\"");
		logMessage(LOG, "Download Only option was selected. File saved to: \"$tmpLocation\"", $logFile);
		next;
	}
	
	###############################################################################
	# Main App - Step 4: Prep for Import into Munki
	###############################################################################
	
	# Extract files or mount disk image, and determine where the actual item we are
	# after ended up. This will return an .app or .pkg for Munki to import, 
	# regardless of the download format.
	
	# This is the step where you would do any prep work on a download before
	# it's imported into Munki. Basically just ensure that $target has the full path
	# to the item to import by the end.
	
	logMessage(LOG, "Extracting download and finding the item we wish to import...", $logFile);
	my $target = "";
	my $itemToImport = perlValue(getPlistObject($dataPlist, "autoMunkiImporter",  "itemToImport"));
	if ($downloadFileName =~ /.zip$/) {
		# ZIP File
		system("$tools{'ditto'} -xk \"$downloadFileName\" \"$tmpDIR\"");
		$target = `$tools{'find'} \"$tmpDIR\" -iname \"$itemToImport\" -print 2>/dev/null`;
	} elsif ($downloadFileName =~ /.tar$/ || $downloadFileName =~ /.tar.gz$/ || $downloadFileName =~ /.tgz$/ || $downloadFileName =~ /.tbz/) {
		# TAR and friends file
		system("$tools{'tar'} -xf \"$downloadFileName\" -C \"$tmpDIR\"");
		$target = `$tools{'find'} \"$tmpDIR\" -iname \"$itemToImport\" -print 2>/dev/null`;
	} elsif ($downloadFileName =~ /.dmg$/ || $downloadFileName =~ /.iso$/) {
		# Disk Image
		
		# Mount Disk Image
		my $hdiutilPlistPath = $downloadFileName . ".plist";
		system("$tools{'yes'} | $tools{'hdiutil'} attach -mountrandom /tmp -plist -nobrowse \"$downloadFileName\" &> \"$hdiutilPlistPath\"");
	
		# Find the path to the Mount Point in the plist returned by hdiutil
		hackAroundLicenceAgreementsInDiskImages($hdiutilPlistPath);
		my $hdiutilPlist = loadDefaults($hdiutilPlistPath);
		if (! defined($hdiutilPlist) ) {
			# Error reading the Plist. Display an error and exit
			logMessage(LOG_ERROR,"Can't mount disk image.\n", $logFile);
			updateStatus($name, "ERROR: Can't mount disk image.");
			sendEmail(subject => "ERROR: $name - Can't mount disk image", message => "Can't read the plist that hdiutil generates when attempting to mount the disk image. The disk image downloaded from $url is most likely corrupt. Script terminated...");		
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}
	
		my @pathToMountPointKey = pathsThatMatchPartialPathWithGrep($hdiutilPlist, "system-entities", "*", "mount-point");
		if ( ! defined($hdiutilPlist) || $#pathToMountPointKey < 0) {
			# Error reading the Plist. Display an error and exit
			logMessage(LOG_ERROR,"Can't determine mount point of DMG.", $logFile);
			updateStatus($name, "ERROR: Can't determine mount point of DMG.");
			sendEmail(subject => "ERROR: $name - Can't determine mount point of DMG", message => "Can't determine the mount point of the disk image downloaded from $url. Script terminated...");
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}
	
		# Get the mount point using the previously found path.
		my $mountPoint = perlValue(getPlistObject($hdiutilPlist, "system-entities", ${$pathToMountPointKey[0]}[1], "mount-point"));
		logMessage(LOG_DEBUG, "Disk image mounted at $mountPoint...", $logFile);
	
		# Find and copy item from disk image
		$target = `$tools{'find'} \"$mountPoint\" -iname \"$itemToImport\" -print 2>/dev/null`;
		if ($target ne "") {
			# Item was found, so copy it out of the disk image
			chomp($target);
			my $dest = addTrailingSlash($tmpDIR) . basename($target);
			system ("$tools{'cp'} -r \"$target\" \"$dest\"");
			logMessage(LOG_VERBOSE, "Item found at: $target", $logFile);
			$target = $dest;
		}
		
		# Unmount and Detach Disk Image
		system("$tools{'hdiutil'} detach $mountPoint > /dev/null");		
	} elsif ($downloadFileName =~ /.pkg$/ || $downloadFileName =~ /.mpkg$/) {
		# Flat package, so no prep is required
		$target = $downloadFileName;
	}
	
	# Check that the target file to import actually exists (sanity check the about if)
	chomp($target);
	if (! -e "$target") {
		# Can't find downloaded file to import into Munki.
		logMessage(LOG_ERROR,"Can't find item ($itemToImport) to import into Munki.", $logFile);
		updateStatus($name, "ERROR: Can't find item ($itemToImport) to import into Munki.");
		sendEmail(subject => "ERROR: $name - Can't find downloaded file to import into Munki", message => "Can't find item to import into Munki. Script terminated...\n\n$name looked for $itemToImport\n");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	logMessage(LOG_VERBOSE, "Item extracted to $target...", $logFile);

	###############################################################################
	# Main App - Step 5: Import into Munki
	###############################################################################
	
	logMessage(LOG, "Importing app into Munki...", $logFile);
	
	# If Git is enabled, and we want to pull and push, update the repo before making changes
	if ($gitEnabled and $gitPullAndPush) {
	    chdir($repo_path);
		logMessage(LOG_VERBOSE, "Pulling latest changes from git server...", $logFile);
		system("$tools{'git'} pull origin master > /dev/null 2>> $logFile");
	}

	# Get optional command line options for Munki Import
	my $munkiimportOptions = "";
	eval { $munkiimportOptions = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "munkiimportOptions")); };
	if ($munkiimportOptions ne "") {
		logMessage(LOG_VERBOSE, "Munki Import command line options: --nointeractive --name \"$name\" $munkiimportOptions", $logFile);
	}
	# Import into Munki
	my $munkiOutput = `$tools{'munkiimport'} --nointeractive --name "$name" $munkiimportOptions \"$target\" | $tools{'grep'} pkgsinfo`;
	
	# Get the PkgInfo File for the package we just imported
	my $pkgInfoPlistPath = $munkiOutput;
	$pkgInfoPlistPath =~ m/\/(.*)?/gi;
	$pkgInfoPlistPath = substr($&, 0, -3);
	logMessage(LOG_VERBOSE, "PkgInfo File: $pkgInfoPlistPath...", $logFile);
	
	# Read Pkginfo file
	my $pkgInfoPlist = loadDefaults( $pkgInfoPlistPath );
	if ( ! defined($pkgInfoPlist)) {
		# Error reading the Plist. Display an error and skip items that relied on it
		logMessage(LOG_ERROR, "The Pkginfo plist can't be read. The import to Munki failed....", $logFile);
		updateStatus($name, "ERROR: The Pkginfo plist can't be read. The import to Munki failed...");
		sendEmail(subject => "ERROR: $name - Import to Munki Failed", message => "The Pkginfo plist can't be read. The import to Munki failed...");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	###############################################################################
	# Main App - Step 6: Update PkgInfo and Data Plists
	###############################################################################
	
	logMessage(LOG, "Updating Pkginfo...", $logFile);

	# Get the version of the new package
	my $packagedVersion = perlValue(getPlistObject($pkgInfoPlist, "version"));

	# Find if there are any installs items that have a CFBundleShortVersionString key
	my @installsVersionPaths = pathsThatMatchPartialPathWithGrep($dataPlist, 'installs', '*', 'CFBundleShortVersionString');
	if ( $#installsVersionPaths > 0 ) {
		foreach my $installsItem (@installsVersionPaths) {
			# Determine if the version should be replaced with the new package version
			if (perlValue( getPlistObject( $dataPlist, 'installs', $$installsItem[1], 'CFBundleShortVersionString' )) eq "__VERSION__") {
				logMessage(LOG_VERBOSE, "Updating a CFBundleShortVersionString version in the Pkginfo...", $logFile);
				my @replacementArray = ('installs');
				push(@replacementArray, $$installsItem[1]);
				push(@replacementArray, 'CFBundleShortVersionString');
				push(@replacementArray, $packagedVersion);
				# Update version for the selected Installs item
				setPlistObject($dataPlist, @replacementArray);
			}
		}
	}
	
	# Add or override Munki's default keys with ones in our data plist
	my %keysHash = perlHashFromNSDict(getPlistObject($dataPlist));
	foreach my $key (sort(keys %keysHash)) {
		# Remove any of the existing keys
		if ($key ne "autoMunkiImporter") {
			logMessage(LOG_VERBOSE, "Overriding Pkginfo key: $key", $logFile);
		}
		removePlistObject($pkgInfoPlist, $key);
	}
	
	# Add the keys from our data plist
	my $combinedPlist = combineObjects($pkgInfoPlist, $dataPlist);
	
	# Remove the keys specific to this script and not Munki
	removePlistObject($combinedPlist, "autoMunkiImporter");

	# Save the PkgInfo
	saveDefaults($combinedPlist, $pkgInfoPlistPath);

	# Save a copy of the version into the data plist
	setPlistObject($dataPlist, "autoMunkiImporter", "modifiedDateCorrospoindingVersion", $packagedVersion);
	saveDefaults($dataPlist, $dataPlistPath);
	
	# Update packaged modification date in data plist, so that we don't attempt to repackage this version
	updateLastModifiedDate($modifiedDate, $dataPlist, $dataPlistPath);
	
	# Get the catalog(s) that the new version has been added to
	my @catalogs = perlArrayFromNSArray(getPlistObject($combinedPlist, "catalogs"), 1);
	my $assignedToCatalogs = "";
	foreach my $catalog (@catalogs) {
		if ($assignedToCatalogs eq "") {
			$assignedToCatalogs = $catalog;
		} else {
			$assignedToCatalogs = $assignedToCatalogs . ", " . $catalog;
		}
	}
		
	logMessage(LOG, "$name version $packagedVersion was imported into Munki $assignedToCatalogs catalog(s)...", $logFile);
	logMessage(LOG, "Please test the app to ensure it functions correctly before enabling for any non Dev / Test users.", $logFile);
	
	# If Git is enabled, add the new pkginfo
	if ($gitEnabled) {
		logMessage(LOG_VERBOSE, "Committing changes to git repo...", $logFile);
		system("$tools{'git'} add $pkgInfoPlistPath > /dev/null 2>> $logFile");
		system("$tools{'git'} commit -m \"$name ($packagedVersion) has been imported by the Automatic Munki Importer tool.\" --author \"autoMunkiImporter.pl <$fromAddress>\" > /dev/null 2>> $logFile");
		# If we want to pull and push, push the changes back to the server
		if ($gitPullAndPush) {
			logMessage(LOG_VERBOSE, "Pushing latest changes to git server...", $logFile);
			system("$tools{'git'} push > /dev/null 2>> $logFile");
		}
	}

	###############################################################################
	# Main App - Step 7: Notify Package has been imported
	###############################################################################
	
	recordNewVersion(name => $name, 
	        		 version => $packagedVersion, 
	        		 modifiedDate => $modifiedDate, 
	        		 initialURL   => $initialURL, 
	        		 finalURL     => $url, 
	        		 pkginfoPath  => $pkgInfoPlistPath);
		
	###############################################################################
	# Main App - Step 8: Optionally run makecatalogs
	###############################################################################
	
	if ($makecatalogs) {
		logMessage(LOG, "Rebuilding catalogs...", $logFile);
		system("$tools{'makecatalogs'} > /dev/null");
	}
	
	logMessage(LOG, "Finished...", $logFile);
}

exit 0;

__END__

=head1 NAME

autoMunkiImporter - Automatically import apps into Munki

=head1 SYNOPSIS

autoMunkiImporter.pl [options]

 Options:
	--data /path/to/data[.plist]		Path to the data plist or directory containing data plists
	--download 				Only download the file (doesn't import into Munki)
	--force-install-dependencies		Force install required Perl Modules
	--help | -h | -?			Show this help text
	--ignoreModDate				Ignore the modified date and version info from the data plist
	--install-dependencies      		Attempt to install the required Perl Modules
	--reset					Resets the modified date for an app
	--silent				Suppresses output to STDOUT and STDERR
	--settings /path/to/settings.plist	Optional path to a default settings plist
	--test					Tests that the script has all of the required items and rights
	--verbose | -v				Show verbose output, can be used twice for debug info as well
	--version				Prints scripts version

=head1 OPTIONS

=over 8

=item B<--data> /path/to/data[.plist]

Path to the data plist, or a directory containing data plists. The data plist contains 
the configuration the script needs to download a particular application. 

See B<DATA PLIST> for structure of the plist.

=item B<--download>

Download the file to /tmp, and exits, without importing the item to Munki. It does not update the 
modified time or import to Munki.

=item B<--force-install-dependencies>

Force install the required Perl Modules using the CPANM script.

=item B<--help | -h | -?>

Show this usage and help text.

=item B<--install-dependencies>

Attempt to install the required Perl Modules using the CPANM script.

=item B<--ignoreModDate>

Ignore the modified date and version info from the data plist. This will cause the item to be 
(re)imported into Munki.

=item B<--reset>

Resets the modified date of an application to the current modification date, without downloading or 
importing the item into Munki. Use this when the latest version of an application is in your Munki 
repo, so that this script doesn't attempt to re add it, of if you want to skip a version.

=item B<--silent>

Suppresses output to STDOUT and STDERR. Verbose information is still written to the log. If 
--silent is provided in conjunction with --install-dependencies, --test, or --version it is 
ignored.

=item B<--settings /path/to/settings.plist>

Optional path to a global settings plist. If not provided 
/Library/Application Support/autoMunkiImporter/_DefaultConfig.plist is used. This plist contains 
the default settings for the script, some of which can be overridden by the data plists.

=item B<--test>

Checks that the script passes it's initial checks, and that it has permissions to write to
the appropriate locations.

=item B<--verbose | -v>

Show verbose output. If used a second time in addition to the verbose info, you will also get
debug information. The verbose version of the output is logged when the logging level is set
to verbose or lower. Debug information is also written to the log when verbose is provided twice.

If --silent is provided, it takes priority and suppresses all output to STDOUT.

=item B<--version>

Prints scripts version to STDOUT.

=back

=head1 DESCRIPTION

B<autoMunkiImporter.pl> will, based on the input data, determine if there is a new version of an 
application available. If a new version is available it will download the new file, extract it, and 
then import it into Munki.

It can handle B<static> URLs, B<dynamic> URLs where the URL or link to the URL changes based off the 
version (it can also handle landing pages before the actual download), and B<Sparkle> RSS feeds. 
This generic approach should allow you to monitor most applications.

It supports downloads in flat PKGs, DMG (including support for disk images with licence 
agreements), ZIP, TAR, TAR.GZ, TGZ, and TBZ. It will import a single item (Application or PKG) from 
anywhere within the download, so the content doesn't have to be in the top level folder. This is 
achieved by using find to locate the item (e.g. the Adobe Flash Player.pkg from within the Adobe 
Flash download).

=head1 DATA PLIST

Auto Munki Importer uses data plists, to inform it about a URL to monitor, how to determine the 
final URL for the download, and to track the modification dates of the downloads.

=head2 REQUIRED KEYS

The data plist needs to contain a dictionary called B<autoMunkiImporter>, which contains the 
following required keys.

=over 8

=item B<URLToMonitor> <string>

This is the URL to monitor for new versions of an application.

=item B<name> <string>

The name used within Munki (and as an identifier in the logs or emails from this script).

=item B<type> <string>

The type needs to be one of the following supported types:-

=over 8

=item B<static>

Use static when the URL doesn't change. This is for sites that just update the file at the same URL 
when a new version is released. E.g. Google Chrome

=item B<dynamic>

Use dynamic when the download link changes with each new version. This type allows you to search 
the page and it's source for the download link to use. Dynamic also has an additional required and 
optional key. See below:-

=over 8

=item B<downloadLinkRegex> - Required

This is the either the text of the download link 
(e.g. THIS TEXT from: E<lt>a href="http://example.com/app.dmgE<gt>THIS TEXTE<lt>/aE<gt>), or a Perl 
compatible regular expression that searches the entire pages source.

=item B<secondLinkRegex> - Optional

Some web pages will redirect to a second page which contains the actual download. In this case this 
key is used to find the download. It works the same as the downloadLinkRegex key.

=back

=item B<sparkle>

Apps that use the Sparkle framework have a RSS based Appcast that list updates. This option will 
parse that feed for the update. To find if an app uses Sparkle run: 
C<find /path/to/application.app -name Sparkle.framework -print>. To find the URL Sparkle is using,
see the B<FINDING THE URL> section.

=back

=item B<itemToImport> <string>

This is the name of the item to be imported into Munki. For example My App.app. Case insensitive 
B<find> is used to locate the application, so it can be anywhere in the download (even within 
application bundles), and wildcards are accepted.

=back

=head2 OPTIONAL KEYS

=over 8

=item B<disabled> <boolean>

If true, disable checking of the application. Useful if you are checking a directory of data plists 
and want to skip an application without removing it.

=item B<emailReports> <boolean>

If true, email reports will be sent on successfully importing a new application, or on a critical 
error (besides the initial environment checks).

=item B<fromAddress> <string>

Email address to send reports from. A default email address should be specified in the settings 
plist, but if present in the data file it will override the default.

=item B<logFile> <string>

Path to log file. A default log file should be specified in the settings plist, but if present in 
the data file it will override the default.

=item B<munkiimportOptions> <string>

Additional command line options to pass to munkiimport. See munkiimport --help and 
makepkginfo --help for available options.

Also see B<MUNKI KEYS> for an additional way of providing data to be incorporated into the 
pkginfo's generated by Munki.

=item B<toAddress> <string>

Email address to send reports to. A default email address should be specified in the settings 
plist, but if present in the data file it will override the default.

=item B<userAgent> <string>

Some websites return different content based on the User Agent. This key allows you to specify the 
user agent to use. If this key is present it will override the user agent in the settings plist.

=back

=head2 MUNKI KEYS

In addition to providing options to munkiimport (and in turn makepkginfo) via the 
munkiimportOptions key, you can at the top level of the data plist include keys that will be copied 
across to the pkginfo file.

This can be useful with items like pre and post scripts, so that instead of having to maintain 
copies of the script, you can just copy the item into the data plist like you would to a pkginfo 
and the script will automatically add it. Use this for items that don't typically change between 
versions.

Any keys at the top level of the plist will override those in the generated pkginfo. So if you say 
used the munkiimportOptions key and include --catalog prod, but had a catalog array at the top of 
the data plist that contained 2 strings (autopkg, dev) then the final pkginfo would be set to 
autopkg, and dev, not prod.

=head2 EXAMPLES

Example "Static" Data Plist for Google Chrome

  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
	  <key>autoMunkiImporter</key>
	  <dict>
		  <key>URLToMonitor</key>
		  <string>https://dl.google.com/chrome/mac/stable/GGRM/googlechrome.dmg</string>
		  <key>emailReports</key>
		  <true/>
		  <key>itemToImport</key>
		  <string>Google Chrome.app</string>
		  <key>name</key>
		  <string>Chrome</string>
		  <key>munkiimportOptions</key>
		  <string>--subdirectory "apps/google"</string>
		  <key>type</key>
		  <string>static</string>
	  </dict>
	  <key>catalogs</key>
	  <array>
		  <string>autopkg</string>
	  </array>
	  <key>display_name</key>
	  <string>Google Chrome Web Browser</string>
  </dict>
  </plist>

Example "Dynamic" Data Plist for Adobe Flash Player

  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
	  <key>autoMunkiImporter</key>
	  <dict>
		  <key>URLToMonitor</key>
		  <string>http://get.adobe.com/flashplayer/</string>
		  <key>downloadLinkRegex</key>
		  <string>Download Now</string>
		  <key>emailReports</key>
		  <true/>
		  <key>itemToImport</key>
		  <string>Adobe Flash Player.pkg</string>
		  <key>munkiimportOptions</key>
		  <string>--subdirectory "apps/adobe"</string>
		  <key>name</key>
		  <string>AdobeFlashPlayer</string>
		  <key>secondLinkRegex</key>
		  <string>location.href\s*=\s*'(.+?)'</string>
		  <key>type</key>
		  <string>dynamic</string>
	  </dict>
	  <key>catalogs</key>
	  <array>
		  <string>autopkg</string>
	  </array>
	  <key>description</key>
	  <string>Adobe Flash Player Plugin for Web Browsers</string>
	  <key>display_name</key>
	  <string>Adobe Flash Player</string>
  </dict>
  </plist>

Example "Sparkle" Data Plist for VLC

  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
	  <key>autoMunkiImporter</key>
	  <dict>
		  <key>URLToMonitor</key>
		  <string>http://update.videolan.org/vlc/sparkle/vlc.xml</string>
		  <key>downloadLinkRegex</key>
		  <string></string>
		  <key>emailReports</key>
		  <true/>
		  <key>itemToImport</key>
		  <string>VLC.app</string>
		  <key>munkiimportOptions</key>
		  <string>--subdirectory "apps/vlc"</string>
		  <key>name</key>
		  <string>VLC</string>
		  <key>secondLinkRegex</key>
		  <string></string>
		  <key>type</key>
		  <string>sparkle</string>
		  <key>userAgent</key>
		  <string></string>
	  </dict>
	  <key>catalogs</key>
	  <array>
		  <string>autopkg</string>
	  </array>
	  <key>description</key>
	  <string>VLC Media Player plays a wide range of different video and audio formats.</string>
  </dict>
  </plist>

=head1 DEFAULT SETTINGS PLIST

The default settings plist contains configuration for the script. It has a series of required keys, 
some of which may be overwritten by individual data plists.

A default settings plist is installed to 
/Library/Application Support/autoMunkiImporter/_DefaultConfig.plist. You can however override this 
using the --settings /path/to/settings.plist command line paramater.

Please take the time to review the settings and change them as appropriate for your environment. 
If the email settings aren't changed, the script will exit during it's initial checks, even if 
emailing reports is disabled.

=head2 REQUIRED KEYS

=over 8

=item B<emailReports> <boolean>

Whether email reports should be sent (Default: True).

=item B<fromAddress> <string>

From email address to use for sending email (Default: replace_me@example.com). Needed regardless of 
whether emailReports is true or false.

=item B<gitEnabled> <boolean>

Whether to add and commit new pkginfos with git (Default: False).

=item B<gitPushAndPull> <boolean>

Whether to pull and push changes to and from a remote git repo (Default: False).

=item B<logFile> <string>

Path to the log file to use (Default: /Library/Logs/autoMunkiImporter/autoMunkiImporter.log).

=item B<logFileMaxSizeInMBs> <number>

Size in MBs that log files can grow to until they are rolled (Default: 1MB).

=item B<makecatalogs> <boolean>

Whether makecatalogs should be run at the end of each import (Default: True).

=item B<maxNoOfLogsToKeep> <number>

Maximum number of logs files to keep (Default: 5).

=item B<smtpServer> <string>

SMTP server to use for sending email (Default: replace_me.example.com). Needed regardless of 
whether emailReports is true or false.

=item B<statusPlistPath> <string>

Path to status plist, which gives a summary of all applications being monitored 
(Default: /Library/Logs/autoMunkiImporter/autoMunkiImporterStatus.plist).

=item B<subjectPrefix> <string>

Prefix to add to email subject lines (Default: [Auto Munki Import]). Needed regardless of whether 
emailReports is true or false.

=item B<toAddress> <string>

To email address to use for receiving email (Default: replace_me@example.com). Needed regardless of 
whether emailReports is true or false.
=item B<userAgent> <string>

The User Agent string to use when attempting to download applications (Default: Mozilla/5.0 
(Macintosh; Intel Mac OS X 10_7_5) AppleWebKit/536.26.14 (KHTML, like Gecko) Version/6.0.1 
Safari/536.26.14). I recommendation you use Safari's User Agent for your primary OS (the default is 
for Lion).

Once you have configured the settings plist, Auto Munki Importer should now have everything it 
needs to run. You can verify this by running autoMunkiImporter.pl --test. You should get 
"All tests passed..." if everything has been configured correctly.

=back

=head1 DEPENDENCIES

This script requires the following Perl modules to be installed:-
 * Date::Parse
 * Mail::Mailer
 * URI::Escape
 * URI::URL
 * WWW:Mechanize
 
You can test if a module is installed by running perl -MModule::Name -e 1 on the command line. 
There will be no output if it's installed, otherwise you will get an error 
("Can't locate Module/Name.pm in @INC(...)") if it's not installed.

Note that there is no space between -M and the module name, e.g. -MDate::Parse.
 
This script uses the perlplist.pl library, that contains copyrighted code from James Reynolds, and 
the University of Utah. The full licence text is available within the perlplist.pl file which is 
located at /usr/local/autoMunkiImporter/perlplist.pl.

=head1 FINDING THE URL

In Safari you can right click on a link and "Copy Link", or view the pages source to determine the 
URL. If you have the Develop menu (Preferences -> Advanced -> Show Develop meun in menu bar) 
enabled, right click on an item and Inspect Element. This will show you the specific HTML behind a 
link.

For tricker pages, and apps using Sparkle to update I recommend using SquidMan 
http://squidman.net/squidman/.

=head2 SQUIDMAN

SQUIDMAN is a easy to use squid proxy. You can use it to log all requests, and using this 
information build our data plist.

Once you have it installed, select the Template tab under Preferences add "strip_query_terms off". 
This will cause the entire URL to be shown. Start (or restart) SquidMan and then set the proxy 
server for your machine to localhost:8080 (or the appropriate values). Then 
tail -f ~/Library/Logs/squid/squid-access.log and you will see what URLs are accessed.

=head1 TROUBLESHOOTING

I has released this script as a service to the broader community, as is, in an unsupported manner 
with no guarantees of support from either myself or my employer (The Australian National 
University).

B<Try running munkiimport manually>

If you can't import items with munkiimport, autoMunkiImporter.pl will fail. The most likely 
problems are that the repo isn't mounted and / or your user doesn't have permissions to write to 
the repo.

B<Try a verbose run>

Try running autoMunkiImporter.pl --verbose --data /path/to/individual/data.plist. This will show 
more information that may help in tracking down the problem.

B<Look at the log file>

Open the log file in your favourite text editor. There maybe some useful information in it. The 
default location for the logs are /Library/​Logs/​autoMunkiImporter. The log location can be 
overridden by the data plist however.

B<Curl>

curl is used to access the web pages, handle redirects, and finally check if the application should 
be downloaded, and if so to download the application. You will occasionally get different results 
from curl then from Safari, so testing curl manually may be helpful.

The best strategy is to use curl --head --location http://www.example.com/path/to/url.ext and 
review it's content. Sites like Google Code block retrieving headers which is required for this 
script to work. In this case one of the returned headers will be X-Content-Type-Options: nosniff.

Also try using different (or no) User Agent (curl --user-agent "my agent").

=head1 LICENCE

Copyright (c) 2012, Adam Reed

All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted 
provided that the following conditions are met:

=over 4

=item * Redistributions of source code must retain the above copyright notice, this list of 
conditions and the following disclaimer.

=item * Redistributions in binary form must reproduce the above copyright notice, this list of 
conditions and the following disclaimer in the documentation and/or other materials provided with 
the distribution.

=item * Neither the name of the "Adam Reed" nor the names of its contributors may be used to 
endorse or promote products derived from this software without specific prior written permission.

=back

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR 
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND 
FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR 
CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL 
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, 
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER 
IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT 
OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=head1 AUTHOR

Adam Reed <adam.reed@anu.edu.au>

=cut
