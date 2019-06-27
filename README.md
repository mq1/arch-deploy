## DEPRECATED

I'm now working on [ali](https://github.com/mquarneti/ali) (Arch Linux Installer)

# My script for installing arch

It is intended to work (sometimes) on my desktop and my laptop, feel free to look around

## Usage:

From archiso:

```sh
curl -sSL https://git.io/fjtwW | bash - \
    --efi-partition=/dev/sda5 --boot-partition=/dev/sda6 --swap-partition=/dev/sda7 --root-partition=/dev/sda8 \
    --hostname=mq-desktop --localtime=Europe/Rome --language=en_US --root-password=password --user-name=manuel \
	--nvidia --install-gnome --install-brave --install-vscodium
```
