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
USER_EMAIL="manuelquarneti@protonmail.com"
PRESET="desktop" # desktop or laptop

TO_INSTALL_COMMON=" \
sudo \
gnome-shell \
gdm \
networkmanager \
nautilus \
file-roller \
tilix \
gnome-control-center \
gnome-tweaks \
python-nautilus \
xdg-user-dirs-gtk \
openssh \
git \
zsh \
flatpak \
gnome-software \
noto-fonts \
noto-fonts-cjk \
noto-fonts-emoji \
youtube-dl \
ntfs-3g \
gvfs-mtp \
libva-utils \
grub \
efibootmgr \
intel-ucode \
os-prober"

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

# install oh-my-zsh without entering zsh
su - $USER_NAME -c "cd ~ && sh -c \$(curl -fsSL https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh | sed 's:env zsh -l::g' | sed 's:chsh -s .*$::g')"

# source vte.sh in zshrc (for tilix) and add an update function
cat <<EOSF >> /home/$USER_NAME/.zshrc
if [ \\\$TILIX_ID ] || [ \\\$VTE_VERSION ]; then
    source /etc/profile.d/vte.sh
fi

function up {
    yay
    flatpak update
}
EOSF

# prepare for installing packages from AUR
pacman -S --noconfirm --needed base-devel
cd /home/$USER_NAME

# install https://github.com/Jguer/yay
git clone https://aur.archlinux.org/yay.git
su - $USER_NAME -c "cd ~/yay && makepkg -si --noconfirm"
rm -rf yay

# install chromium-vaapi
echo '[maximbaz]' >> /etc/pacman.conf
echo 'Server = https://pkgbuild.com/~maximbaz/repo/' >> /etc/pacman.conf

# enable hardware acceleration on chromium-vaapi
cat <<EOSF > .config/chromium-flags.conf
--enable-accelerated-video
--enable-accelerated-mjpeg-decode
--disable-gpu-driver-bug-workarounds
--ignore-gpu-blacklist
--enable-gpu-rasterization
--enable-zero-copy
--enable-native-gpu-memory-buffers
EOSF
chown $USER_NAME .config/chromium-flags.conf

# install chromium-widevine (required for Netflix)
git clone https://aur.archlinux.org/chromium-widevine.git
su - $USER_NAME -c "cd ~/chromium-widevine && makepkg -si --noconfirm"
rm -rf chromium-widevine

# configure vaapi
case \$PRESET in
    desktop)
        git clone https://aur.archlinux.org/libva-vdpau-driver-chromium.git
        su - $USER_NAME -c "cd ~/libva-vdpau-driver-chromium && makepkg -si --noconfirm"
        rm -rf libva-vdpau-driver-chromium
        echo "LIBVA_DRIVER_NAME=vdpau" >> /etc/environment
        echo "VDPAU_DRIVER=nvidia" >> /etc/environment
    ;;
    laptop)
        echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
    ;;
esac

# generate a ED25519 SSH key pair
su - $USER_NAME -c 'ssh-keygen -t ed25519 -C "$USER_EMAIL"'

# install some flatpak apps
flatpak install -y \
    org.gnome.eog \
    org.gnome.gedit \
    de.haeckerfelix.Fragments \
    io.github.GnomeMpv \

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
