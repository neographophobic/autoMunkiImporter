#!/bin/bash

######## NAME ##########################################################
# removeAutoMunkiImporter.sh - Removes the tools and all associated items

######## DESCRIPTION ################################################### 
# The script will remove all items associated with the tool

######### COMMENTS #####################################################

######### AUTHOR #######################################################
# Adam Reed <adam.reed@anu.edu.au>

echo
echo "Are you sure you want to continue and remove AutoMunkiImporter? [y/N]"
read continue
if [ "$continue" != "y" ];
then
	echo "Exiting..."
	exit 0
fi

rm -r /Library/Application\ Support/autoMunkiImporter
rm -r /Library/LaunchDaemons/au.edu.anu.autoMunkiImporter.plist
rm -r /Library/Logs/autoMunkiImporter
rm -r /usr/local/autoMunkiImporter
rm -r /usr/local/share/man/man1/autoMunkiImporter.pl.1
pkgutil --forget au.edu.anu.pkg.AutoMunkiImporter

