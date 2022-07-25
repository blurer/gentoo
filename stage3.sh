#!/bin/bash
set -e

source funcs.sh

#
# stage3 install
#

# sync time
ntpd -q -g

# download & unpack stage3 tarball
links https://www.gentoo.org/downloads/mirrors/
LINKS_RUNNING="true"
while [[ $LINKS_RUNNING == "true" ]]; do
  log_msg INFO "Waiting for user to quit links ..."
  LINKS_RUNNING=$(ps -aux | (grep -o '[l]inks') || true)
  sleep 1s
done
tar xpvf stage3-*.tar.xz --xattrs-include="*.*" --numeric-owner
rm stage3-*.tar.xz

# configure portage (COMMON/USE)
PROMPT_PORTAGE=$(prompt_accept "Configure /etc/portage/make.conf COMMON/USE/MAKE/etc flags")
if [[ "$PROMPT_PORTAGE" == "y" ]]; then
  nano -w ./etc/portage/make.conf
fi

# make sure DNS works after chroot
cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

# mount filesystems
mount --types proc /proc /mnt/gentoo/proc
mount --rbind /sys /mnt/gentoo/sys
mount --make-rslave /mnt/gentoo/sys
mount --rbind /dev /mnt/gentoo/dev
mount --make-rslave /mnt/gentoo/dev
mount --bind /run /mnt/gentoo/run
mount --make-slave /mnt/gentoo/run 

# change root!
chroot /mnt/gentoo /bin/bash << EOF
set -e

source funcs.sh
source /etc/profile
export PS1="(chroot) ${PS1}"

log_msg INFO "mount boot partition" >> /var/log/installer.log
mkdir -p /boot/efi
mount ${CFG_BLOCK_PART}1 /boot/efi

log_msg INFO "synchronize gentoo ebuild repo" >> /var/log/installer.log
emerge --ask n --sync

# TODO: select profile

log_msg INFO "update @world set (@system and @selected)" >> /var/log/installer.log
emerge --ask n --update --deep --newuse @world

log_msg INFO "configure licenses" >> /var/log/installer.log
echo "ACCEPT_LICENSE=\"-* @FREE\"" >> /etc/portage/make.conf
echo "sys-kernel/linux-firmware @BINARY-REDISTRIBUTABLE" >> /etc/portage/package.license

log_msg INFO "configure timezone" >> /var/log/installer.log
echo $CFG_TIMEZONE > /etc/timezone
emerge --ask n --config sys-libs/timezone-data

log_msg INFO "configure locales" >> /var/log/installer.log
echo "fi_FI.UTF-8 UTF-8" >> /etc/locale.gen
echo "fi_FI ISO-8859-1" >> /etc/locale.gen
echo "en_GB.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
eselect locale list
eselect locale set 7

log_msg INFO "reload environment" >> /var/log/installer.log
env-update && source /etc/profile && export PS1="(chroot) ${PS1}"

#
# firmware install
#

#
# kernel install
#

log_msg INFO "install kernel sources" >> /var/log/installer.log
emerge --ask n sys-kernel/gentoo-sources

log_msg INFO "select kernel sources" >> /var/log/installer.log
eselect kernel list
eselect kernel set 1

log_msg INFO "install genkernel & set /boot/efi in fstab" >> /var/log/installer.log
emerge --ask n sys-kernel/genkernel
echo "${CFG_BLOCK_PART}1 /boot/efi vfat defaults 0 2" >> /etc/fstab

log_msg INFO "compile kernel sources" >> /var/log/installer.log
genkernel all

#
# filesystem install
#

log_msg INFO "set swap, / and cdrom in fstab" >> /var/log/installer.log
mkdir -p /mnt/cdrom
echo "${CFG_BLOCK_PART}"2 none swap sw 0 0 >> /etc/fstab
echo "${CFG_BLOCK_PART}"3 / ext4 noatime 0 1 >> /etc/fstab
echo /dev/cdrom /mnt/cdrom auto noauto,user 0 0 >> /etc/fstab

#
# networking install
#

log_msg INFO "set hostname" >> /var/log/installer.log
echo "hostname=\"${CFG_HOSTNAME}\"" > /etc/conf.d/hostname

log_msg INFO "install netifrc" >> /var/log/installer.log
emerge --ask n --noreplace net-misc/netifrc

log_msg INFO "install dhcpcd" >> /var/log/installer.log
emerge --ask n net-misc/dhcpcd

log_msg INFO "install wireless" >> /var/log/installer.log
emerge --ask n net-wireless/iw net-wireless/wpa_supplicant

log_msg INFO "configure networking" >> /var/log/installer.log
echo "config_${CFG_NETWORK_INTERFACE}=\"dhcp\"" >> /etc/conf.d/net
ln -s /etc/init.d/net.lo /etc/init.d/net.${CFG_NETWORK_INTERFACE}
rc-update add net.${CFG_NETWORK_INTERFACE} default

log_msg INFO "configure hosts" >> /var/log/installer.log
echo "127.0.0.1 ${CFG_HOSTNAME} localhost" >> /etc/hosts

#
# system install
#

log_msg INFO "set root password" >> /var/log/installer.log
echo "root:${CFG_ROOT_PASSWORD}" | chpasswd

log_msg INFO "set keymap" >> /var/log/installer.log
sed -i '/^keymap/s/=.*$/=$"'"fi"'"/' /etc/conf.d/keymaps
rc-update add keymaps boot
rc-service keymaps restart

log_msg INFO "install syslog" >> /var/log/installer.log
emerge --ask n app-admin/sysklogd
rc-update add sysklogd default

log_msg INFO "install crond" >> /var/log/installer.log
emerge --ask n sys-process/cronie
rc-update add cronie default

log_msg INFO "install file indexer" >> /var/log/installer.log
emerge --ask n sys-apps/mlocate

log_msg INFO "install filesystem tools" >> /var/log/installer.log
emerge --ask n sys-fs/e2fsprogs
emerge --ask n sys-fs/dosfstools

#
# bootloader install
#

log_msg INFO "install grub2 with efi" >> /var/log/installer.log
echo "GRUB_PLATFORMS=\"efi-64\"" >> /etc/portage/make.conf
emerge --ask n sys-boot/grub

log_msg INFO "install bootloader" >> /var/log/installer.log
grub-install --target=x86_64-efi --efi-directory=/boot/efi

log_msg INFO "configure bootloader" >> /var/log/installer.log
grub-mkconfig -o /boot/grub/grub.cfg

EOF
