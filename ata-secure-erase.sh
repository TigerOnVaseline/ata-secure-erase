#!/usr/bin/env bash

# ata-secure-erase.sh
# Use hdparm (8) to erase an ATA disk with the SECURITY ERASE UNIT (F4h)
# command under Linux

# (C) 2015 TigerOnVaseline
# https://github.com/TigerOnVaseline/ata-secure-erase

# This code is licensed under MIT license:
# http://opensource.org/licenses/MIT

# Requires awk and hdparm
# POSIX conventions and the Shell Style Guide have been adhered to where viable
# https://google-styleguide.googlecode.com/svn/trunk/shell.xml

# References: 
# T13/1699-D, AT Attachment 8 - ATA/ATAPI Command Set (ATA8-ACS)
# http://www.t13.org/documents/UploadedDocuments/docs2007/D1699r4a-ATA8-ACS.pdf

# DISCLAIMER
# Care has been taken to thoroughly test this script using a variety of cases,
# though, as with all Linux/UNIX-like affairs, it may still fail in mysterious
# circumstances.

# In particular, ERASE UNIT may fail to erase some SSD drives:
# M. Wei, L. M. Grupp, F. M. Spada, and S. Swanson, 'Reliably Erasing Data 
# from Flash-Based Solid State Drives'
# https://www.usenix.org/legacy/event/fast11/tech/full_papers/Wei.pdf

if [ "$EUID" -ne  "0" ]; then
	echo >&2 "Error: This script must be run as root or with sudo (8)"
	exit 1
fi 

# POSIX-compliant method for checking a command available 
if [ $(type hdparm >/dev/null 2>&1) ]; then
	echo >&2 "Error: This script requires hdparm"
	exit 1
fi

if [ $(type awk >/dev/null 2>&1) ]; then
	echo >&2 "Error: This script requires awk"
	exit 1
fi

if [ -z "$1" ]; then
	echo >&2 "Usage:" 
	echo >&2 "$0 [-f] device"
	echo >&2 "$0 -l "
	echo >&2 "Erase a disk with the ATA SECURITY ERASE UNIT command"
	echo >&2 "	 -f 	Don't prompt before erasing"
	echo >&2 "	 -l 	List disks"
	exit 1
fi

if [ "$1" == "-l" ]; then
	echo "Available disks for secure erase are:"
	# Use the most portable method for finding available ATA disks, anything 
	# found by udev should end in a letter
	for disk in $(awk '/[0-9].*[a-z]$/ {print $4}' /proc/partitions); do
		# hdparm output should match "Security:"  with "Master" on the 
		# following line if SECURITY ERASE UNIT is supported (NR+1). Command 
		# output  must be quoted for bash to handle metachars properly
		if [ "$(hdparm -I /dev/${disk} 2>&1| awk '/Security:/{n=NR+1} NR==n { print $1 }')" == "Master" ]; then
			echo /dev/${disk}
		fi
	done
exit 0
fi

if [ "$1" == "-f" ]; then
	force=true
	ata_disk=$2
else
	ata_disk=$1
fi

# Check the specifed device exists and is a block device
if [ ! -b ${ata_disk} ]; then 
	echo >&2 "Error: No such block device ${ata_disk}"
	exit 1 
fi

if [ "$(hdparm -I ${ata_disk} 2>&1| awk '/Security:/{n=NR+1} NR==n { print $1 }')" != "Master" ]; then 
	echo >&2 "Error: ATA SECURITY ERASE UNIT unsupported on ${ata_disk}"
	exit 1 
fi

# Check for frozen state
if [ "$(hdparm -I ${ata_disk} 2>&1| awk '/frozen/ { print $1 }')" != "not" ]; then
	echo >&2 "Error: Disk ${ata_disk} security state is frozen, check https://ata.wiki.kernel.org/index.php/ATA_Secure_Erase for possible solutions"
	exit 1
fi

if [ $force ]; then
user_choice='Y'
else
	echo "WARNING: this procedure will erase all data on ${ata_disk} beyond recovery." 
	echo "Continue [Y/N]?"
	read user_choice
fi

disk_password="123456"

if [ "${user_choice}" == "Y" ]; then
	echo "Attempting to set user password and enable secure erase..."
	hdparm --user-master u --security-set-pass ${disk_password} ${ata_disk} >/dev/null 2>&1
else
	echo "Secure erase operation cancelled"
	exit 0
fi

# If the user password was set, string value "not" should be absent from the 
# third line after matching "Security:"
if [ "$(hdparm -I ${ata_disk} | awk '/Security:/{n=NR+3} NR==n { print $1 }')" == "not" ]; then
	echo >&2 "Error setting user password on ${ata_disk}, check with hdparm -I ${ata_disk} to ensure ${ata_disk} is still in a usable state"
	echo >&2 "The user password is ${disk_password}. If present, it should be removed with:"
	echo >&2 "hdparm --user-master u --security-unlock ${disk_password} ${ata_disk}"
	exit 1
else
	echo "User password set, attempting secure erase for ${ata_disk}";
	# Estimate the time required to complete the erasure
	hdparm -I ${ata_disk} | awk '/for SECURITY ERASE UNIT/'
	# Run the erase command
	hdparm --user-master u --security-erase ${disk_password} ${ata_disk} >/dev/null 2>&1
	# Sucessful erase should reset "enabled" value to "not"
	if [ "$(hdparm -I ${ata_disk} | awk '/Security:/{n=NR+3} NR==n { print $1 }')" == "not" ]; then
		echo "Secure erase was successful for ${ata_disk}";
		exit 0
	else
		echo >&2 "Error performing secure erase on ${ata_disk}"
		exit 1
	fi;
fi
