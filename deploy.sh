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
# /dev/sda5    Linux ESP                         50MiB
# /dev/sda6    Linux Boot                        200MiB
# /dev/sda6    Linux Swap                        8GiB
# /dev/sda7    Linux Root                        Remaining space

# partitioning
if [ -z $EFI_PARTITION ]; then EFI_PARTITION="/dev/sda5"; fi
if [ -z $BOOT_PARTITION ]; then BOOT_PARTITION="/dev/sda6"; fi
if [ -z $SWAP_PARTITION ]; then SWAP_PARTITION="/dev/sda7"; fi
if [ -z $ROOT_PARTITION ]; then ROOT_PARTITION="/dev/sda8"; fi

# system configuration
if [ -z $LOCALTIME ]; then LOCALTIME="Europe/Rome"; fi
if [ -z $LANGUAGE ]; then LANGUAGE="en_US"; fi
if [ -z $ROOT_PASSWORD ]; then echo "Root password not set, exiting..."; exit 1; fi
if [ -z $USER_NAME ]; then USER_NAME="manuel"; fi
if [ -z $USER_PASSWORD ]; then USER_PASSWORD=$ROOT_PASSWORD; fi

# packages to install
if [ -z $PRESET ]; then PRESET="desktop"; fi                         # desktop or laptop
if [ -z $DESKTOP_ENVIRONMENT ]; then DESKTOP_ENVIRONMENT="gnome"; fi # gnome or kde
if [ -z $INSTALL_FIREFOX ]; then INSTALL_FIREFOX=false; fi           # installs firefox
if [ -z $INSTALL_CHROME ]; then INSTALL_CHROME=false; fi             # installs google-chrome (aur)
if [ -z $INSTALL_CHROMIUM ]; then INSTALL_CHROMIUM=false; fi         # installs chromium-vaapi-bin (aur), chromium-widevine (aur) and libva-vdpau-driver-chromium (aur)
if [ -z $INSTALL_BRAVE ]; then INSTALL_BRAVE=true; fi                # installs brave-bin (aur)
if [ -z $INSTALL_CODE ]; then INSTALL_CODE=true; fi                  # installs code (visual studio code OSS build) and ttf-fira-code

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
grub \
efibootmgr \
"

case $PRESET in
	desktop) MY_HOSTNAME="mq-desktop"; TO_INSTALL="$TO_INSTALL nvidia vdpauinfo";;
	laptop)  MY_HOSTNAME="mq-laptop"; TO_INSTALL="$TO_INSTALL wpa_supplicant intel-media-driver";;
	*)       MY_HOSTNAME="mq-box";;
esac

if $INSTALL_CODE; then
	TO_INSTALL="$TO_INSTALL code ttf-fira-code"
fi

case $DESKTOP_ENVIRONMENT in
	gnome) TO_INSTALL="$TO_INSTALL gnome gnome-tweaks tilix python-nautilus --ignore=gnome-terminal,totem";;
	kde) TO_INSTALL="$TO_INSTALL plasma plasma-wayland-session kde-applications";;
esac

# PRE-INSTALLATION
# ================

# update the system clock
timedatectl set-ntp true

# format the partitions
mkfs.vfat -F 32 $EFI_PARTITION
mkfs.ext4 -F $BOOT_PARTITION
mkfs.f2fs -f $ROOT_PARTITION
mkswap -f $SWAP_PARTITION
swapon $SWAP_PARTITION

# mount the file systems
mount $ROOT_PARTITION /mnt
mkdir /mnt/boot
mount $BOOT_PARTITION /mnt/boot
mkdir /mnt/efi
mount $EFI_PARTITION /mnt/efi

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
INSTALL_FIREFOX=$INSTALL_FIREFOX
INSTALL_CHROME=$INSTALL_CHROME
INSTALL_CHROMIUM=$INSTALL_CHROMIUM
INSTALL_BRAVE=$INSTALL_BRAVE
INSTALL_CODE=$INSTALL_CODE

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

# install the web browser(s)

if \$INSTALL_FIREFOX; then
	pacman -S --noconfirm firefox
fi

if \$INSTALL_CHROME; then
	aur-install google-chrome
fi

if \$INSTALL_CHROMIUM; then
	# install chromium-vaapi-bin and widevine (required for DRM apps ex. Netflix)
	su - $USER_NAME -c "gpg --recv-keys EB4F9E5A60D32232BB52150C12C87A28FEAC6B20" && \
	aur-install chromium-vaapi-bin && \
	aur-install chromium-widevine
fi

if \$INSTALL_BRAVE; then
	aur-install brave-bin
	echo "kernel.unprivileged_userns_clone = 1" > /etc/sysctl.d/00-local-userns.conf
fi

# configure vaapi and vdpau
case \$PRESET in
	desktop)
		if \$INSTALL_CHROMIUM; then
			aur-install libva-vdpau-driver-chromium
		else
			pacman -S --noconfirm libva-vdpau-driver
		fi
		echo "LIBVA_DRIVER_NAME=vdpau\\\nVDPAU_DRIVER=nvidia" >> /etc/environment
	;;
	laptop)
		echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
	;;
esac

# add the user's dotfiles
su - $USER_NAME -c " \
	git clone https://github.com/mquarneti/dotfiles.git ~/.dotfiles && \
	chmod +x ~/.dotfiles/install.sh && \
	PRESET=$PRESET INSTALL_CHROMIUM=$INSTALL_CHROMIUM INSTALL_CODE=$INSTALL_CODE ~/.dotfiles/install.sh \
"

# enable display manager service
case $DESKTOP_ENVIRONMENT in
	gnome) systemctl enable gdm.service;;
	kde)   systemctl enable sddm.service;;
esac

# enable networkmanager and bluetooth services
systemctl enable NetworkManager.service
systemctl enable bluetooth.service

# install grub
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

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
