# Makefile that utilises Luggage https://github.com/unixorn/luggage
# to create an installer package for Auto Munki Importer.

include /usr/local/share/luggage/luggage.make

PACKAGE_VERSION=v0.0.0
TITLE=AutoMunkiImporter
REVERSE_DOMAIN=au.edu.anu.pkg
PLIST_PATH=prototype.plist
PAYLOAD=\
		pack-library-application_support-autoMunkiImporter \
		pack-library-launchdaemons \
		pack-library-logs-autoMunkiImporter \
		pack-private-etc-pathsd \
		pack-usr-local-autoMunkiImporter \
		pack-usr-local-share-man-man1 \
		pack-resource-background \
		pack-resource-readme

# Sample Data Plists
pack-library-application_support-autoMunkiImporter: l_Library_Application_Support_autoMunkiImport
	@sudo ${CP} -R ../sample_plists/*.plist ${WORK_D}/Library/Application\ Support/autoMunkiImport/
	@sudo chmod 0640 ${WORK_D}/Library/Application\ Support/autoMunkiImport/*.plist
	@sudo chown -R root:admin ${WORK_D}/Library/Application\ Support/autoMunkiImport/*.plist

l_Library_Application_Support_autoMunkiImport: l_Library_Application_Support
	@sudo mkdir -p ${WORK_D}/Library/Application\ Support/autoMunkiImport
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support/autoMunkiImport
	@sudo chmod 0770 ${WORK_D}/Library/Application\ Support/autoMunkiImport

# LaunchD Plist
pack-library-launchdaemons: l_Library_LaunchDaemons
	@sudo ${CP} -R ../launchd/au.edu.anu.autoMunkiImporter.plist ${WORK_D}/Library/LaunchDaemons/
	@sudo chmod 0644 ${WORK_D}/Library/LaunchDaemons/au.edu.anu.autoMunkiImporter.plist
	@sudo chown -R root:wheel ${WORK_D}/Library/LaunchDaemons/au.edu.anu.autoMunkiImporter.plist

# Logs DIR
pack-library-logs-autoMunkiImporter: l_Library_Logs_autoMunkiImport

l_Library_Logs_autoMunkiImport: l_Library_Logs
	@sudo mkdir -p ${WORK_D}/Library/Logs/autoMunkiImporter
	@sudo chown root:admin ${WORK_D}/Library/Logs/autoMunkiImporter
	@sudo chmod 0775 ${WORK_D}/Library/Logs/autoMunkiImporter

l_Library_Logs: l_Library
	@sudo mkdir -p ${WORK_D}/Library/Logs
	@sudo chown root:wheel ${WORK_D}/Library/Logs
	@sudo chmod 0755 ${WORK_D}/Library/Logs

# Path
pack-private-etc-pathsd: l_private_etc_pathsd
	@sudo ${CP} -R autoMunkiImporter ${WORK_D}/private/etc/paths.d/
	@sudo chmod 0644 ${WORK_D}/private/etc/paths.d/autoMunkiImporter
	@sudo chown -R root:wheel ${WORK_D}/private/etc/paths.d/autoMunkiImporter

l_private_etc_pathsd: l_private_etc
	@sudo mkdir -p ${WORK_D}/private/etc/paths.d
	@sudo chown root:wheel ${WORK_D}/private/etc/paths.d
	@sudo chmod 0755 ${WORK_D}/private/etc/paths.d

# Script
pack-usr-local-autoMunkiImporter: l_usr_local_autoMunkiImporter
	@sudo ${CP} -R ../autoMunkiImporter.pl ${WORK_D}/usr/local/autoMunkiImporter/
	@sudo chmod 0644 ${WORK_D}/usr/local/autoMunkiImporter/autoMunkiImporter.pl
	@sudo chown -R root:wheel ${WORK_D}/usr/local/autoMunkiImporter/autoMunkiImporter.pl
	@sudo ${CP} -R ../tools/testAllApps.pl ${WORK_D}/usr/local/autoMunkiImporter/
	@sudo chmod 0644 ${WORK_D}/usr/local/autoMunkiImporter/testAllApps.pl
	@sudo chown -R root:wheel ${WORK_D}/usr/local/autoMunkiImporter/testAllApps.pl

l_usr_local_autoMunkiImporter: l_usr_local
	@sudo mkdir -p ${WORK_D}/usr/local/autoMunkiImporter
	@sudo chown root:wheel ${WORK_D}/usr/local/autoMunkiImporter
	@sudo chmod 0755 ${WORK_D}/usr/local/autoMunkiImporter

# Man Page
pack-usr-local-share-man-man1: l_usr_local_share_man_man1
	@sudo ${CP} -R autoMunkiImporter.pl.1 ${WORK_D}/usr/local/share/man/man1/
	@sudo chmod 0644 ${WORK_D}/usr/local/share/man/man1/autoMunkiImporter.pl.1
	@sudo chown -R root:wheel ${WORK_D}/usr/local/share/man/man1/autoMunkiImporter.pl.1

l_usr_local_share_man_man1: l_usr_local_share_man
	@sudo mkdir -p ${WORK_D}/usr/local/share/man/man1
	@sudo chown root:wheel ${WORK_D}/usr/local/share/man/man1
	@sudo chmod 0755 ${WORK_D}/usr/local/share/man/man1

l_usr_local_share_man: l_usr_local_share
	@sudo mkdir -p ${WORK_D}/usr/local/share/man
	@sudo chown root:wheel ${WORK_D}/usr/local/share/man
	@sudo chmod 0755 ${WORK_D}/usr/local/share/man

# Package Background and Readme
pack-resource-background:
	@sudo ${INSTALL} -m 755 background.png ${RESOURCE_D}/background

pack-resource-readme:
	@sudo ${INSTALL} -m 755 readme.rtf ${RESOURCE_D}/ReadMe.rtf

# Overwrite Luggage defaults
modify_packageroot:
	@sudo chmod 0755 ${WORK_D}/Library
	@sudo chown root:wheel ${WORK_D}/Library
	@sudo chmod 0755 ${WORK_D}/Library/Application\ Support
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support
