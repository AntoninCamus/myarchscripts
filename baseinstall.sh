#!/bin/bash

#############################################################################
#   __  __                         _      _____           _       _         #
#  |  \/  |         /\            | |    / ____|         (_)     | |        #
#  | \  / |_   _   /  \   _ __ ___| |__ | (___   ___ _ __ _ _ __ | |_ ___   #
#  | |\/| | | | | / /\ \ | '__/ __| '_ \ \___ \ / __| '__| | '_ \| __/ __|  #
#  | |  | | |_| |/ ____ \| | | (__| | | |____) | (__| |  | | |_) | |_\__ \  #
#  |_|  |_|\__, /_/    \_\_|  \___|_| |_|_____/ \___|_|  |_| .__/ \__|___/  #
#           __/ |                                          | |              #
#          |___/                                           |_|              #
#                                                                           #
# Title : Base Installer                                                    #
#                                                                           #
# Requirements : None                                                       #
#                                                                           #
# Author : Antonin Camus (github.com/antonincamus)                          #
#                                                                           #
# Description : This script isn't etheir an installer or a distribution,    #
#               but a kind of helper to help me (and you) automatize your   #
#               installation of archlinux. Feel free to clone this repo,    #
#               and to share back your modifications !                      #
#                                                                           #
# Support : At the moment, I support functionnalities I use on my main      #
#           installation : EFI, Encrypted installation, Gnome. This script  #
#           won't handle formatting of your disks BUT will handle lvm       #
#           volume configuration.                                           #
#                                                                           #
# License : This script is shared under GPL3 licence terms.                 #
#                                                                           #
#############################################################################

#############################  SCRIPT VARIABLES  ############################
# There is no need to modify thoses variables, but you can.
ERROR="[ MyArchScript - Error ] "
INFO="[ MyArchScript - Info ] "

##############################  USER VARIABLES  #############################

# Disks and part. configuration :

# Disks configuration :
# I provide 2 configuration, described on the official wiki below :
# https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system
# - no encryption : "none"
# - lvm on luks : "lvm"

# ESP : UEFI partition
UEFI_PART="/dev/sda1"
FORMAT_UEFI="false"

ENCRYPTION="none" # "none" or "lvm"

# Then you should fill your choices accordingly :
if [ "$ENCRYPTION" == "none" ]; then
    ROOT_PART="sda2" # Part. name ("sdxy")
    SWAP_PART="sda3" # Part. name ("sdxy"), "file" or "none"
elif [ "$ENCRYPTION" == "lvm" ]; then
    LVM_ENCRYPTED_PART="sda2"       # Part. name ("sdxy")
    LVM_DECRYPTED_MAPPER="cryptlvm" # Mapper name (e.g. "cryptlvm")
    VOLUME_GROUP="VolumeGroup"      # It's not necessary to change this one
    ROOT_VOLUME="root"              # LVM volume name, "file" or "none"
    ROOT_VOLUME_SIZE="51G"          # Size of Root Volume, in G
    SWAP_VOLUME="swap"              # LVM volume name, "file" or "none"
    if [ ! "$SWAP_VOLUME" = "file" ]; then
        SWAP_VOLUME_SIZE="4G"
    fi
fi

if [ "$SWAP_PART" == "file" ] || [ "$SWAP_VOLUME" == "file" ]; then
    SWAP_FILE_SIZE="4G"
fi

# Localisation configuration :

LANGUAGE_CODE="fr_FR"
# Use `localectl list-keymaps` to list keymaps
CONSOLE_KEYMAP="fr-latin9"
CONSOLE_FONT="lat9w-16"
# Replace GMT with the file with your timezone
TIME_ZONE="/usr/share/zoneinfo/GMT"

# System configuration
HOSTNAME="archlinux-pc"
BOOTLOADER="refind"

# Hardware configuration
GPU_BRAND="intel"

# User config
USERNAME="user"
LONG_NAME="Long name of user"

#################################  FUCTIONS  ################################

function setup() {
    ########## CONFIGURATION OF INSTALLER ##########
    echo "$INFO Starting the installer ..."

    # Set up strict script mode :
    # Exit on error.
    set -o errexit # Append "|| true" to override.
    # Exit on error inside any functions or subshells.
    set -o errtrace
    # Do not allow use of undefined vars.
    set -o nounset # Use ${VAR:-} to override.
    # Catch the first error in chained programs with "|"
    set -o pipefail
    # Turn on traces for debug
    # set -o xtrace

    install="pacman -S --noconfirm"
}

function verify() {
    ########## VERIFY CONFIGURATION ##########
    echo "$INFO Verifying your configuration ..."

    # At the moment, BIOS isn't supported. If you wan't this support,
    # don't hesitate to open an Issue on github. If the user is in bios, exit:
    if ! [ -d "/sys/firmware/efi/efivars" ]; then
        echo "$ERROR You're booting in bios and this isn't yet supported."
        exit 1
    fi

    if [ $ENCRYPTION != "none" ] && [ $ENCRYPTION != "lvm" ]; then
        echo "$ERROR The ENCRYPTION variable is incorrectly configured."
        exit 1
    fi
}

function disksetup() {
    echo "$INFO Configuring disks ..."
    if [ "$ENCRYPTION" == "none" ]; then
        mkfs.ext4 "/dev/$ROOT_PART"
        mount "/dev/$ROOT_PART" /mnt
        if [ ! "$SWAP_PART" == "file" ]; then
            mkswap "/dev/$SWAP_PART"
            swapon "/dev/$SWAP_PART"
        fi
    elif [ "$ENCRYPTION" == "lvm" ]; then
        cryptsetup -y -v luksFormat --type luks2 "/dev/$LVM_ENCRYPTED_PART"
        cryptsetup open "/dev/$LVM_ENCRYPTED_PART" "$LVM_DECRYPTED_MAPPER" --allow-discards
        pvcreate "/dev/mapper/$LVM_DECRYPTED_MAPPER"
        vgcreate $VOLUME_GROUP "/dev/mapper/$LVM_DECRYPTED_MAPPER"
        lvcreate -L $ROOT_VOLUME_SIZE $VOLUME_GROUP -n $ROOT_VOLUME
        mkfs.ext4 "/dev/$VOLUME_GROUP/$ROOT_VOLUME"
        mount "/dev/$VOLUME_GROUP/$ROOT_VOLUME" /mnt
        if [ ! "$SWAP_VOLUME" == "file" ]; then
            lvcreate -L $SWAP_VOLUME_SIZE $VOLUME_GROUP -n $SWAP_VOLUME
            mkswap "/dev/$VOLUME_GROUP/$SWAP_VOLUME"
            swapon "/dev/$VOLUME_GROUP/$SWAP_VOLUME"
        fi
    fi

    if [ ! $SWAP_PART = "file" ] || [ ! $SWAP_VOLUME = "file" ]; then
        fallocate -l $SWAP_FILE_SIZE /mnt/swapfile
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
    fi

    if $FORMAT_UEFI; then
        mkfs.vfat -F32 $UEFI_PART
    fi
    mkdir /mnt/boot
    mount $UEFI_PART /mnt/boot
}

function basestrap() {
    ########## STRAP BASE ##########

    # Install base
    echo "$INFO Strapping base and base-devel ..."
    pacstrap /mnt base base-devel
}

function genconffiles() {
    ########## CONFIGURATION FILES ##########
    echo "$INFO Generating configuration files ..."

    # Set hostname
    echo "* hostname ..."
    echo $HOSTNAME >/mnt/etc/hostname
    cat >/mnt/etc/hosts <<EOF
# Static table lookup for hostnames.
# See hosts(5) for details.
127.0.0.1	$HOSTNAME
127.0.0.1   localhost
::1         $HOSTNAME
::1         localhost
EOF

    # Set locales
    echo "* vconsole.conf ..."
    cat >/mnt/etc/vconsole.conf <<EOF
KEYMAP=$CONSOLE_KEYMAP
FONT=$CONSOLE_FONT
EOF

    echo "* locale.conf ..."
    cat >/mnt/etc/locale.conf <<EOF
# Language choosen by default
LANG="$LANGUAGE_CODE.UTF-8"
# Prefer english to default language if no translation
LANGUAGE="$LANGUAGE_CODE:en_US"
# Keep default sorting
LC_COLLATE=C
EOF

    echo "* locale.gen ..."
    sed -si "s/^#$LANGUAGE_CODE/$LANGUAGE_CODE/; \
    s/^#en_US/en_US/;" /mnt/etc/locale.gen

    # Generate fstab
    echo "* fstab ..."
    genfstab -U -p /mnt >>/mnt/etc/fstab

    if [ $SWAP_PART = "file" ] || [ $SWAP_VOLUME = "file" ]; then
        # Fix swapfile bad mounted in fstab
        sed -i 's/\/mnt\/swapfile/\/swapfile/' /etc/fstab
    fi

    # Optimize default settings of pacman
    echo "* Optimizing pacman default settings ..."
    sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf

    echo "$INFO Entering chroot to finish generation of configuration files ..."
    arch-chroot /mnt <<EOF
    
    # Generation of locales
    echo "* Generating locales ..."
    locale-gen
    
    # Set time
    echo "* Setting up time ..."
    ln -sf $TIME_ZONE /etc/localtime
    hwclock --systohc --utc
    
    # Backuping the old mirrorlist and actualizing the new one
    echo "* Getting better mirrors for pacman ..."
    $install reflector
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old
    reflector --age 48 --sort rate --save /etc/pacman.d/mirrorlist

    if [ ! $ENCRYPTION = "none" ] ; then
        echo "* Configuration of mkinitcpio.conf to allow encryption ..."
        # Configuration of init
        sed -i 's/ keyboard//' /etc/mkinitcpio.conf
        sed -i 's/block/keyboard keymap block encrypt/' /etc/mkinitcpio.conf
    fi
    echo "* Generation of initramfs ..."
    mkinitcpio -p linux

    # User configuration
    echo "* Creating user ..."
    useradd -m -g users -G wheel -c "$LONG_NAME" -s /bin/bash $USERNAME
    echo "$INFO Please enter what password would you like for your user"
    passwd $USERNAME
    sed -i 's/# %wheel/%wheel/' /etc/sudoers
    
    # Disabling of root logging
    echo "* Locking root user ..."
    passwd -l root
EOF
}

function plusinstall() {
    ########## ADDITIONALS & DRIVERS FILES ##########
    echo "$INFO Entering chroot to install additional packages and drivers ..."
    arch-chroot /mnt <<EOF

    echo "$INFO Installing additionals tools ..."

    # Install usefull packages
    echo "* Installing usefull packages ..."
    $install mtools intel-ucode lsb-release                    # System tools
    $install dosfstools ntfs-3g exfat-utils                    # Usefull FS drivers
    $install git mc nmap neovim htop wget                      # Personnal cli tools

    echo "* Installing and enabling networkmanager ..."
    $install networkmanager
    systemctl enable NetworkManager

    echo "* Installing and enabling ntp ..."
    $install ntp
    systemctl enable ntpd

    # Fonts
    echo "* Installing fonts ..."
    $install ttf-{bitstream-vera,liberation,freefont,dejavu}

    echo "$INFO Installing drivers ..."
    
    # Video codec
    echo "* Installing video codecs ..."
    $install gst-plugins-{base,good,bad,ugly} gst-libav
    
    # Xorg peripherals drivers
    echo "* Installing Xorg peripherals drivers ..."
    #TODO : Autodetect if laptop or desktop (or VM)
    $install xf86-input-{mouse,keyboard,libinput} xdg-user-dirs
    
    # Xorg peripherals drivers
    echo "* Installing graphical drivers ..."
    # According to gpu, install xorg, openGL, HW video and Vulkan driver (if disponibles)
    if [ $GPU_BRAND = 'intel' ] ; then
        $install xf86-video-intel mesa libva-mesa-driver libvdpau-va-gl vulkan-intel
        elif [ $GPU_BRAND = 'nvidia' ] ; then
        $install xf86-video-nouveau mesa mesa-vdpau
        elif [ $GPU_BRAND = 'oldamd' ] ; then
        $install xf86-video-ati mesa mesa-vdpau
        elif [ $GPU_BRAND = 'newamd' ] ; then
        $install xf86-video-amdgpu mesa mesa-vdpau vulkan-radeon
    fi
    # Many optimizations are disponible according to your gpu, don't hesitate to look further :
    # https://wiki.archlinux.org/index.php/Intel_graphics
    # https://wiki.archlinux.org/index.php/ATI & https://wiki.archlinux.org/index.php/AMDGPU
    # https://wiki.archlinux.org/index.php/Nouveau & https://wiki.archlinux.org/index.php/NVIDIA
    # https://wiki.archlinux.org/index.php/Hardware_video_acceleration
    
    systemctl enable bluetooth
EOF
}

function bootloaderinstall() {
    ########## BOOTLOADER ##########
    echo "$INFO Entering chroot to install bootloader ..."
    arch-chroot /mnt << EOF

    # Installing general tools
    echo "* Installing UEFI tools ..."
    $install os-prober efibootmgr                              # EFI Tools

    # Installing bootloader
    echo "* Preparing variables ..."
    BOOTUUID=$(blkid | grep "$UEFI_PART" | grep -o -E '\sUUID="([a-z0-9-]*)"' | cut -d '"' -f 2)
    if [ "$ENCRYPTION" == "none" ] ; then
        ROOTUUID=$(blkid | grep "$ROOT_PART" | grep -o -E '\sUUID="([a-z0-9-]*)"' | cut -d '"' -f 2)
    elif [ "$ENCRYPTION" == "lvm" ] ; then
        ROOTUUID=$(blkid | grep "$LVM_ENCRYPTED_PART" | grep -o -E '\sUUID="([a-z0-9-]*)"' | cut -d '"' -f 2)
    fi

    if [ $BOOTLOADER = "grub" ] ; then
        echo "* Installing grub ..."
        $install grub
        grub-mkconfig -o /boot/grub/grub.cfg
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Grub_Archlinux --recheck
        if [ "$ENCRYPTION" == "lvm" ] ; then
            sed -i "s/root=\\w*=[\\w-]*\"/cryptdevice=UUID=$ROOTUUID:cryptroot$CONFIGFLAGS root=/dev/mapper/cryptroot rw add_efi_memmap\"" /boot/grub/grub.cfg
        fi
    elif [ $BOOTLOADER = "refind" ] ; then
        echo "* Installing refind ..."
        $install refind-efi
        refind-install
        if [ "$ENCRYPTION" == "none" ] ; then
            cat >> /boot/EFI/refind/refind.conf << EOF2
menuentry \"Arch Linux\" {
    volume  $BOOTUUID
    icon    /EFI/refind/icons/os_arch.png
    loader  /vmlinuz-linux
    initrd  /initramfs-linux.img
    submenuentry \"Boot using fallback initframfs\" {
        initrd  /initramfs-linux-fallback.img
    }
}
EOF2
        elif [ "$ENCRYPTION" == "lvm" ] ; then
            cat >> /boot/EFI/refind/refind.conf << EOF2
menuentry \"Arch Linux\" {
    volume  $BOOTUUID
    icon    /EFI/refind/icons/os_arch.png
    loader  /vmlinuz-linux
    initrd  /initramfs-linux.img
    options \"cryptdevice=UUID=$ROOTUUID:cryptroot$CONFIGFLAGS root=/dev/mapper/cryptroot rw add_efi_memmap\"
    submenuentry \"Boot using fallback initframfs\" {
        initrd  /initramfs-linux-fallback.img
    }
}
EOF2
        fi
    fi
EOF
}

function gnomeinstall() {
    # Install packages
    $install gnome
    $install gnome-tweaks gnome-sound-recorder nautilus-sendto gnome-weather gnomes-recipe gnome-usage

    # Tweaks
    gsettings set org.gnome.desktop.peripherals.touchpad click-method 'areas'
    gsettings set org.gnome.desktop.wm.preferences button-layout ':minimize,maximize,close'

    # Useless packages removal
    pacman -Rsc --noconfirm yelp gnome-logs gnome-system-monitor gnome-todo gnome-getting-started-docs orca rygel vino

    # Basic setup
    sudo localectl set-x11-keymap fr
    systemctl enable gdm
    systemctl enable avahi-daemon
    systemctl enable avahi-dnsconfd
}

function addonsinstall() {
    # Install a real browser
    pacman -Rsc --noconfirm epiphany
    $install firefox

    # Install office tools
    $install "libreoffice-fresh-$LANGUAGE_CODE" unoconv cups
    systemctl enable org.cups.cupsd

    # Install cli tools
    $install htop nmap mc

    # Install dev tools
    $install nmap neovim shellcheck # CLI
    $install code                   # GUI

    # Install an AUR wrapper
    cd /tmp
    git clone https://aur.archlinux.org/pikaur.git && cd pikaur/
    makepkg -si
}

#################################  MAIN  ################################

setup

verify

disksetup

basestrap

genconffiles

plusinstall

bootloaderinstall

gnomeinstall

addonsinstall
