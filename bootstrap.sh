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
# Title : Boostrap                                                          #
#                                                                           #
# Author : Antonin Camus (github.com/antonincamus)                          #
#                                                                           #
# Description : This script is just a boosraper of my DE (gnome) and        #
#               some tools and dev config, inspire yourself !               #
#                                                                           #
# License : This script is shared under GPL3 licence terms.                 #
#                                                                           #
#############################################################################

#### Variable

GPU_BRAND="intel"

#### Setup installer ####

# Set up strict script mode :
set -o errexit  # Exit on error, append "|| true" to override.
set -o errtrace # Exit on error inside any functions or subshells.
set -o nounset  # Do not allow use of undefined vars, use ${VAR:-} to override.
set -o pipefail # Catch the first error in chained programs with "|"
# set -o xtrace # Turn on traces for debug

# Update system and check presence of dev packages ####
sudo pacman -Syu --noconfirm
sudo pacman -S base-devel git --noconfirm --needed

# Install aur helper : pikaur
if ! command -v pikaur >/dev/null; then
    cd /tmp
    git clone https://aur.archlinux.org/pikaur.git
    cd /tmp/pikaur
    makepkg -si --noconfirm --needed
    cd
    rm -rf /tmp/pikaur
fi

# Setup aliases
pacinstall="sudo pikaur -S --noconfirm --needed"
pacremove="sudo pikaur -Rsc --noconfirm"

#### Install packages ####

# Install gnome
$pacinstall gnome
$pacremove epiphany gedit totem simple-scan yelp
$pacremove gnome-{books,calendar,characters,dictionary,font-viewer,maps,music,logs,todo,terminal,system-monitor}

# Install graphic drivers
#TODO : Autodetect if laptop or desktop (or VM)
$INSTALL xf86-input-{mouse,keyboard,libinput} xdg-user-dirs

echo "* Installing graphical drivers ..."
# According to gpu, install xorg, openGL, HW video and Vulkan driver (if disponibles)
if [ $GPU_BRAND = "intel" ]; then
    $INSTALL xf86-video-intel mesa libva-mesa-driver libvdpau-va-gl vulkan-intel
elif [ $GPU_BRAND = "nvidia" ]; then
    $INSTALL xf86-video-nouveau mesa mesa-vdpau
elif [ $GPU_BRAND = "oldamd" ]; then
    $INSTALL xf86-video-ati mesa mesa-vdpau
elif [ $GPU_BRAND = "newamd" ]; then
    $INSTALL xf86-video-amdgpu mesa mesa-vdpau vulkan-radeon
fi

# Many optimizations are disponible according to your gpu, don't hesitate to look further :
# https://wiki.archlinux.org/index.php/Intel_graphics
# https://wiki.archlinux.org/index.php/ATI & https://wiki.archlinux.org/index.php/AMDGPU
# https://wiki.archlinux.org/index.php/Nouveau & https://wiki.archlinux.org/index.php/NVIDIA
# https://wiki.archlinux.org/index.php/Hardware_video_acceleration

systemctl enable bluetooth || true                                                 # If this command fail : don't raise error, pc has no bluetooth

# Add new useful softwares
$pacinstall gnome-usage gnome-tweaks                                               #Gnome tools
$pacinstall firefox firefox-i18n-fr chrome-gnome-shell typora cups                 #Work
$pacinstall meld tilix code                                                        #Dev
$pacinstall pamac-aur flatpak                                                      #System tools
$pacinstall transmission-gtk                                                       #Millenacious

# Flatpak install repos & tools
flatpak install -y flathub com.discordapp.Discord                                  #Discord
flatpak install -y flathub com.spotify.Client                                      #Spotify
# Codecs
$pacinstall gst-libav gst-plugins-{base,good,bad,ugly}                             #Video & sound codecs

# Term tools
$pacinstall zsh antigen-git neofetch exa                                           #Shell
$pacinstall htop mc tmux nmap lnav hwloc minicom                                   #TUI Utilies
$pacinstall docker virtualbox                                                      #Virtualisation

# Developpement tools & languages
$pacinstall plantuml tokei                                                         #Tools
$pacinstall shellcheck shfmt python-pylint                                         #Formaters and linters

# Fonts
$pacinstall ttf-bitstream-vera ttf-dejavu ttf-freefont ttf-liberation ttf-opensans #General fonts
$pacinstall ttf-fira-code ttf-mononoki                                             #Dev fonts

#### Config ####

# X config
sudo localectl set-x11-keymap fr

# Gnome config
gsettings set org.gnome.desktop.peripherals.touchpad click-method "areas"
gsettings set org.gnome.desktop.wm.preferences button-layout ":minimize,maximize,close"
sudo systemctl enable gdm
sudo systemctl enable org.cups.cupsd

# ZSH Config
chsh -s /bin/zsh #Set as default
cat >~/.zshrc <<EOF
### Antigen
source /usr/share/zsh/share/antigen.zsh

# Load the oh-my-zsh's library.
antigen use oh-my-zsh

# Bundles from the default repo (robbyrussell's oh-my-zsh).
antigen bundle git
antigen bundle extract
antigen bundle common-aliases
antigen bundle command-not-found
antigen bundle zsh-users/zsh-syntax-highlighting
antigen bundle zsh-users/zsh-history-substring-search
antigen bundle zsh-users/zsh-autosuggestions
antigen bundle zsh-users/zsh-completions

# Load the theme.
antigen theme agnoster

# Tell Antigen that you're done.
antigen apply

### Aliases
# ls
alias ls="exa"
alias la="exa -a"
alias ll="exa -l"
alias lla="exa -la"
alias llt="exa -T"
alias llfu="exa -bgGhHlS --git"
# cp
alias cp="cp -R"
# scp
alias scp="scp -r"
alias grep="grep --color=auto"
# mkdir
alias mkdir="mkdir -p"
# df
alias df="df -kTh"
# update
alias update="sudo pikaur -Syu ; flatpak update"

### Variables
export EDITOR=nano

### Welcome
neofetch
EOF
