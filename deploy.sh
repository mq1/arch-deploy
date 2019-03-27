#!/bin/bash

# INSTALLATION PARAMETERS
# =======================

# SUGGESTED PARTITION SCHEME
# ==========================
# DEVICE       PARTITION                         SIZE
# /dev/sda1    Windows Recovery Environment      500MiB
# /dev/sda2    Windows ESP                       100MiB
# /dev/sda3    Microsoft Reserved Partition      16MiB
# /dev/sda4    Microsoft basic data partition    Arbitrary
# /dev/sda5    Linux ESP                         512MiB
# /dev/sda6    Linux Swap                        8GiB
# /dev/sda7    Linux Root                        Remaining space

# partitioning
LINUX_ESP="/dev/sda5" # efi system partition
SWAP_PARTITION="/dev/sda6"
ROOT_PARTITION="/dev/sda7"
WINDOWS_ESP="/dev/sda2"

# system configuration
LOCALTIME="Europe/Rome"
LANGUAGE="en_US"
ROOT_PASSWORD="secret"
USER_NAME="manuel"
USER_PASSWORD=$ROOT_PASSWORD

# packages to install
PRESET="desktop"            # desktop or laptop
DESKTOP_ENVIRONMENT="gnome" # gnome or kde

TO_INSTALL=" \
base \
base-devel \
f2fs-tools \
sudo \
networkmanager \
openssh \
git \
zsh \
zsh-autosuggestions \
zsh-completions \
zsh-history-substring-search \
zsh-syntax-highlighting \
zsh-theme-powerlevel9k \
bat \
lsd \
neovim \
xclip \
flatpak \
noto-fonts \
noto-fonts-cjk \
noto-fonts-emoji \
mpv \
youtube-dl \
ntfs-3g \
libva-utils \
intel-ucode \
"

case $PRESET in
	desktop) MY_HOSTNAME="mq-desktop"; TO_INSTALL="$TO_INSTALL nvidia vdpauinfo";;
	laptop)  MY_HOSTNAME="mq-laptop"; TO_INSTALL="$TO_INSTALL wpa_supplicant intel-media-driver";;
	*)       MY_HOSTNAME="mq-box";;
esac

case $DESKTOP_ENVIRONMENT in
	gnome) TO_INSTALL="$TO_INSTALL gnome gnome-tweaks fragments";;
	kde) TO_INSTALL="$TO_INSTALL plasma plasma-wayland-session kde-applications qbittorrent";;
esac

# PRE-INSTALLATION
# ================

# update the system clock
timedatectl set-ntp true

# format the partitions
mkfs.vfat -F32 $LINUX_ESP
mkfs.f2fs -f $ROOT_PARTITION
mkswap -f $SWAP_PARTITION
swapon $SWAP_PARTITION

# mount the file systems
mount $ROOT_PARTITION /mnt
mkdir /mnt/boot
mount $LINUX_ESP /mnt/boot

# copy the windows boot loader from $WINDOWS_ESP to $LINUX_ESP
mkdir /mnt/boot/windows
mount $WINDOWS_ESP /mnt/boot/windows
cp -r /mnt/boot/windows/* /mnt/boot
umount $WINDOWS_ESP
rmdir /mnt/boot/windows

# INSTALLATION
# ============

# install the packages
pacstrap /mnt $TO_INSTALL

# CONFIGURE THE SYSTEM
# ====================

# generate the fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# write the second part to be executed inside the chroot
cat <<EOF > /mnt/part2.sh
#!/bin/bash

aur-install() {
	su - $USER_NAME -c " \
		cd ~ && \
		git clone https://aur.archlinux.org/\$1.git && \
		cd \$1 && \
		makepkg -sirc --noconfirm && \
		cd .. && \
		rm -rf \$1 \
	"
}

PRESET=$PRESET
DESKTOP_ENVIRONMENT=$DESKTOP_ENVIRONMENT

# set the time zone
ln -sf /usr/share/zoneinfo/$LOCALTIME /etc/localtime

# run hwclock to generate /etc/adjtime
hwclock --systohc

# uncomment $LANGUAGE.UTF-8 UTF-8 in /etc/locale.gen
sed -i "s/#$LANGUAGE.UTF-8 UTF-8/$LANGUAGE.UTF-8 UTF-8/g" /etc/locale.gen

# generate the locale
locale-gen

# set the LANG variable in locale.conf
echo "LANG=$LANGUAGE.UTF-8" > /etc/locale.conf

# create the hostname file
echo "$MY_HOSTNAME" > /etc/hostname

# add matching entries to hosts
cat <<EOSF >> /etc/hosts
127.0.0.1 localhost
::1 localhost
127.0.1.1 $MY_HOSTNAME.localdomain $MY_HOSTNAME
EOSF

# set the root password
echo "root:$ROOT_PASSWORD" | chpasswd

# MY STUFF
# ========

# create the user
useradd -m -s /usr/bin/zsh -G wheel $USER_NAME

# set the user password
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# add the wheel group (without password) to the sudoers file
echo "%wheel ALL=(ALL) NOPASSWD: ALL" | EDITOR='tee -a' visudo

# install https://github.com/Jguer/yay
aur-install yay-bin

# install chromium-vaapi-bin
su - $USER_NAME -c "gpg --recv-keys EB4F9E5A60D32232BB52150C12C87A28FEAC6B20"
aur-install chromium-vaapi-bin

# install chromium-widevine (required for Netflix)
aur-install chromium-widevine

# configure vaapi
case \$PRESET in
	desktop)
		aur-install libva-vdpau-driver-chromium
		echo "LIBVA_DRIVER_NAME=vdpau" >> /etc/environment
		echo "VDPAU_DRIVER=nvidia" >> /etc/environment
	;;
	laptop)
		echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
	;;
esac

# add the user's dotfiles
su - $USER_NAME -c " \
	git clone https://github.com/mquarneti/dotfiles.git ~/.dotfiles && \
	chmod +x ~/.dotfiles/install.sh && \
	~/.dotfiles/install.sh
"

# enable display manager service
case $DESKTOP_ENVIRONMENT in
	gnome) systemctl enable gdm.service;;
	kde) systemctl enable sddm.service;;
esac

# enable networkmanager and bluetooth services
systemctl enable NetworkManager.service
systemctl enable bluetooth.service

# install systemd-boot
bootctl --path=/boot install

# automatic systemd-boot update with pacman hook
mkdir -p /etc/pacman.d/hooks
cat <<EOSF > /etc/pacman.d/hooks/100-systemd-boot.hook
[Trigger]
Type = Package
Operation = Upgrade
Target = systemd

[Action]
Description = Updating systemd-boot
When = PostTransaction
Exec = /usr/bin/bootctl update
EOSF

# configure systemd-boot
mkdir -p /boot/loader
cat <<EOSF > /boot/loader/loader.conf
default arch
timeout 5
console-mode max
EOSF

# add an entry for Arch to systemd-boot
mkdir -p /boot/loader/entries
cat <<EOSF > /boot/loader/entries/arch.conf
title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=$ROOT_PARTITION rw
EOSF

# leave the chroot
exit
EOF

# make part2.sh executable
chmod +x /mnt/part2.sh

# execute part2.sh as chroot
arch-chroot /mnt /part2.sh

# remove part2.sh
rm /mnt/part2.sh

# umount all the partitions
umount -R /mnt

echo "installation complete"
