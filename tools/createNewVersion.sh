#!/bin/bash

######## NAME ##########################################################
# createNewVersion.sh - Tags and builds a new version of the tools

######## DESCRIPTION ################################################### 
# The script will update the version info, check it in, tag it, then
# make a new installer disk image

######### COMMENTS #####################################################
# Assumes you have Luggage installed to create the package with.

######### AUTHOR #######################################################
# Adam Reed <adam.reed@anu.edu.au>

# Check that there is 1 argument
if [ $# -ne 1 ]
then
  echo "Usage: `basename $0` v#.#.#"
  exit 1
fi

# Change into script's dir
DIRNAME=`dirname $0`
cd $DIRNAME
cd ..

# Check there are no changes pending
git status
echo
echo "Are you sure you want to continue and tag this release as $1? [y/N]"
read continue
if [ "$continue" != "y" ];
then
	echo "Exiting..."
	exit 0
fi

# Set Version for Script
echo "Update script version..."
sed "s/my \$scriptVersion = \".*\";/my \$scriptVersion = \"$1\";/" autoMunkiImporter.pl > autoMunkiImporter.pl.out
mv autoMunkiImporter.pl.out autoMunkiImporter.pl

# Create MAN Page
echo "Creating man page..."
pod2man --release $1 --center "Tool Reference Manual" autoMunkiImporter.pl > pkg/autoMunkiImporter.pl.1

# Update the Package Makefile
echo "Update package version..."
sed "s/PACKAGE_VERSION=.*/PACKAGE_VERSION=$1/" pkg/Makefile > pkg/Makefile.out
mv pkg/Makefile.out pkg/Makefile

# Commit Changes to GIT
echo "Adding changes to git..."
git add autoMunkiImporter.pl
git add pkg/autoMunkiImporter.pl.1
git add pkg/Makefile
git commit -m "Setting version numbers for $1"

# Tag release
echo "Tagging version..."
git tag -a -m "Tagging version $1" $1

# Make PKG
echo "Making package disk image..."
cd pkg
sudo make dmg

PKG=`pwd`
echo "Package available at ${PKG}/AutoMunkiImport-$1.dmg"
echo "Done..."