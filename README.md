Auto Munki Importer
===================

> If you are looking at automating Munki, I no longer recommend that you use this code, and instead suggest you use [AutoPkg](https://github.com/autopkg/autopkg) which is actively supported by the Munki community.

> This project is no longer actively maintained.

Auto Munki Importer is a Perl script that will, based on the input data, determine if there is a new version of an application available. If a new version is available it will download the new file, extract it, and then import it into Munki.

It can handle [static](http://neographophobic.github.com/autoMunkiImporter/dataplists.html#static) URLs, [dynamic](http://neographophobic.github.com/autoMunkiImporter/dataplists.html#dynamic) URLs where the URL or link to the URL change based off the version (it can also handle landing pages before the actual download), and [Sparkle](http://neographophobic.github.com/autoMunkiImporter/dataplists.html#sparkle) RSS feeds. This generic approach should allow you to monitor most applications.

It supports downloads in flat PKGs, DMG (including support for disk images with licence agreements), ZIP, TAR, TAR.GZ, TGZ, and TBZ. It will import a single item (Application or PKG) from anywhere within the download, so the content doesn't have to be in the top level folder. This is achieved by using find to locate the item (e.g. the Adobe Flash Player.pkg from within the Adobe Flash download).

How do I get started?
---------------------

Please visit the [Auto Munki Importer](http://neographophobic.github.com/autoMunkiImporter/index.html) website. It contains information on:-

- Downloading Auto Munki Importer and dependencies,
- Installation,
- Configuration,
- The format of the Import Data Plists,
- Tips for Troubleshooting, FAQs and Support infomation, and
- Acknowledgements
