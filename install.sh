#!/bin/bash

# define the partitions
EFI_PARTITION="/dev/sda5"
BOOT_PARTITION="/dev/sda6"
SWAP_PARTITION="/dev/sda7"
ROOT_PARTITION="/dev/sda8"

MY_HOSTNAME="mq-desktop"

MY_PASSWORD="secret"

timedatectl set-ntp true

# format the partitions
mkfs.vfat $EFI_PARTITION
mkfs.ext4 $BOOT_PARTITION
mkswap $SWAP_PARTITION
mkfs.ext4 $ROOT_PARTITION

swapon $SWAP_PARTITION

# mount the partitions
mount $ROOT_PARTITION /mnt
mkdir /mnt/boot
mount $BOOT_PARTITION /mnt/boot
mkdir /mnt/boot/efi
mount $EFI_PARTITION /mnt/boot/efi

pacstrap /mnt base

genfstab -U /mnt >> /mnt/etc/fstab

# write the second part to be executed inside the chroot
cat <<EOF > /mnt/part2.sh
#!/bin/bash
ln -sf /usr/share/zoneinfo/Europe/Rome /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$MY_HOSTNAME" > /etc/hostname
echo "127.0.0.1 localhost" >> /etc/hosts
echo "::1 localhost" >> /etc/hosts
echo "127.0.1.1 $MY_HOSTNAME.localdomain $MY_HOSTNAME" >> /etc/hosts
echo "root:$MY_PASSWORD" | chpasswd
pacman -S --noconfirm grub efibootmgr intel-ucode
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=arch-grub
grub-mkconfig -o /boot/grub/grub.cfg
exit # leave the chroot
EOF

chmod +x /mnt/part2.sh

arch-chroot /mnt /part2.sh

rm /mnt/part2.sh

umount -R /mnt

echo "installation complete"
