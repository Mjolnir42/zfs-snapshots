zfs-snapshots
=============

A set of scripts for FreeBSD periodic(8) for automated snapshots and backups.

An external script can be triggered for postprocessing of the generated
backups, cleanup of snapshots and cleanup of backups.

Example scripts for encrypted remote storage accessible via FTP are
provided.

Installation
============
1. Copy the periodic scripts in usr/local/etc/periodic/daily on your
   system. Place them in /usr/local/etc/periodic/daily/
2. Copy the scripts in usr/local/sbin onto your system. Place them in
   /usr/local/sbin/ or where you would prefer them to be.
3. Add the following entries to your /etc/periodic.conf.local

    daily_zfs_snapshots_enable="YES"
    Enable or disable the snapshot creation

    daily_zfs_snapshots_create_weekly="YES"
    Tag the snapshot on each saturday as weekly

    daily_zfs_snapshots_create_monthly="YES"
    Tag the snapshot on the first of each month as monthly

    daily_zfs_snapshots_datasets_ignore="pool/backup"
    Which dataset to not create snapshots for. This can be a comma
    separated list of datasets. Child datasets are ignored as well.
    So "pool/backup" also ignores "pool/backup/restore" and
    "pool/backup/test" for example.

    daily_zfs_snapshots_user_namespace="com.1and1.periodic"
    The user namespace used for snapshot user properties. Change as you like,
    but needs to be set to a valid value. See zfs(1).

    daily_zfs_snapshots_backup_enable="YES"
    Enable or disable the creation of backups from the snapshots.

    daily_zfs_snapshots_backup_daily_style="differential"
    This governs how backups from daily snapshots are created. Monthly
    snapshots always create a full stream. Weekly snapshots create an
    incremental stream against the last monthly, or full streams if no
    monthly exists. If this is set to "incremental", the daily snapshots
    always trigger incremental streams against the day before. If set to
    "differential", then incremental streams are generated against the
    last weekly or monthly, whichever is newer. If only daily snapshots
    exist, differential behaves the same as incremental.
    If no prior snapshot exists, a full stream is generated.

    daily_zfs_snapshots_backup_storage_dir="/backup"
    Path where the backup streams are to be written to.

    daily_zfs_snapshots_backup_send_flags="-Dp"
    Flags to pass to zfs send.

    daily_zfs_snapshots_cleanup_enable="YES"
    Enable or disable the cleanup routines. Needs to be set to YES for
    the more specific routine's enable/disable to be evaluated.

    daily_zfs_snapshots_cleanup_viability="10"
    How many days of snapshots and backups you want to keep. Defaults to
    10 days if unset.

    daily_zfs_snapshots_cleanup_clear_snapshots="YES"
    Enable or disable the cleanup of snapshots. All snapshots older than
    specified in the viability option are destroyed. The newest monthly
    as well as the newest weekly snapshot are always kept, if they are
    created.

    daily_zfs_snapshots_cleanup_script_snapshots="/usr/local/sbin/zfs-snapshots-clean.pl"
    The script that implements the snapshot cleanup. Adjust to the path
    you used. If you want to trigger your own script, it must implement
    a `-d $days` command line option that the number of days can be
    passed along to.

Enable backup processing
========================

zfs-snapshots can be configured to execute a processing script for every
stream it generated. This script is passed the absolute path of the
generated streamfile as first and only argument. You can enable this by
setting the following option in periodic.conf.local to the absolute path
of your processing script:

    daily_zfs_snapshots_backup_postprocessing="/usr/local/sbin/zfs-snapshots-processing.sh"

The example processing script:
1. Generates a random encryption key
2. Encrypts the backup stream with the generated key (AES-256-OFB)
3. Generates an HMAC for the encrypted backup file (SHA512)
4. Encrypts the random key with a RSA public key
5. Packs the encrypted backup, the HMAC and the encrypted key in a tarball
6. Creates a parity2 checksum for the tarball with 3% redundancy
7. Uploads the tarball and the parity2 data to an FTP
8. Cleans up the local files if the upload was successful

This processing script needs to be adjusted for your environment. Maybe
you have SFTP or rsync over SSH available. Maybe you do not need to push
your backups since they are collected? Maybe you do not want to encrypt
your backup (why?!).

Enable storage cleanup
======================

In addition to the snapshot cleanup script, zfs-snapshots can be
configured to trigger a secondary script to cleanup your backup storage.
You can configure this by setting the following two options in
periodic.conf.local:

    daily_zfs_snapshots_cleanup_clear_storage="YES"
    Enable or disable the storage cleanup script.

    daily_zfs_snapshots_cleanup_script_storage="/usr/local/sbin/zfs-snapshots-tidy.pl"
    Absolute path to your storage cleanup script. This too needs to
    implement a `-d $days` command line option if you want to replace it
    with a script for your environment.

The example cleanup script:
1. Retrieves a list of all files on the FTP
2. Marks all backup files that were created in the current period of validity
3. Marks all backup files that are referenced by a valid incremental
   backup
4. Deletes all unmarked backups

The FTP path must only contain files uploaded by the example processing
script. In the best case scenario, all unrecognized files are only
deleted...

Configure the example processing script
=======================================

1. Setup your /root/.netrc so it can be used by curl to FTP upload
   the backups
2. Specify your RSA public key in line 40 of the script. See the README
   in usr/local/libdata/zfs-snapshots/ for information how to create a
   RSA keypair with openssl's commandline tools.
3. Specify the FQDN of the FTP server in line 41 of the script
4. Specify the path where the encryption keys should be generated in
   line 42 of the script
5. Remove the exit statement in line 44 of the script
6. Ensure the following commands are available on your system: openssl,
   tar, curl, par2

For the path where the encryption keys are generated, you can use a
small tempfs.

Configure the example storage cleanup script
============================================

1. Add username, passwort and FQDN information for the FTP to the script
   in lines 64-66.
2. Check that all required Perl modules are available on the system. You
   can check this by using:
   `perl -c /usr/local/sbin/zfs-snapshots-tidy.pl` 

Additional information
======================
This software is released under a 2-clause BSD license.
Use at your own risk. Slippery when wet.
