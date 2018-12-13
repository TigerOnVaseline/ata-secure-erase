#!/usr/bin/env bash

# ata-secure-erase.sh
# Use hdparm (8) to erase an ATA disk with the SECURITY ERASE UNIT (F4h)
# command under Linux

# (C) 2015 TigerOnVaseline
# https://github.com/TigerOnVaseline/ata-secure-erase

# This code is licensed under MIT license:
# http://opensource.org/licenses/MIT

# POSIX conventions and the Shell Style Guide have been adhered to where viable
# https://google.github.io/styleguide/shell.xml

# Linted with shellcheck: https://github.com/koalaman/shellcheck

# References: 
# T13/1699-D, AT Attachment 8 - ATA/ATAPI Command Set (ATA8-ACS)
# http://www.t13.org/documents/UploadedDocuments/docs2007/D1699r4a-ATA8-ACS.pdf

# DISCLAIMER
# Whilst care has been taken to thoroughly test this script using a variety of 
# cases, # as with all Linux/UNIX-like affairs, it may still fail in mysterious
# circumstances. In particular, ERASE UNIT may fail to erase some SSD drives:
# M. Wei, L. M. Grupp, F. M. Spada, and S. Swanson, 'Reliably Erasing Data 
# from Flash-Based Solid State Drives'
# https://www.usenix.org/legacy/event/fast11/tech/full_papers/Wei.pdf

# Read arguments and count into arrays to prevent them getting mangled
readonly SCRIPT_NAME=${0##*/}
readonly -a ARGV=("$@")
readonly ARGC=("$#")
readonly DISK_PASSWORD="123456"
readonly REQUIRED_OS="Linux"
readonly MIN_KERNEL_VERSION=20627
readonly MIN_BASH_VERSION=4
readonly REQUIRED_COMMANDS="awk grep hdparm lsblk udevadm uname"

show_usage() {
    cat <<- _EOF_ >&2

Usage:  ${SCRIPT_NAME} [-f] device | ${SCRIPT_NAME} -l
Erase a disk with the ATA SECURITY ERASE UNIT command

OPTIONS
    -f    Don't prompt before erasing (USE WITH CAUTION)
    -l    List disks

EXAMPLES
    Erase the device /dev/sda:
    ${SCRIPT_NAME} /dev/sda

_EOF_
}

list_available_disks() {
    local device
    local eligible_disk_found
    udevadm settle # Syncronise with udev first
    echo "Available disks for secure erase are:"
    for device in $(lsblk --nodeps --noheadings --output NAME --paths); do
        if is_block_device "${device}" && ata_erase_support "${device}"; then
            echo "${device}"
            eligible_disk_found=true
        fi
        if [[ ! "$eligible_disk_found" == "true" ]]; then
            echo >&2 "No supported disks found for secure erase" 
        fi
    done
}

is_block_device() {
    local file="$1"
    if [[ -b ${file} ]]; then 
        true
    else
        false
    fi
}

ata_erase_support() {
    local disk="$1"
    local master_revision_present
    local password_supported
    # hdparm output should match "Security:" with "Master" on the 
    # following line if SECURITY ERASE UNIT is supported (NR+1).
    if hdparm -I "${disk}" | grep -q '^Security:'; then
        master_revision_present=$(hdparm -I "${disk}" | awk '/Security:/{n=NR+1} NR==n { print $1 }')
        if [[ "${master_revision_present}" =~ ^Master ]]; then
            password_supported=$(hdparm -I "${disk}" | awk '/Security:/{n=NR+2} NR==n { print $1,$2 }')
            if [[ "${password_supported}" =~ ^supported ]]; then
                true
            else
                false
            fi
        else
            false
        fi
    else
        false
    fi
}

is_unfrozen() {
    local frozen_state
    frozen_state=$(hdparm -I "${ata_disk}" | awk '/frozen/ { print $1,$2 }')
    if [ "${frozen_state}" == "not frozen" ]; then
        true
    else
        false
    fi
}

set_password () {
    local ata_disk="$1"
    hdparm --user-master u --security-set-pass "${DISK_PASSWORD}" "${ata_disk}" >/dev/null
}

is_password_set () {
    local password_state
    password_state=$(hdparm -I "$1" | awk '/Security:/{n=NR+3} NR==n { print $1,$2 }')
    if [[ ${password_state} == "enabled" ]]; then
        true
    else
        false
    fi
}

estimate_erase_time () {
    local ata_disk="$1"
    hdparm -I "${ata_disk}" | awk '/for SECURITY ERASE UNIT/'
}

erase_disk() {
    local ata_disk="$1"
    hdparm --user-master u --security-erase "${DISK_PASSWORD}" "$ata_disk" >/dev/null 
}

main() {

    local system_name
    local kernel_release
    local kernel_version
    local kernel_version_numeric
    local ata_disk="$1"
    local force=false


    if [[ "${BASH_VERSINFO[0]}" -lt "${MIN_BASH_VERSION}" ]]; then
        echo >&2 "Error: This script requires bash-4.0 or higher"
        exit 1
    fi

    # Get operating system name (POSIX)
    system_name=$(uname -s)

    if [[ "${system_name}" != "${REQUIRED_OS}" ]]; then
        echo >&2 "This script can only run on Linux"
        exit 1
    fi

    kernel_release=$(uname --kernel-release)
    kernel_version=(${kernel_release//[.-]/ })
    kernel_version_numeric=$(((kernel_version[0] * 10000) + (kernel_version[1] * 100) + kernel_version[2]))

    # lsblk requires sysfs block directory (kernel 2.6.27 and above)
    if [[ ${kernel_version_numeric} -lt ${MIN_KERNEL_VERSION} ]]; then
        echo >&2 "This script requires kernel version ${MIN_KERNEL_VERSION} or higher"
    fi

    if [[ "${EUID}" -ne  "0" ]]; then
        echo >&2 "Error: This script must be run as root or with sudo (8)"
        exit 1
    fi

    # POSIX-compliant method for checking a command is available 
    local required_command
    for required_command in ${REQUIRED_COMMANDS}
    do
        if ! type "${required_command}" >/dev/null 2>&1; then
            echo >&2 "Error: This script requires ${required_command}"
            exit 1
        fi
    done

    if [[ ${ARGC[0]} -lt 1 || ${ARGC[0]} -gt 2 ]]; then
        show_usage
        exit 1
    fi

    while getopts ":f:hl" option
    do
        case "${option}" in
        l)
            list_available_disks
            exit 0
            ;;
        h)
            show_usage
            exit 0
            ;;
        f)
            force=true
            ata_disk="$2"
            ;;
        *)
            show_usage
            exit 1
            ;;
        esac
    done

    # Check the specifed device exists and is a block device
    if ! is_block_device "${ata_disk}"; then 
        echo >&2 "Error: No such block device ${ata_disk}, use ${SCRIPT_NAME} -l to list available disks"
        exit 1 
    fi

    if ! ata_erase_support "${ata_disk}"; then 
        echo >&2 "Error: ATA SECURITY ERASE UNIT unsupported on ${ata_disk}, use ${SCRIPT_NAME} -l to list available disks"
        exit 1 
    fi

    # Check for frozen state
    if ! is_unfrozen "${ata_disk}"; then
        echo >&2 "Error: Disk ${ata_disk} security state is frozen, check \
        https://ata.wiki.kernel.org/index.php/ATA_Secure_Erase for options"
        exit 1
    fi

    if [[ ! $force ]]; then
        echo "WARNING: this procedure will erase all data on ${ata_disk} beyond recovery." 
        echo -n "Continue [Y/N]?"
        read -r user_choice
    fi

    if [[ "${user_choice,,}" == "y" ]]; then
        echo "Attempting to set user password and enable secure erase..."
        set_password "${ata_disk}"
    else
        echo "Secure erase operation cancelled"
        exit 0
    fi

    if is_password_set "${ata_disk}"; then
        echo >&2 "Error setting user password on ${ata_disk}"
        exit 1
    else
        echo "User password set, attempting secure erase for ${ata_disk}";
        estimate_erase_time "${ata_disk}"
        erase_disk "${ata_disk}"
        # Sucessful erase should reset "enabled" value to "not"
        if ! is_password_set "${ata_disk}"; then
            echo "Secure erase was successful for ${ata_disk}";
            exit 0
        else
            echo >&2 "Error performing secure erase on ${ata_disk}"
            exit 1
        fi;
    fi
}

main "${ARGV[@]}" 