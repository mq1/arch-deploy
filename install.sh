#!/bin/bash

# INSTALLATION PARAMETERS
# =======================

EFI_PARTITION="/dev/sda5"
BOOT_PARTITION="/dev/sda6"
SWAP_PARTITION="/dev/sda7"
ROOT_PARTITION="/dev/sda8"
LOCALTIME="Europe/Rome"
LANGUAGE="en_US"
ROOT_PASSWORD="secret"
USER_NAME="manuel"
USER_PASSWORD=$ROOT_PASSWORD
PRESET="desktop" # desktop or laptop

TO_INSTALL_COMMON=" \
sudo \
gnome-shell \
gdm \
networkmanager \
nautilus \
file-roller \
gnome-control-center \
xdg-user-dirs-gtk \
gnome-backgrounds \
gnome-software \
gnome-keyring \
gnome-system-monitor \
gnome-screenshot \
gvfs-mtp \
gvfs-nfs \
gvfs-smb \
mousetweaks \
tilix \
gnome-tweaks \
python-nautilus \
openssh \
git \
zsh \
zsh-autosuggestions \
zsh-completions \
zsh-history-substring-search \
zsh-syntax-highlighting \
zsh-theme-powerlevel9k \
ttf-hack \
bat \
neovim \
flatpak \
noto-fonts \
noto-fonts-cjk \
noto-fonts-emoji \
chromium \
mpv \
youtube-dl \
ntfs-3g \
libva-utils \
grub \
efibootmgr \
intel-ucode"

case $PRESET in
    desktop) MY_HOSTNAME="mq-desktop"; TO_INSTALL="nvidia vdpauinfo";;
    laptop)  MY_HOSTNAME="mq-laptop"; TO_INSTALL="wpa_supplicant dialog intel-media-driver networkmanager-openvpn";;
    *)       MY_HOSTNAME="mq-box";;
esac

# PRE-INSTALLATION
# ================

# update the system clock
timedatectl set-ntp true

# format the partitions
mkfs.vfat $EFI_PARTITION
mkfs.ext4 -F $BOOT_PARTITION
mkfs.f2fs -f $ROOT_PARTITION
mkswap -f $SWAP_PARTITION
swapon $SWAP_PARTITION

# mount the file systems
mount $ROOT_PARTITION /mnt
mkdir /mnt/boot
mount $BOOT_PARTITION /mnt/boot
mkdir /mnt/boot/efi
mount $EFI_PARTITION /mnt/boot/efi

# INSTALLATION
# ============

# install the base packages and f2fs-tools
pacstrap /mnt base f2fs-tools

# CONFIGURE THE SYSTEM
# ====================

# generate the fstab file
genfstab -U /mnt >> /mnt/etc/fstab

# write the second part to be executed inside the chroot
cat <<EOF > /mnt/part2.sh
#!/bin/bash

PRESET=$PRESET

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

# install some packages
pacman -S --noconfirm $TO_INSTALL_COMMON $TO_INSTALL

# create the user
useradd -m -s /usr/bin/zsh -G wheel $USER_NAME

# set the user password
echo "$USER_NAME:$USER_PASSWORD" | chpasswd

# add the wheel group (without password) to the sudoers file
echo "%wheel ALL=(ALL) NOPASSWD: ALL" | EDITOR='tee -a' visudo

# prepare for installing packages from AUR
pacman -S --noconfirm --needed base-devel
cd /home/$USER_NAME

# install https://github.com/Jguer/yay
su - $USER_NAME -c " \
    cd ~ && \
    git clone https://aur.archlinux.org/yay.git && \
    cd yay && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf yay "

# install chromium-widevine (required for Netflix)
su - $USER_NAME -c " \
    cd ~ && \
    git clone https://aur.archlinux.org/chromium-widevine.git && \
    cd chromium-widevine && \
    makepkg -si --noconfirm && \
    cd .. && \
    rm -rf chromium-widevine"

# configure vaapi
case \$PRESET in
    desktop)
        su - $USER_NAME -c " \
            cd ~ && \
            git clone https://aur.archlinux.org/libva-vdpau-driver-chromium.git && \
            cd libva-vdpau-driver-chromium && \
            makepkg -si --noconfirm && \
            cd .. && \
            rm -rf libva-vdpau-driver-chromium"
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

# enable some services
systemctl enable gdm.service
systemctl enable NetworkManager.service
systemctl enable bluetooth.service

# write the grub configuration file
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch-grub
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
