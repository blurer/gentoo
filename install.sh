#!/bin/bash
set -e

source funcs.sh

log_msg INFO "Welcome to the simple Gentoo installer script!"
log_msg INFO "$(cat <<-END
This script assumes the following things:
  - networking works
  - gpt & uefi
  - ext4 filesystems
  - openrc
END
)"

#
# initial install
#

# make sure all scripts are executable
chmod +x *.sh

# configure installer
export CFG_BLOCK_DEVICE="$(prompt_value "Target block device handle" "")"
export CFG_PART_PREFIX="$(prompt_value "Partition number prefix (eg. 'p' for NVMe, '' for HDD/SSD)" "")"
export CFG_BLOCK_PART="${CFG_BLOCK_DEVICE}${CFG_PART_PREFIX}"
export CFG_PART_BOOT_SIZE="$(prompt_value "Boot partition size (in MB)" "256")"
export CFG_PART_SWAP_SIZE="$(prompt_value "Swap partition size (in MB)" "4096")"
export CFG_PART_ROOT_SIZE="$(prompt_value "Root partition size (in %)" "100")%"
export CFG_TIMEZONE="$(prompt_value "System timezone" "Europe/Helsinki")"
export CFG_LOCALE="$(prompt_value "System locale" "fi_FI")"
export CFG_HOSTNAME="$(prompt_value "System hostname" "gentoo")"
export CFG_NETWORK_INTERFACE="$(prompt_value "Network interface name" "enp0s3")"
export CFG_KEYMAP="$(prompt_value "Keymap to use" "fi")"
export CFG_ROOT_PASSWORD="$(prompt_value "Root user password" "")"

log_msg INFO "$(cat <<END
Verify configuration:
  - CFG_BLOCK_DEVICE:       $CFG_BLOCK_DEVICE
  - CFG_PART_PREFIX:        $CFG_PART_PREFIX
  - CFG_BLOCK_PART:         $CFG_BLOCK_PART
  - CFG_PART_BOOT_SIZE:     $CFG_PART_BOOT_SIZE
  - CFG_PART_SWAP_SIZE:     $CFG_PART_SWAP_SIZE
  - CFG_PART_ROOT_SIZE:     $CFG_PART_ROOT_SIZE
  - CFG_TIMEZONE:           $CFG_TIMEZONE
  - CFG_LOCALE:             $CFG_LOCALE
  - CFG_HOSTNAME:           $CFG_HOSTNAME
  - CFG_NETWORK_INTERFACE:  $CFG_NETWORK_INTERFACE
  - CFG_KEYMAP:             $CFG_KEYMAP
END
)"

PROMPT_PROCEED=$(prompt_accept "Verify that the above info is correct and proceed at your own risk")
if [[ "$PROMPT_PROCEED" == "n" ]]; then
  log_msg WARN "Exiting installer safely, nothing was done..."
  exit 0
fi

# wipe old fs
PROMPT_WIPEFS=$(prompt_accept "Wipe all from target filesystem")
if [[ "$PROMPT_WIPEFS" == "y" ]]; then
  log_msg WARN "Executing 'wipefs -a $CFG_BLOCK_DEVICE' ..."
  wipefs -a $CFG_BLOCK_DEVICE
fi

# setup disklabel
parted -a optimal $CFG_BLOCK_DEVICE mklabel gpt

# setup partitions
parted -s $CFG_BLOCK_DEVICE mkpart primary 0% $CFG_PART_BOOT_SIZE
parted -s $CFG_BLOCK_DEVICE mkpart primary $CFG_PART_BOOT_SIZE $CFG_PART_SWAP_SIZE
parted -s $CFG_BLOCK_DEVICE mkpart primary $(($CFG_PART_BOOT_SIZE+$CFG_PART_SWAP_SIZE)) $CFG_PART_ROOT_SIZE
parted -s $CFG_BLOCK_DEVICE print

# setup filesystems
mkfs.fat -F 32 ${CFG_BLOCK_PART}1
mkswap ${CFG_BLOCK_PART}2
mkfs.ext4 ${CFG_BLOCK_PART}3

# activate swap partition
swapon ${CFG_BLOCK_PART}2

# mount root parition
mkdir -p /mnt/gentoo
mount ${CFG_BLOCK_PART}3 /mnt/gentoo

# execute stage3 install
cp stage3.sh /mnt/gentoo/
cp funcs.sh /mnt/gentoo/
(cd /mnt/gentoo ; bash stage3.sh)

# finalize installation
umount -l /mnt/gentoo/dev{/shm,/pts,} 
umount -R /mnt/gentoo

log_msg INFO "All is done! You can execute 'reboot' now!"
