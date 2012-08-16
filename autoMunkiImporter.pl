#!/usr/bin/perl

######## NAME ##########################################################
# autoMunkiImporter.pl - Automatically import apps into Munki

######## DESCRIPTION ################################################### 
# This script will based on the input data determine if there is a new
# version of an application available. If a new version is available
# it will download the new file, extract it, and then import it into 
# Munki.

# It can handle static urls, dynamic urls where the URL or link to the 
# url change based off the version (it can also handle landing pages 
# before the actual download), and sparkle rss feeds. This generic 
# approach should allow you to monitor most applications.

# It supports downloads in flat PKGs, DMG (including support for disk images 
# with licence agreements), ZIP, TAR, TAR.GZ, TGZ, and TBZ. It will import a 
# single item (APP or PKG) from anywhere within the download, so the 
# content doesn't have to be in the top level folder. This is achieved by
# using find to locate the item (e.g. the Adobe Flash Player.pkg from 
# within the Adobe Flash download).

######### COMMENTS #####################################################
# Detailed documentation is provided at the end of the script. The best
# way of accessing it is to run:-

# perldoc /path/to/autoMunkiImporter.pl

######### AUTHOR #######################################################
# Adam Reed <adam.reed@anu.edu.au>

# Import Perl Modules, additional non standard modules are imported via 
# the checkPerlDependencies() function
use strict;
use warnings;
use version;
use Foundation;
use URI;
use File::Temp;
use File::Basename;
use File::Copy;
use Getopt::Long;
use Pod::Usage;
use POSIX;

###############################################################################
# User Editable Configuration Variables
###############################################################################

# Default User Settings file
my $defaultSettingsPlistPath = "/Library/Application Support/autoMunkiImporter/_DefaultSettings.plist";

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

# Email
my $subject = "";
my $message = "";

# Script version
my $scriptVersion = "v0.1.0";

# Command Line options 
my $downloadOnly = 0; # Do a download only, without importing the package (0 = false)
my $verbose = 0; # Verbose output to STDOUT in addition to the log (0 = false)
my $progress = 0; # Show curl download progress (0 = false)
my $help = 0; # Show help info (0 = false)
my $reset = 0; # Reset the modification date (0 = false)
my $ignoreModDate = 0; # Ignore modification date (0 = false)
my $showScriptVersion = 0; # Show script version (0 = false)
my $testScript = 0; # Test the script has the appropriate items (0 = false)

# Global Variables for Default User Settings
my $name = undef;					# App Name for item being imported
my $userAgent = undef; 				# Web User Agent to present to sites
my $logFile = undef;				# Path to log file
my $logFileMaxSizeInMBs = undef;	# Upper size of log files before they are rolled
my $maxNoOfLogsToKeep = undef;		# No of log files to preserve
my $emailReports = undef;			# Whether to email reports (0 = false, 1 = true)
my $fromAddress = undef;			# From email address for reports
my $toAddress = undef				# To email address for reports
my $smtpServer = undef;				# SMTP Server to use for email reports
my $subjectPrefix = undef;			# Prefix for subject line of email reports
my $statusPlistPath = undef;		# Path to the status plist
my $makecatalogs = undef;			# Whether to run makecatalogs (0 = false, 1 = true)

# Supported Download Types
my @supportedDownloadTypes = ("pkg", "mpkg", "dmg", "zip", "tar", "tar.gz", "tgz", "tbz");

###############################################################################
# Helper Functions - Dependencies
###############################################################################

sub checkPerlDependencies {
	my $missingDependencies = 0;
	my $perlPlistLib = dirname($0) . "/perlplist.pl";

	eval { require Date::Parse;    }; $missingDependencies = 1 if $@;
	eval { require Mail::Mailer;   }; $missingDependencies = 1 if $@;
	eval { require URI::Escape;    }; $missingDependencies = 1 if $@;
	eval { require URI::URL;       }; $missingDependencies = 1 if $@;
	eval { require WWW::Mechanize; }; $missingDependencies = 1 if $@;
	eval { require $perlPlistLib;  }; $missingDependencies = 1 if $@;
	
	if ($missingDependencies) {
		logMessage("stderr", "ERROR: Required Perl Modules were not found. Please ensure that Date::Parse, Mail::Mailer, URI::Escape, URI::URL, and WWW::Mechanize are installed.", "/dev/null");
		logMessage("stderr", " - perlplist.pl also needs to be in the same directory as this script.", "/dev/null");
		exit 1;
	} else {
		use Date::Parse;
		return 1;
	}
	
	return 0;
}

sub checkMunkiRepoIsAvailable {
	# Get the Munki Repo Path from the munkiimport --config plist
	my $munkiImportConfigPlist = loadDefaults( expandFilePath("~/Library/Preferences/com.googlecode.munki.munkiimport.plist") );
	if ( ! defined($munkiImportConfigPlist)) {
		# Error reading the Munki Import Config Plist. Display an error and exit
		logMessage("stderr, log", "ERROR: Munki Repo path can't be found.", undef);
		$subject = $subjectPrefix . " ERROR: Repo not found";
		$message = "Munki Repo could not be found. Script terminated...";
		sendEmail(subject => $subject, message => $message);

		exit 1;
	} else {
		my $repo_path = perlValue(getPlistObject($munkiImportConfigPlist, "repo_path"));

		if ( -d "$repo_path" && -w "$repo_path/pkgs" && -w "$repo_path/pkgsinfo") {
			# Munki repo is available and include pkgs and pkgsinfo directories
			return 1;
		} else {
			logMessage("stderr, log", "ERROR: Munki Repo isn't available or is missing pkgs and pkgsinfo directories.", $logFile);
			$subject = $subjectPrefix . " ERROR: Repo not available";
			$message = "Munki Repo isn't available or is missing pkgs and pkgsinfo directories. Script terminated...";
			sendEmail(subject => $subject, message => $message);
			exit 1;
		}
	}
	return 0;
}

sub checkTools {
	for my $key ( keys %tools ) {
		if ( ! -e $tools{$key} ) {
			# Tool wasn't found
			logMessage("stderr, log", "ERROR: Required tool $key not found at $tools{$key}.", $logFile);
			exit 1;
		}
	}
	return 1;
}

sub checkPermissions {
	# Check Log is writable
	my $logFileDir = dirname($logFile);
	if (! -w "$logFileDir") {
		logMessage("stderr", "ERROR: Can't write to log file: $logFile", undef);		
		exit 1;
	}

	# Check Data dir is writable
	if (! -w "$dataPlistPath") {
		logMessage("stderr, log", "ERROR: Can't write to data plist: $dataPlistPath.", $logFile);		
		exit 1;
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
			rotateLog($logFile);
		}
	}

	# Create the log file, and pad it.
	my $pad = "\n\n---------------------------------------------------";
	system("$tools{'echo'} \"$pad\" >> $logFile");	

	if ($verbose || $progress) {
		print $pad . "\n";
	}
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
	my ($where, $message, $logFile) = @_;
	
	if ( defined($where) and defined($message) ) {
		# Send message to STDERR
		if ( grep /stderr/, $where ) {
			print STDERR "$message\n";
		}
		
		# Send message to STDOUT
		if ( grep /stdout/, $where) {
			print STDOUT "$message\n" if ($verbose);
		}
		
		# Write message to log
		if ( grep /log/, $where ) {
			# Format output for log
			my $nowString = localtime;
			my $output =  $nowString . " - " . $message;
			chomp($output);
			
			# Write the message to the log
			system("$tools{'echo'} \"$output\" >> $logFile");
		}
	}
}

###############################################################################
# Helper Functions - Plists
###############################################################################

sub readDataPlist {
	my ($dataPlistPath) = @_;

	# Get the config data
	my $dataPlist = loadDefaults( expandFilePath($dataPlistPath) );
	if ( ! defined($dataPlist)) {
		# Error reading the Plist. Display an error and exit
		logMessage("stderr, log", "ERROR: The data plist can't be parsed", $logFile);
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

	if ( -e expandFilePath($statusPlistPath) ) {
		$statusPlist = loadDefaults( expandFilePath($statusPlistPath) );
	} 
	
	if ( ! defined ($statusPlist) ) {
		$statusPlist = NSMutableDictionary->dictionary();
	}

	return $statusPlist;
}

sub readDefaultSettingsPlist {
	my ($defaultSettingsPlistPath) = @_;

	my $defaultSettingsPlist = loadDefaults( expandFilePath($defaultSettingsPlistPath) );
	if ( ! defined($defaultSettingsPlist)) {
		# Error reading the Plist. Display an error and exit
		logMessage("stderr", "ERROR: The default settings plist ($defaultSettingsPlistPath) can't be parsed", "/dev/null");
		exit 1;
	}

	checkDefaultSettingsPlist($defaultSettingsPlist);
	return $defaultSettingsPlist;
}

sub checkDataPlistForRequiredKeys {
	my ($dataPlist) = @_;
	
	my $missingKeys = 0;
	my $dummyVar = undef;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "URLToMonitor")); }; $missingKeys = 1 if $@;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "name"));         }; $missingKeys = 1 if $@;
	eval { $type     = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "type"));         }; $missingKeys = 1 if $@;
	eval { $dummyVar = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "itemToImport")); }; $missingKeys = 1 if $@;
	
	if ($missingKeys) {
		# Ensure that the required keys were present
		logMessage("stderr, log", "ERROR: Missing Keys in Data Plist. Require autoMunkiImporter dict, with URLToMonitor, name, type, and itemToImport strings.", $logFile);
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
			logMessage("stderr, log", "ERROR: Missing Keys in Data Plist. Require autoMunkiImporter dict, with downloadLinkRegex when type = dynamic.", $logFile);
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

	if ($type =~ /static/i) {
		$type = "static";
	} elsif ($type =~ /dynamic/i) {
		$type = "dynamic";	
	} elsif ($type =~ /sparkle/i) {
		$type = "sparkle";	
	} else {
		logMessage("stderr, log", "ERROR: Type: \"$type\" is unsupported. Supported types are static, dynamic, or sparkle.", $logFile);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
}

sub checkDefaultSettingsPlist {
	my ($defaultSettingsPlist) = @_;
	
	my @expectedKeys = ("userAgent", "logFile", "logFileMaxSizeInMBs", "maxNoOfLogsToKeep", 
						"statusPlistPath", "emailReports", "smtpServer", "fromAddress", 
						"toAddress", "subjectPrefix", "makecatalogs", "version");

	foreach my $key (@expectedKeys) {
		my $dummyVar = "";
		eval { $dummyVar = perlValue(getPlistObject($defaultSettingsPlist, "$key")); }; 
		if ($dummyVar eq "" || $dummyVar =~ /REPLACE_ME/i) {
			logMessage("stderr", "ERROR: Key: $key does not have an appropriate value in the default settings plist. Exiting...", $logFile);
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
				logMessage("stderr, log", "ERROR: Redirect Loop found", $logFile);
				$subject = $subjectPrefix . " ERROR: $name - Redirect Loop found";
				$message = "While determining the URL of the download a redirect loop was detected.\nScript terminated...";
				sendEmail(subject => $subject, message => $message);
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

	my $headers = `$tools{'curl'} --head --location --user-agent \"$userAgent\" \"$url\" 2>/dev/null`;
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
		logMessage("stdout, log", "Redirect(s) found. New URL is: $url", $logFile);
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
	}
	
	return $foundLink;
}

sub findDownloadLinkOnPage {
	my ($url, $dataPlist) = @_;
	
	my $foundLink = undef;
	
	# Download the page, using our provided user agent
	my $mech = WWW::Mechanize->new();
	$mech->agent($userAgent);
	logMessage("stdout, log", "Using User Agent: " . $mech->agent, $logFile);

	eval { $mech->get($url); };
	if ($@) {
		logMessage("stderr, log", "ERROR: Can't download content of URL. Error was: $@", $logFile);
		$subject = $subjectPrefix . " ERROR: $name - Can't download content of URL";
		$message = "Can't download content of URL. Error returned was:-\n$@\nScript terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			return undef;
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
	
	logMessage("stdout, log", "Download Link found: $foundLink", $logFile);
	
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
			logMessage("stdout, log", "Checking: Date: " . timestampToString($itemPubDate) . " ($itemPubDate), Version: $itemVer, URL: $itemURL", $logFile);
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
						logMessage("stdout, log", "Newer version found in feed (by release date)...", $logFile);
					} elsif ($itemVer gt $version) {
						# Release date is the same, but this is a newer version, so use this instead of any previously found items
						# version comparison can be hit and miss, so preference is given to the modification date
						$pubDate = $itemPubDate;
						$version = $itemVer;
						$finalUrl = $itemURL;
						logMessage("stdout, log", "Newer version found in feed (by version as release date was the same)...", $logFile);
					}
				}
			}		
		}
	}

	# URL can have spaces, so encode them.
	$finalUrl = escapeURL($finalUrl);
	logMessage("stdout, log", "URL for latest sparkle update is: $finalUrl", $logFile);

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
			Subject =>	$args{subject}
		} );
	
		# We can print to $mailer just as we would print to STDOUT or any other file handle...
		print $mailer $args{message};
		$mailer->close();
	}
}

sub updateStatus {
	my ($name, $message) = @_;

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

}

sub updateLastModifiedDate {
	my ($modifiedDate, $dataPlist, $dataPlistPath) = @_;
	my @modifiedDateArray = ("-d", "autoMunkiImporter", "-d", "modifiedDate", "-t", $modifiedDate);
	setPlistObjectForce( $dataPlist, \@modifiedDateArray );
	saveDefaults($dataPlist, $dataPlistPath);
}

sub hackAroundLicenceAgreementsInDiskImages {
	my ($plistFile) = @_;

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
	$path = expandFilePath($path);
	$path =~ s/ /\\ /g;
	my @dirContents = <$path/*>;
	my $item;
	foreach $item (@dirContents) {
		if (-f $item && $item =~ /\.plist$/ && $item !~ /_.+\.plist$/ ) {
			# Plist, so add it to the array
			push(@dataPlists, $item);
		}
		if (-d $item) {
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
	
	# Logging
	$logFile = perlValue(getPlistObject($defaultSettingsPlist, "logFile"));
	$logFile = expandFilePath($logFile);
	$logFileMaxSizeInMBs = perlValue(getPlistObject($defaultSettingsPlist, "logFileMaxSizeInMBs"));
	$maxNoOfLogsToKeep = perlValue(getPlistObject($defaultSettingsPlist, "maxNoOfLogsToKeep"));
	
	# User Agent
	$userAgent = perlValue(getPlistObject($defaultSettingsPlist, "userAgent"));

	# Email
	$emailReports = perlValue(getPlistObject($defaultSettingsPlist, "emailReports"));
	$smtpServer = perlValue(getPlistObject($defaultSettingsPlist, "smtpServer"));
	$fromAddress = perlValue(getPlistObject($defaultSettingsPlist, "fromAddress"));
	$toAddress = perlValue(getPlistObject($defaultSettingsPlist, "toAddress"));
	$subjectPrefix = perlValue(getPlistObject($defaultSettingsPlist, "subjectPrefix"));

	# Status Plist
	$statusPlistPath = perlValue(getPlistObject($defaultSettingsPlist, "statusPlistPath"));

	# Make Catalogs
	$makecatalogs = perlValue(getPlistObject($defaultSettingsPlist, "makecatalogs"));
}

###############################################################################
# Main App - Prep
###############################################################################

# Check Pre-reqs are meet
checkPerlDependencies() or die;

# Handle Command Line options
GetOptions ('data=s'     	=> \$dataPlistPath, 
			'settings=s'	=> \$defaultSettingsPlistPath,
			'download'   	=> \$downloadOnly, 
			'verbose|v'  	=> \$verbose, 
			'progress|p'	=> \$progress,
			'help|h|?'   	=> \$help, 
			'version'    	=> \$showScriptVersion, 
			'ignoreModDate' => \$ignoreModDate,
			'test' 			=> \$testScript,
			'reset'      	=> \$reset);

# Show the help info if requested
pod2usage(1) if $help;

# Show the version if requested
if ($showScriptVersion) {
	print $scriptVersion . "\n";
	exit 0;
}

# Check $dataPlistPath was set, and that a file exists at the location 
if (! defined($dataPlistPath) || ! -e $dataPlistPath) {
	# No argument, or does not exist, bail showing usage
	logMessage("stderr", "ERROR: The data plist (or directory of plists) needs to be provided via a command line argument of --data /path/to/data.plist", "/dev/null");
	pod2usage(1);
	exit 1;
}

# Get default settings
$defaultSettingsPlist = readDefaultSettingsPlist($defaultSettingsPlistPath);
defaultSettings($defaultSettingsPlist);

# Check Munki Repo is available, and that all of the required tools are also available
checkMunkiRepoIsAvailable() or die;
checkTools() or die;

# Check paths are writable
checkPermissions();
if ($testScript) {
	print "All tests passed...\n";
	exit 0;
}

# Setup Status Plist
$statusPlist = readStatusPlist($statusPlistPath);

if (-d $dataPlistPath) {
	# Path to a directory of plists
	getDataPlists($dataPlistPath);
	$dataPlistSourceIsDir = 1;
} else {
	# Path to a specific plist, not a directory
	push(@dataPlists, $dataPlistPath);
	$dataPlistSourceIsDir = 0;
}

# Loop through each of the data plists that have been found and process them
foreach $dataPlistPath (@dataPlists) {
	# Reset the default settings (which maybe overwritten by the dataPlist
	defaultSettings($defaultSettingsPlist);

	# Read the data plist, which contains config for this script
	$dataPlist = readDataPlist($dataPlistPath);
	
	# Get product name
	$name = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "name"));

	# Get optional Log File name (overwriting the one in the default settings plist)
	eval { $logFile = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "logFile")); };	
	# Prepare the log for use
	$logFile = expandFilePath($logFile);
	prepareLog($logFile);
	logMessage("stdout, log", "App Name: $name", $logFile);
	logMessage("stdout, log", "Processing Type: $type", $logFile);

	# Get optional email settings (overwriting the ones in the default settings plist)
	eval { $emailReports = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "emailReports")); };
	eval { $fromAddress = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "emailFrom")); };
	eval { $toAddress = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "emailTo")); };
	
	# Check for optional disabled key
	my $disabled = 0; # False
	eval { $disabled = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "disabled")); };
	if ($disabled) {
		logMessage("stdout, log", "Automatic Update Check is DISABLED. Exiting...", $logFile);
		updateStatus($name, "Automatic Update Check is DISABLED. Exiting...");
		next;
	}
	
	# Show basic progress info
	if ($progress) {
		print "App Name: $name\n";
	}
	
	
	###############################################################################
	# Main App - Step 1: Get the URL for the download
	###############################################################################
	
	my $url = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "URLToMonitor"));
	if ($url eq "") {
		logMessage("stderr, log", "ERROR: URL is missing. Exiting...", $logFile);
		updateStatus($name, "ERROR: URL is missing. Exiting...");
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# Replace the XML encoding of &
	$url =~ s/&amp;/&/g;
	
	my $initialURL = $url;
	logMessage("stdout, log", "Initial URL: $initialURL", $logFile);
	
	# Some sites will return different content based off the user agent
	# Optionally overwrite the default user agent if present in the plist
	eval { $userAgent = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "userAgent")); };
	logMessage("stdout, log", "Determining Final URL...", $logFile);
	
	if ($type eq "static") {
		$url = findFinalURLAfterRedirects($url);
	} elsif ($type eq "dynamic") {
		$url = findDownloadLinkOnPage($url, $dataPlist);
	} elsif ($type eq "sparkle") {
		$url = findDownloadLinkFromSparkleFeed($url);
	}
	
	if (! defined $url || $url eq "") {
		logMessage("stderr, log", "ERROR: Can't determine final URL. Exiting...", $logFile);
		updateStatus($name, "ERROR: Can't determine final URL. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Can't determine final URL";
		$message = "Can't determine final URL. Script terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	logMessage("stdout, log", "Final URL: $url", $logFile);
	
	###############################################################################
	# Main App - Step 2: Determine if file has changed since we last processed it
	###############################################################################
	
	logMessage("stdout, log", "Determine if file has changed since we last processed it...", $logFile);
	# Get headers for download
	my $headers = `$tools{'curl'} --head --user-agent \"$userAgent\" \"$url\" 2>&1`;
	# Convert line endings to \n, and split the headers into lines
	$headers =~ s/\r/\n/gi;
	my @headers = split /\n/, $headers;
	
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
		logMessage("stderr, log", "ERROR: Problem accessing file to download. The error and / or headers were\n$headers", $logFile);
		updateStatus($name, "ERROR: Problem accessing file to download. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Problem accessing file to download";
		$message = "There was a problem accessing the file to download. The URL $url returned the following error and / or headers:-\n$headers\n\nScript terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# Die if the modification date isn't set
	if ($modifiedDate eq "" || $modifiedDate == 0) {
		logMessage("stderr, log", "ERROR: Modification date of download not found. The headers were\n$headers", $logFile);
		updateStatus($name, "ERROR: Modification date of download not found. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Modification Date not found";
		$message = "Modification date of download not found, indicating a problem.\n\nThe URL $url returned the following headers\n$headers. Script terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# If just resetting the modified date, bail at this stage
	if ($reset) {
		updateLastModifiedDate($modifiedDate, $dataPlist, $dataPlistPath);
		logMessage("stdout, log", "Modification date rest to current modification date of url", $logFile);
		updateStatus($name, "Modification date rest to current modification date of url.");
		next;
	}
	
	# Compare latest modification date to what we have already packaged
	my $currentPackagedModifiedDate = 0;
	if (!$downloadOnly) {
		eval { $currentPackagedModifiedDate = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "modifiedDate")); };
		
		logMessage("stdout, log", "Modification Date of Download:                     " . timestampToString($modifiedDate) . " ($modifiedDate)", $logFile);
		logMessage("stdout, log", "Modification Date of Previously Packaged Download: " . timestampToString($currentPackagedModifiedDate) . " ($currentPackagedModifiedDate)", $logFile);
	
		if ($modifiedDate <= $currentPackagedModifiedDate) {
			logMessage("stdout, log", "No new version of $name found. Exiting...", $logFile);
			updateStatus($name, "No new version found.");
			if (! $ignoreModDate) {
				next;
			}
		} else {
			logMessage("stdout, log", "New version of $name found...", $logFile);
		}	
	}
	
	###############################################################################
	# Main App - Step 3: Download the new version of the app
	###############################################################################
	
	# Sanity check download to ensure it's of a supported type
	my $validExtension = 0; 
	foreach my $supportedDownloadType(@supportedDownloadTypes) {
		if ($url =~ m/($supportedDownloadType)$/) {
			$validExtension = 1;	
		}
	}
	
	if (! $validExtension) {
		# Download is in an unsupported format.
		logMessage("stderr, log","ERROR: Download is in an unsupported format. Exiting...\n", $logFile);
		updateStatus($name, "ERROR: Download is in an unsupported format. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Download is in an unsupported format";
		$message = "URL implies that the download would be in an unsupported format ($url). Script terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}	
	
	my $tmpDIR = File::Temp->newdir();
	my $downloadFileName = addTrailingSlash($tmpDIR) . basename($url);
	logMessage("stdout, log", "Starting download of Final URL to $downloadFileName...", $logFile);
	
	# Show basic progress info
	if ($progress) {
		print "Downloading: $url\n         to: $downloadFileName\n\n";
	}
	
	# Show progress if in verbose or progress modes
	my $progressOuptutLocation = "";
	if (! $verbose && ! $progress) {
		$progressOuptutLocation = "2>/dev/null";
	}
	
	system("$tools{'curl'} --user-agent \"$userAgent\" -o \"$downloadFileName\" \"$url\" $progressOuptutLocation");
	logMessage("stdout, log", "Download complete...", $logFile);
	
	
	# If download only is set, copy the downloaded file to /tmp and quit
	if ($downloadOnly) {
		# Copy to user defined spot
		my $tmpLocation = "/private/tmp/" . basename($downloadFileName);
		system ("$tools{'cp'} -r \"$downloadFileName\" \"$tmpLocation\"");
	
		$message = "Download Only option was selected. File saved to: \"$tmpLocation\". Exiting...";
		updateStatus($name, "Download only selected. File downloaded to $tmpLocation");
		logMessage("log", $message, $logFile);
		print $message . "\n";
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
	
	logMessage("stdout, log", "Extracting download and finding item we wish to import...", $logFile);
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
			logMessage("stderr, log","ERROR: Can't mount disk image. Exiting...\n", $logFile);
			updateStatus($name, "ERROR: Can't mount disk image. Exiting...");
			$subject = $subjectPrefix . " ERROR: $name - Can't mount disk image.";
			$message = "Can't read the plist that hdiutil generates when attempting to mount the disk image. The disk image downloaded from $url is most likely corrupt. Script terminated...\n\n";
			sendEmail(subject => $subject, message => $message);		
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}
	
		my @pathToMountPointKey = pathsThatMatchPartialPathWithGrep($hdiutilPlist, "system-entities", "*", "mount-point");
		if ( ! defined($hdiutilPlist) || $#pathToMountPointKey < 0) {
			# Error reading the Plist. Display an error and exit
			logMessage("stderr, log","ERROR: Can't determine mount point of DMG. Exiting...\n", $logFile);
			updateStatus($name, "ERROR: Can't determine mount point of DMG. Exiting...");
			$subject = $subjectPrefix . " ERROR: $name - Can't determine mount point of DMG";
			$message = "Can't determine the mount point of the disk image downloaded from $url. Script terminated...";
			sendEmail(subject => $subject, message => $message);
			if ($dataPlistSourceIsDir) {
				next;
			} else {
				exit 1;
			}
		}
	
		# Get the mount point using the previously found path.
		my $mountPoint = perlValue(getPlistObject($hdiutilPlist, "system-entities", ${$pathToMountPointKey[0]}[1], "mount-point"));
		logMessage("stdout, log", "Disk image mounted at $mountPoint...", $logFile);
	
		# Find and copy item from disk image
		$target = `$tools{'find'} \"$mountPoint\" -iname \"$itemToImport\" -print 2>/dev/null`;
		if ($target ne "") {
			# Item was found, so copy it out of the disk image
			chomp($target);
			my $dest = addTrailingSlash($tmpDIR) . basename($target);
			system ("$tools{'cp'} -r \"$target\" \"$dest\"");
			logMessage("stdout, log", "Copying item \"$target\" to \"$dest\"", $logFile);
			$target = $dest;
		}
		
		# Unmount and Detach Disk Image
		system("$tools{'hdiutil'} detach $mountPoint > /dev/null");		
	} elsif ($downloadFileName =~ /.pkg$/ || $downloadFileName =~ /.mpkg$/) {
		# Flat package, so no prep is required
		$target = $downloadFileName;
	} else {
		# Download is in an unsupported format - Should be caught in step 3, but here as a failsafe.
		logMessage("stderr, log","ERROR: Download is in an unsupported format. Exiting...\n", $logFile);
		updateStatus($name, "ERROR: Download is in an unsupported format. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Download is in an unsupported format";
		$message = "Download is in an unsupported format ($downloadFileName). Script terminated...";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	# Check that the target file to import actually exists (sanity check the about if)
	chomp($target);
	if (! -e "$target") {
		# Can't find downloaded file to import into Munki.
		logMessage("stderr, log","ERROR: Can't find item ($itemToImport) to import into Munki. Exiting...\n", $logFile);
		updateStatus($name, "ERROR: Can't find item ($itemToImport) to import into Munki. Exiting...");
		$subject = $subjectPrefix . " ERROR: $name - Can't find downloaded file to import into Munki";
		$message = "Can't find item to import into Munki. Script terminated...\n\n$name looked for $itemToImport\n";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	}
	
	logMessage("stdout, log", "Item extracted to $target...", $logFile);
	
	
	###############################################################################
	# Main App - Step 5: Import into Munki
	###############################################################################
	
	logMessage("stdout, log", "Importing app into Munki...", $logFile);
	# Show basic progress info
	if ($progress) {
		print "Importing app into Munki...\n";
	}
	
	# Get optional command line options for Munki Import
	my $munkiimportOptions = "";
	eval { $munkiimportOptions = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "munkiimportOptions")); };
	if ($munkiimportOptions ne "") {
		logMessage("stdout, log", "Munki Import command line options: --nointeractive --name \"$name\" $munkiimportOptions", $logFile);
	}
	# Import into Munki
	my $munkiOutput = `$tools{'munkiimport'} --nointeractive --name "$name" $munkiimportOptions \"$target\" | $tools{'grep'} pkgsinfo`;
	
	# Get the PkgInfo File for the package we just imported
	my $pkgInfoPlistPath = $munkiOutput;
	$pkgInfoPlistPath =~ m/\/(.*)?/gi;
	$pkgInfoPlistPath = substr($&, 0, -3);
	logMessage("stdout, log", "PkgInfo File: $pkgInfoPlistPath...", $logFile);
	
	logMessage("stdout, log", "Imported app into Munki...", $logFile);
	
	###############################################################################
	# Main App - Step 6: Update PkgInfo and Data Plists
	###############################################################################
	
	logMessage("stdout, log", "Updating Pkginfo...", $logFile);
	
	# Read Pkginfo file
	my $packagedVersion = "";
	my $pkgInfoPlist = loadDefaults( $pkgInfoPlistPath );
	if ( ! defined($pkgInfoPlist)) {
		# Error reading the Plist. Display an error and skip items that relied on it
		logMessage("stderr, log", "ERROR: The Pkginfo plist can't be read. The import to Munki failed....", $logFile);
		updateStatus($name, "ERROR: The Pkginfo plist can't be read. The import to Munki failed...");
		$subject = $subjectPrefix . " ERROR: $name - Import to Munki Failed";
		$message = "The Pkginfo plist can't be read. The import to Munki failed.\n";
		sendEmail(subject => $subject, message => $message);
		if ($dataPlistSourceIsDir) {
			next;
		} else {
			exit 1;
		}
	} else {
			# Add or override Munki's default keys with ones in our data plist
		my %keysHash = perlHashFromNSDict(getPlistObject($dataPlist));
		foreach my $key (sort(keys %keysHash)) {
			# Remove any of the existing keys
			if ($key ne "autoMunkiImporter") {
				logMessage("stdout, log", "Overriding Pkginfo key: $key", $logFile);
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
		$packagedVersion = perlValue(getPlistObject($pkgInfoPlist, "version"));
		setPlistObject($dataPlist, "autoMunkiImporter", "modifiedDateCorrospoindingVersion", $packagedVersion);
		saveDefaults($dataPlist, $dataPlistPath);
	}
	
	# Update packaged modification date in data plist, so that we don't attempt to repackage this version
	updateLastModifiedDate($modifiedDate, $dataPlist, $dataPlistPath);
	
	logMessage("stdout, log", "Pkginfo Updated...", $logFile);
	logMessage("stdout, log", "$name version $packagedVersion was imported into Munki. Please test the app to ensure it functions correctly before enabling for any non Dev / Test users.", $logFile);
	
	###############################################################################
	# Main App - Step 7: Notify Package has been imported
	###############################################################################
	
	$subject = $subjectPrefix . " " . $name . " (v" . $packagedVersion . ") has been imported";
	$message = $name . " (v" . $packagedVersion . ") has been imported into Munki.\n\nIt's pkginfo file is at $pkgInfoPlistPath.";
	sendEmail(subject => $subject, message => $message);
	recordNewVersion(name => $name, 
	        		 version => $packagedVersion, 
	        		 modifiedDate => $modifiedDate, 
	        		 initialURL   => $initialURL, 
	        		 finalURL     => $url, 
	        		 pkginfoPath  => $pkgInfoPlistPath);
		
	###############################################################################
	# Main App - Step 8: Optionally run makecatalogs
	###############################################################################
	
	eval { $makecatalogs = perlValue(getPlistObject($dataPlist, "autoMunkiImporter", "makecatalogs")); };
	if ($makecatalogs) {
		logMessage("stdout, log", "Rebuilding catalogs...", $logFile);
		system("$tools{'makecatalogs'} > /dev/null");
	}
	
	logMessage("stdout, log", "Finished...", $logFile);
}

exit 0;

__END__

=head1 NAME

autoMunkiImporter - Automatically import apps into Munki

=head1 SYNOPSIS

autoMunkiImporter.pl --data /path/to/data[.plist] [options]

 Options:
	--data /path/to/data[.plist]		Path to the data plist or directory containing data plists (required)
	--download 				Only download the file (doesn't import into Munki)
	--help | -?				Show this help text
	--ignoreModDate				Ignore the modified date and version info from the data plist
	--progress				Prints progress information to STDOUT
	--reset					Resets the modified date for an app
	--settings /path/to/settings.plist	Optional path to a default settings plist
	--test					Tests that the script has all of the required items and rights
	--verbose				Show verbose output to STDOUT
	--version				Prints scripts version to STDOUT

	man autoMunkiImporter.pl		For more detailed information

=head1 OPTIONS

=over 8

=item B<--data> /path/to/data[.plist]

Path to the data plist, or a directory containing data plists (required). The data plist contains 
the specific configuring this script to download a particular app. 

See B<DATA PLIST> for structure of the plist.

=item B<--download | -n>

Download the file to /tmp, without importing the item to Munki. It does B<not> update the modified 
time or import to Munki.

=item B<--help | -?>

Show this help text

=item B<--ignoreModDate>

Ignore the modified date and version info from the data plist and exit. This will cause the item to 
be (re)imported into Munki.

=item B<--progress>

Reports progress of the script to STDOUT

=item B<--reset>

Resets the modified date of an app to the current modification date, without downloading or 
importing the item into Munki. Use this when the latest version of an app is in your Munki repo, so 
that this script doesn't attempt to re add it, of if you want to skip a version.

=item B<--settings /path/to/settings.plist>

Optional path to a default settings plist. If not provided /Library/Application Support/autoMunkiImporter/_DefaultConfig.plist 
is used. This plist contains the default settings for the script, some of which can be overridden by
the data plists.

=item B<--test>

Checks that the script passes it's initial checks, and that it has permissions to write to
the appropriate locations.

=item B<--verbose>

In addition to writing to the log, show log and progress messages on STDOUT

=item B<--version>

Displays the scripts version

=back

=head1 DESCRIPTION

B<autoMunkiImporter.pl> will based on the input data determine if there is a new version of an 
application available. If a new version is available it will download the new file, extract it, and 
then import it into Munki.

It can handle static urls, dynamic urls where the URL or link to the url change based off the 
version (it can also handle landing pages before the actual download), and sparkle rss feeds. This 
generic approach should allow you to monitor most applications.

It supports downloads in flat PKGs, DMG (including support for disk images with licence agreements), 
ZIP, TAR TAR.GZ, TGZ, and TBZ. It will import a single item (APP or PKG) from anywhere within the 
download, so the content doesn't have to be in the top level folder. This is achieved by using find 
to locate the item (e.g. the Adobe Flash Player.pkg from within the Adobe Flash download).

=head1 DATA PLIST

=head2 REQUIRED KEYS

The data plist needs to contain a dictionary called B<autoMunkiImporter>, which contains a series 
of strings.

=over 8

=item B<URLToMonitor> <string>

This is the URL to monitor for new versions of an application

=item B<name> <string>

The name used within Munki (and as an identifier in the logs or emails from this script).

=item B<type> <string>

The type needs to be one of the following supported types:-

=over 8

=item B<static>

Use static when the URL doesn't change. This is for sites that just update the file at the same URL 
when a new version is released. E.g. Google Chrome

=item B<dynamic>

Use dynamic when the download link on a website changes with each new version. Dynamic also has 
additional required and optional keys. See below:-

=over 8

=item B<downloadLinkRegex> - Required

This is the either the text of the download link 
(e.g. THIS TEXT from: <a href="http://example.com/app.dmg> THIS TEXT </a>), or a perl compatible 
regular expression for the same text.

=item B<secondLinkRegex> - Optional

Some web pages will redirect to a second page which contains the actual download. In this case this 
key is used to find the download. It works the same as the downloadLinkRegex key, but if the link 
isn't found it then just searches the entire page (for example they use Javascript to cause the 
download to start automatically).

=back

=item B<sparkle>

Apps that use the Sparkle framework have a RSS based Appcast that list updates. This option will 
parse that feed for the update. To find if an app uses Sparkle run: 
C<find /path/to/app -name Sparkle.framework -print>

=back

=item B<itemToImport> <string>

This is the name of the item to be imported into Munki. For example My App.app. Find is used to 
locate the app, so it can be anywhere in the download (even within app bundles).

=back

=head2 OPTIONAL KEYS

=over 8

=item B<disabled> <boolean>

If true, will disable checking of the app. Useful if you are checking a directory of data plists and
want to skip an app without removing it.

=item B<emailReports> <boolean>

If true, email reports will be sent on successfully importing a new app, or on a critical error 
(besides the initial environment checks)

=item B<emailTo> <string>

Email address to send reports to. A default Email address should be specified in the script, but 
if present in the data file it will override the default.

=item B<emailFrom> <string>

Email address to send reports from. A default Email address should be specified in the script, but 
if present in the data file it will override the default.

=item B<logFile> <string>

Path to log file. A default log file should be specified in the script, but if present in the data 
file it will override the default.

=item B<makecatalogs> <boolean>

If true, I<makecatalogs> is run after the app is imported into Munki.

=item B<munkiimportOptions> <string>

Additional command line options to pass to I<munkiimport>. See munkiimport --help and 
makepkginfo --help for available options.

Also see B<MUNKI KEYS> for an additional way of providing data to Munki.

=item B<userAgent> <string>

Some websites return different content based on the User Agent. If this key is present it will 
override the user agent in the script.

=back

=head2 MUNKI KEYS

In addition to providing options to munkiimport via the munkiimportOptions key, you can at the top 
level of the data plist include keys that will be copied
across to the pkginfo file. 

This can be useful with items like pre and post scripts, so that instead of having to maintain 
copies of the script, you can just copy the item into the data plist 
like you would to a pkginfo and the script will automatically add it. 

Any keys at the top level of the plist will override those in the generated pkginfo. So if you say 
used the munkiimportOptions key and set --catalog prod, but had a catalog array at the top of the 
data plist that contained 2 strings (autopkg, dev) then the final pkginfo would be set to autopkg, 
and dev, not prod.

=head2 EXAMPLE

 <?xml version="1.0" encoding="UTF-8"?>
 <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
 <plist version="1.0">
 <dict>
	<key>autoMunkiImporter</key>
	<dict>
		<key>URLToMonitor</key>
		<string>http://www.skype.com/go/getskype-macosx.dmg</string>
		<key>name</key>
		<string>Skype</string>
		<key>type</key>
		<string>direct</string>
		<key>itemToImport</key>
		<string>Skype.app</string>
		<key>emailReports</key>
		<true/>
		<key>makecatalogs</key>
		<true/>
	</dict>
	<key>catalogs</key>
	<array>
		<string>dev</string>
	</array>
 </dict>
 </plist>

=head1 DEFAULT SETTINGS PLIST

The default settings plist contains configuration for the script. It has a series of required keys.

=head2 REQUIRED KEYS

=over 8

=item B<userAgent> <string>

User Agent string to use. Recommendation is Safari's User Agent for your primary OS.

=item B<logFile> <string>

Path to the log file

=item B<logFileMaxSizeInMBs> <number>

Size in MBs that log files can grow to until they are rolled.

=item B<maxNoOfLogsToKeep> <number>

Maximum number of logs to keep.

=item B<statusPlistPath> <string>

Path to status plist, which gives a summary of all apps being monitored.

=item B<emailReports> <boolean>

Whether email should be sent.

=item B<smtpServer> <string>

SMTP server to use for sending email. Needed regardless of whether emailReports is true or false.

=item B<fromAddress> <string>

From email address to use for sending email. Needed regardless of whether emailReports is true or 
false.

=item B<toAddress> <string>

To email address to use for receiving email. Needed regardless of whether emailReports is true or 
false.

=item B<subjectPrefix> <string>

Prefix to add to email subject lines. Needed regardless of whether emailReports is true or false.

=item B<makecatalogs> <boolean>

Whether makecatalogs should be run at the end of each import

=item B<version> <number>

Version number of the settings plist. This should be 1.

=back

=head1 DEPENDENCIES

This perl script requires the following perl modules to be installed:-
 * Date::Parse
 * Mail::Mailer
 * URI::Escape
 * URI::URL
 * WWW:Mechanize
 
You can test if a module is installed by running perl -MModule::Name -e 1 on the command line. You 
will get an error if it's not installed. Not there is no space between -M and the module name, 
e.g. -MDate::Parse.
 
It also requires the perlplist.pl script to be in the same directory as this script. Please see that 
script for it's copyright statement.

=head1 FINDING THE URL

In Safari you can either right click on a link and "Copy Link", or view the pages source to determine 
the URL.

For tricker pages, and apps using Sparkle to update I recommend using SquidMan 
http://squidman.net/squidman/.

=head2 SQUIDMAN

SQUIDMAN is a easy to use SQUID proxy. We can use it to log all requests, and using this information 
build our data plist.

Once you have it installed, in the Template under preferences add "strip_query_terms off". This will 
cause the entire URL to be shown. Start (or restart) SquidMan and then set the proxy server for your 
machine to localhost:8080 (or the appropriate values). Then 
tail -f ~/Library/Logs/squid/squid-access.log and you will see what URLs are accessed.

=head1 TROUBLESHOOTING

The best strategy is to use curl --head --location http://www.example.com/path/to/url.ext and review
it's content. Sites like Google Code block retrieving headers which is required for this script to 
work. In this case one of the returned headers will be X-Content-Type-Options: nosniff.

Also try using different (or no) User Agents (curl --user-agent "my agent").

=head1 AUTHOR

Adam Reed <adam.reed@anu.edu.au>

=cut
