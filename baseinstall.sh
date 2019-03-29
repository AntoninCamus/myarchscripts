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

##############################  SCRIPT VARIABLES  #############################

INSTALL='pacman -S --noconfirm'
ERROR='\e[31m[ MyArchScript - Error ]\e[0m '
INFO='\e[32m[ MyArchScript - Info ]\e[0m '

##############################  USER VARIABLES  #############################

# Disks and part. configuration :

# Disks configuration :
# I provide 2 configuration, described on the official wiki below :
# https://wiki.archlinux.org/index.php/Dm-crypt/Encrypting_an_entire_system
# - no encryption : "none"
# - lvm on luks : "lvm"

# ESP : UEFI partition
UEFI_PART='/dev/sda1'
FORMAT_UEFI='true' # Should be false if you install with another OS, else true.

ENCRYPTION='lvm' # 'none' or 'lvm'

# Then you should fill your choices accordingly :
if [ "$ENCRYPTION" == 'none' ]; then
    ROOT_PART='sda2' # Part. name ('sdxy')
    SWAP_PART='sda3' # Part. name ('sdxy'), 'file' or 'none'
elif [ "$ENCRYPTION" == 'lvm' ]; then
    LVM_ENCRYPTED_PART='sda2'       # Part. name ('sdxy')
    LVM_DECRYPTED_MAPPER='cryptlvm' # Mapper name (e.g. 'cryptlvm')
    VOLUME_GROUP='VolumeGroup'      # It's not necessary to change this one
    ROOT_VOLUME='root'              # LVM volume name, 'file' or 'none'
    ROOT_VOLUME_SIZE='51G'          # Size of Root Volume, in G
    SWAP_VOLUME='swap'              # LVM volume name, 'file' or 'none'
    if [ "$SWAP_VOLUME" != 'file' ]; then
        SWAP_VOLUME_SIZE='4G'
    fi
fi

if [ "$SWAP_PART" == 'file' ] || [ "$SWAP_VOLUME" == 'file' ]; then
    SWAP_FILE_SIZE='4G'
fi

# Localisation configuration :
LANGUAGE_CODE='fr_FR'
CONSOLE_KEYMAP='fr' # Use `localectl list-keymaps` to list keymaps
CONSOLE_FONT='eurlatgr'
TIME_ZONE='/usr/share/zoneinfo/Europe/Paris' # Use `ls -R /usr/share/zoneinfo/` to list all timezones

# System configuration
BOOTLOADER='refind'

#################################  FUCTIONS  ################################

function setup() {
    ########## CONFIGURATION OF INSTALLER ##########
    echo -e "$INFO Starting the installer ..."

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
}

function verify() {
    ######## COMPLETING CONFIGURATION ########
    echo -e "$INFO Asking some user input ..."

    read -rp 'Enter computer name: ' HOSTNAME

    # User config
    read -rp 'Enter username: ' USERNAME
    read -rp 'Enter long name: ' LONG_NAME
    read -rsp 'Enter user password: ' PASSWORD
    read -rsp 'Repeat user password: ' PASSWORD2

    if [ "$PASSWORD" != "$PASSWORD2" ]; then
        echo -e "$ERROR user password weren't the same."
        exit 1
    fi

    read -rsp 'Enter user password: ' DISK_PASSWORD
    read -rsp 'Repeat user password: ' DISK_PASSWORD2

    if [ "$DISK_PASSWORD" != "$DISK_PASSWORD2" ]; then
        echo -e "$ERROR disk password weren't the same."
        exit 1
    fi
    ########## VERIFY CONFIGURATION ##########
    echo -e "$INFO Verifying your configuration ..."

    # At the moment, BIOS isn't supported. If you wan't this support,
    # don't hesitate to open an Issue on github. If the user is in bios, exit:
    if ! [ -d '/sys/firmware/efi/efivars' ]; then
        echo -e "$ERROR You're booting in bios and this isn't yet supported."
        exit 1
    fi

    if [ "$ENCRYPTION" != 'none' ] && [ "$ENCRYPTION" != 'lvm' ]; then
        echo -e "$ERROR The ENCRYPTION variable is incorrectly configured."
        exit 1
    fi
}

function disksetup() {
    echo -e "$INFO Configuring disks ..."
    if [ "$ENCRYPTION" == 'none' ]; then
        mkfs.ext4 "/dev/$ROOT_PART"
        mount "/dev/$ROOT_PART" /mnt
        if [ "$SWAP_PART" != 'file' ] && [ "$SWAP_PART" != 'none' ]; then
            mkswap "/dev/$SWAP_PART"
            swapon "/dev/$SWAP_PART"
        fi
    elif [ "$ENCRYPTION" == 'lvm' ]; then
        cryptsetup luksFormat -q --type luks2 "/dev/$LVM_ENCRYPTED_PART" <<<"$DISK_PASSWORD"
        cryptsetup open "/dev/$LVM_ENCRYPTED_PART" "$LVM_DECRYPTED_MAPPER" --allow-discards <<<"$DISK_PASSWORD"
        pvcreate -ff "/dev/mapper/$LVM_DECRYPTED_MAPPER"
        vgcreate "$VOLUME_GROUP" "/dev/mapper/$LVM_DECRYPTED_MAPPER"
        lvcreate -L "$ROOT_VOLUME_SIZE" "$VOLUME_GROUP" -n "$ROOT_VOLUME"
        mkfs.ext4 "/dev/$VOLUME_GROUP/$ROOT_VOLUME"
        mount "/dev/$VOLUME_GROUP/$ROOT_VOLUME" /mnt
        if [ "$SWAP_VOLUME" != 'file' ] && [ "$SWAP_VOLUME" != 'none' ]; then
            lvcreate -L "$SWAP_VOLUME_SIZE" "$VOLUME_GROUP" -n "$SWAP_VOLUME"
            mkswap "/dev/$VOLUME_GROUP/$SWAP_VOLUME"
            swapon "/dev/$VOLUME_GROUP/$SWAP_VOLUME"
        fi
    fi

    if [ "${SWAP_PART:-}" == 'file' ] || [ "${SWAP_VOLUME:-}" == 'file' ]; then
        fallocate -l "$SWAP_FILE_SIZE" /mnt/swapfile
        chmod 600 /mnt/swapfile
        mkswap /mnt/swapfile
        swapon /mnt/swapfile
    fi

    if $FORMAT_UEFI; then
        mkfs.vfat -F32 "$UEFI_PART"
    fi
    mkdir /mnt/boot
    mount "$UEFI_PART" /mnt/boot
}

function basestrap() {
    ########## STRAP BASE ##########

    # Install base
    echo -e "$INFO Strapping base and base-devel ..."
    pacstrap /mnt base base-devel
}

function genconffiles() {
    ########## CONFIGURATION FILES ##########
    echo -e "$INFO Generating configuration files ..."

    # Set hostname
    echo '* hostname ...'
    echo "$HOSTNAME" >/mnt/etc/hostname
    cat >/mnt/etc/hosts <<EOF
# Static table lookup for hostnames.
# See hosts(5) for details.
127.0.0.1	$HOSTNAME
127.0.0.1   localhost
::1         $HOSTNAME
::1         localhost
EOF

    # Set locales
    echo '* vconsole.conf ...'
    cat >/mnt/etc/vconsole.conf <<EOF
KEYMAP=$CONSOLE_KEYMAP
FONT=$CONSOLE_FONT
EOF

    echo '* locale.conf ...'
    cat >/mnt/etc/locale.conf <<EOF
# Language choosen by default
LANG="$LANGUAGE_CODE.UTF-8"
# Prefer english to default language if no translation
LANGUAGE="$LANGUAGE_CODE:en_US"
# Keep default sorting
LC_COLLATE=C
EOF

    echo '* locale.gen ...'
    sed -si "s/^#$LANGUAGE_CODE/$LANGUAGE_CODE/; \
            s/^#en_US/en_US/;" /mnt/etc/locale.gen

    # Generate fstab
    echo '* fstab ...'
    genfstab -U -p /mnt >>/mnt/etc/fstab

    if [ "${SWAP_PART:-}" == 'file' ] || [ "${SWAP_VOLUME:-}" == 'file' ]; then
        # Fix swapfile bad mounted in fstab
        sed -i 's/\/mnt\/swapfile/\/swapfile/' /etc/fstab
    fi

    # Optimize default settings of pacman
    echo '* Optimizing pacman default settings ...'
    sed -i 's/#Color/Color/' /mnt/etc/pacman.conf
    sed -i 's/#TotalDownload/TotalDownload/' /mnt/etc/pacman.conf

    echo "$INFO Entering chroot to finish generation of configuration files ..."
    arch-chroot /mnt <<EOF
    
    # Generation of locales
    echo '* Generating locales ...'
    locale-gen
    
    # Set time
    echo '* Setting up time ...'
    ln -sf $TIME_ZONE /etc/localtime
    hwclock --systohc --utc
    
    # Backuping the old mirrorlist and actualizing the new one
    echo '* Getting better mirrors for pacman ...'
    $INSTALL reflector
    cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.old
    reflector --age 48 --sort rate --save /etc/pacman.d/mirrorlist

    if [ "$ENCRYPTION" == 'lvm' ] ; then
        echo '* Configuration of mkinitcpio.conf to allow encryption ...'
        # Configuration of init
        sed -i 's/ keyboard//' /etc/mkinitcpio.conf
        sed -i 's/block/keyboard keymap block lvm2 encrypt/' /etc/mkinitcpio.conf
    fi

    echo '* Generation of initramfs ...'
    mkinitcpio -p linux

    # User configuration
    echo '* Creating user ...'
    useradd -m -g users -G wheel -c "$LONG_NAME" -s /bin/bash "$USERNAME"
    echo "$INFO Please enter what password would you like for your user"
    chpasswd <<< $USERNAME:$PASSWORD
    sed -i 's/# %wheel/%wheel/' /etc/sudoers
    
    # Disabling of root logging
    echo '* Locking root user ...'
    passwd -l root
EOF
}

function plusinstall() {
    ########## ADDITIONALS & DRIVERS FILES ##########
    echo -e "$INFO Installing additionals tools ..."
    arch-chroot /mnt <<EOF

    echo '* Installing usefull packages ...'
    $INSTALL mtools intel-ucode lsb-release                    # System tools
    $INSTALL dosfstools ntfs-3g exfat-utils                    # Usefull FS drivers

    echo '* Installing and enabling networkmanager ...'
    $INSTALL networkmanager
    systemctl enable NetworkManager

    echo '* Installing and enabling ntp ...'
    $INSTALL ntp
    systemctl enable ntpd
EOF
}

function bootloaderinstall() {
    ########## BOOTLOADER ##########
    echo '* Preparing variables ...'
    CONFIGFLAGS=':allow-discards'
    BOOTUUID=$(blkid | grep "$UEFI_PART" | grep -o -E '\sUUID="([a-zA-Z0-9-]*)"' | cut -d '"' -f 2)
    if [ "$ENCRYPTION" == 'none' ]; then
        ROOTUUID=$(blkid | grep "$ROOT_PART" | grep -o -E '\sUUID="([a-zA-Z0-9-]*)"' | cut -d '"' -f 2)
    elif [ "$ENCRYPTION" == 'lvm' ]; then
        ROOTUUID=$(blkid | grep "$LVM_ENCRYPTED_PART" | grep -o -E '\sUUID="([a-zA-Z0-9-]*)"' | cut -d '"' -f 2)
    fi

    echo -e "$INFO Entering chroot to install bootloader ..."
    arch-chroot /mnt <<EOF
    echo '* Installing UEFI tools ...'
    $INSTALL os-prober efibootmgr                              # EFI Tools

    # Installing bootloader
    if [ "$BOOTLOADER" == 'grub' ] ; then
        echo '* Installing grub ...'
        $INSTALL grub
        grub-mkconfig -o /boot/grub/grub.cfg
        grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=Grub_Archlinux --recheck
    elif [ $BOOTLOADER = 'refind' ] ; then
        echo '* Installing refind ...'
        $INSTALL refind-efi
        refind-install
    fi
EOF

    echo -e "$INFO Configuring bootloader ..."
    if [ "$BOOTLOADER" == 'grub' ]; then
        if [ "$ENCRYPTION" == 'lvm' ]; then
            sed -i \
                "s/root=\\w*=[\\w-]*\"/cryptdevice=UUID=$ROOTUUID:cryptroot$CONFIGFLAGS root=/dev/mapper/cryptroot rw add_efi_memmap\"" \
                /mnt/boot/grub/grub.cfg
        fi
    elif [ "$BOOTLOADER" == 'refind' ]; then
        if [ "$ENCRYPTION" == 'none' ]; then
            cat >>/mnt/boot/EFI/refind/refind.conf <<EOF
menuentry "Arch Linux" {
    volume  $BOOTUUID
    icon    /EFI/refind/icons/os_arch.png
    loader  /vmlinuz-linux
    initrd  /initramfs-linux.img
    submenuentry "Boot using fallback initframfs" {
        initrd  /initramfs-linux-fallback.img
    }
}
EOF
        elif [ "$ENCRYPTION" == 'lvm' ]; then
            cat >>/mnt/boot/EFI/refind/refind.conf <<EOF
menuentry "Arch Linux" {
    volume  $BOOTUUID
    icon    /EFI/refind/icons/os_arch.png
    loader  /vmlinuz-linux
    initrd  /initramfs-linux.img
    options "cryptdevice=UUID=$ROOTUUID:$LVM_DECRYPTED_MAPPER$CONFIGFLAGS root=/dev/$VOLUME_GROUP/$ROOT_VOLUME rw add_efi_memmap"
    submenuentry "Boot using fallback initframfs" {
        initrd  /initramfs-linux-fallback.img
    }
}
EOF
        fi

    fi
}

#################################  MAIN  ################################

setup

verify

disksetup

basestrap

genconffiles

plusinstall

bootloaderinstall
