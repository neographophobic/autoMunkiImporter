#!/bin/bash

# Handle Data Plists
DATA_PLIST_PATH="/Library/Application Support/autoMunkiImporter"
for FILE in "$DATA_PLIST_PATH/_example_plists/"*
do
	echo $FILE
	FILENAME=`basename "$FILE"`
    [[ ! -e "$DATA_PLIST_PATH/$FILENAME" ]] && cp "$DATA_PLIST_PATH/_example_plists/$FILENAME" "$DATA_PLIST_PATH/$FILENAME"
done

# Install Perl Dependencies
/usr/local/autoMunkiImporter/autoMunkiImporter.pl --force-install-dependencies
exit $?
