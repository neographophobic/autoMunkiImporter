# Makefile that utilises Luggage https://github.com/unixorn/luggage
# to create an installer package for Auto Munki Importer.

include /usr/local/share/luggage/luggage.make

PACKAGE_VERSION=0.3.0
TITLE=AutoMunkiImporter
REVERSE_DOMAIN=com.github.neographophobic.pkg
PLIST_PATH=prototype.plist
PAYLOAD=\
		pack-library-application_support-autoMunkiImporter \
		pack-library-logs-autoMunkiImporter \
		pack-private-etc-pathsd \
		pack-usr-local-autoMunkiImporter \
		pack-usr-local-share-man-man1 \
		pack-resource-license \
		pack-resource-readme \
		pack-resource-postflight

# Example Data Plists
pack-library-application_support-autoMunkiImporter: l_Library_Application_Support_autoMunkiImporter
	@sudo ${CP} -R -L _example_plists ${WORK_D}/Library/Application\ Support/autoMunkiImporter/
	@sudo chmod 0664 ${WORK_D}/Library/Application\ Support/autoMunkiImporter/_example_plists/*
	@sudo chown -R root:admin ${WORK_D}/Library/Application\ Support/autoMunkiImporter/_example_plists

l_Library_Application_Support_autoMunkiImporter: l_Library_Application_Support
	@sudo mkdir -p ${WORK_D}/Library/Application\ Support/autoMunkiImporter
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support/autoMunkiImporter
	@sudo chmod 0775 ${WORK_D}/Library/Application\ Support/autoMunkiImporter

# Logs DIR
pack-library-logs-autoMunkiImporter: l_Library_Logs_autoMunkiImporter

l_Library_Logs_autoMunkiImporter: l_Library_Logs
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
	@sudo chmod 0755 ${WORK_D}/usr/local/autoMunkiImporter/autoMunkiImporter.pl
	@sudo chown -R root:wheel ${WORK_D}/usr/local/autoMunkiImporter/autoMunkiImporter.pl
	@sudo ${CP} -R ../perlplist.pl ${WORK_D}/usr/local/autoMunkiImporter/
	@sudo chmod 0755 ${WORK_D}/usr/local/autoMunkiImporter/perlplist.pl
	@sudo chown -R root:wheel ${WORK_D}/usr/local/autoMunkiImporter/perlplist.pl
#	@sudo ${CP} -R ../tools/testAllApps.pl ${WORK_D}/usr/local/autoMunkiImporter/
#	@sudo chmod 0755 ${WORK_D}/usr/local/autoMunkiImporter/testAllApps.pl
#	@sudo chown -R root:wheel ${WORK_D}/usr/local/autoMunkiImporter/testAllApps.pl

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

# Package License and Readme
pack-resource-license:
	@sudo ${INSTALL} -m 755 license.rtf ${RESOURCE_D}/License.rtf

pack-resource-readme:
	@sudo ${INSTALL} -m 755 readme.rtf ${RESOURCE_D}/ReadMe.rtf

pack-resource-postflight:
	@sudo ${INSTALL} -m 755 postflight.sh ${RESOURCE_D}/postflight

# Overwrite Luggage defaults
modify_packageroot:
	@sudo chmod 0755 ${WORK_D}/Library
	@sudo chown root:wheel ${WORK_D}/Library
	@sudo chmod 0755 ${WORK_D}/Library/Application\ Support
	@sudo chown root:admin ${WORK_D}/Library/Application\ Support
