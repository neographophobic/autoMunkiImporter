#!/usr/bin/perl

######## NAME ##########################################################
# testAllApps.pl - Test all Apps download and import as expected

######## DESCRIPTION ################################################### 
# The script will create a new temporary Munki Repo, and then process
# all data plists twice. It's then up to the SysAdmin to determine how
# well the process worked.

######### COMMENTS #####################################################
#

######### AUTHOR #######################################################
# Adam Reed <adam.reed@anu.edu.au>

# Import Perl Modules
use strict;
use warnings;
use Foundation;
use File::Basename;
use CWD qw(realpath);

# Import the PerlPlist Library
my $perlPlistPath;
if (-e dirname($0) . "/perlplist.pl") {
	$perlPlistPath = dirname($0) . "/perlplist.pl";
} else {
	$perlPlistPath = dirname($0) . "/../perlplist.pl";
}
require $perlPlistPath;

# Command to run and test (first run will add --ignoreModDate)
my $scriptPath = $parentPath . "autoMunkiImporter.pl";
my $dataPath   = $parentPath. "data";
my $command =  "$scriptPath --progress --data $dataPath";

# Step 1 - Make Temp Repo
my ($second, $minute, $hour, $dayOfMonth, $month, $yearOffset, $dayOfWeek, $dayOfYear, $daylightSavings) = localtime();
my $year = 1900 + $yearOffset;

my $tempRepoPath = sprintf("/Users/Shared/munki_test_repo_%d%02d%02d%02d%02d", $year, $month, $dayOfMonth, $hour, $minute);

if (-e $tempRepoPath) {
	print STDERR "Error: $tempRepoPath exists. Exiting...\n";
	exit 1;
}

mkdir($tempRepoPath);
mkdir($tempRepoPath . "/catalogs");
mkdir($tempRepoPath . "/manifests");
mkdir($tempRepoPath . "/pkgs");
mkdir($tempRepoPath . "/pkgsinfo");

print "Temporary Munki Repo created at: $tempRepoPath\n";

# Step 2 - Temporarily Change Munki Configure to use the new repo
my $munkiImportConfigPlistPath = expandFilePath("~/Library/Preferences/com.googlecode.munki.munkiimport.plist");
my $munkiImportConfigPlist = loadDefaults( $munkiImportConfigPlistPath );
my $originalRepoPath = perlValue(getPlistObject($munkiImportConfigPlist, "repo_path"));
setPlistObject($munkiImportConfigPlist, "repo_path", $tempRepoPath);
saveDefaults($munkiImportConfigPlist, $munkiImportConfigPlistPath);
print "MunkiImport Repo Path changed from $originalRepoPath to $tempRepoPath\n";

# Step 3 - Run the script
print "Completing first run.\n";
my $startTime = time();
system($command . " --ignoreModDate");
my $endTime = time();
my $elapsedTime = $endTime - $startTime;
print "First run took $elapsedTime seconds\n";

# Step 4 - Run the script again to ensure it's not re-downloading things it shouldn't
print "Completing second run.\n";
$startTime = time();
system($command);
$endTime = time();
$elapsedTime = $endTime - $startTime;
print "Second run took $elapsedTime seconds\n";

# Step 5 - Put MunkiImport back to how it was
setPlistObject($munkiImportConfigPlist, "repo_path", $originalRepoPath);
saveDefaults($munkiImportConfigPlist, $munkiImportConfigPlistPath);
print "MunkiImport Repo Path changed back to $originalRepoPath\n";

# Done
print "Test run complete. Please review $tempRepoPath at your leisure.\n";
exit 0;
