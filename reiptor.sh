#!/bin/bash

############################################################################
# reiptor                                                                  #
# Copyright (C) 2025 Vasu Makadia                                          #
#                                                                          #
# Licensed under the Apache License, Version 2.0 (the "License");          #
# you may not use this file except in compliance with the License.         #
# You may obtain a copy of the License at                                  #
#                                                                          #
#      http://www.apache.org/licenses/LICENSE-2.0                          #
#                                                                          #
# Unless required by applicable law or agreed to in writing, software      #
# distributed under the License is distributed on an "AS IS" BASIS,        #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. #
# See the License for the specific language governing permissions and      #
# limitations under the License.                                           #
############################################################################

##########################################
# Color Definitions for Terminal Output  #
##########################################
BOLD_RED='\033[1;31m'
RED='\033[0;31m'
BOLD_GREEN='\033[1;32m'
GREEN='\033[0;32m'
BOLD_YELLOW='\033[1;33m'
YELLOW='\033[0;33m'
BOLD_BLUE='\033[1;34m'
BLUE='\033[0;34m'
NC='\033[0m'

########################
# Display ASCII Banner #
# ######################
show_ascii_banner() {
    echo -e "${BOLD_BLUE}"
    echo "              _____    ___  _                "
    echo " _ __   ___   \_   \  / _ \| |_   ___   _ __ "
    echo "| '__| / _ \   / /\/ / /_)/| __| / _ \ | '__|"
    echo "| |   |  __//\/ /_  / ___/ | |_ | (_) || |   "
    echo "|_|    \___|\____/  \/      \__| \___/ |_|   "
    echo -e "${BLUE}                   v1.0       "
    echo -e "${BOLD_RED}     Where you were isn't where you are.     "
    echo -e "${NC}\n"
}

##############################
# Check for Root privellages #
##############################
check_root_privellages() {
    if [[ "$UID" -ne 0 ]]; then
        echo -e "${RED}[ERROR]:${NC} Please run 'reIPtor.sh' as a Root User.\n"
        exit 1
    fi
    echo -e "${GREEN}[*]${NC} Detected Root user privellages."
}

#################################
# Detect the Linux distribution #
#################################
detect_linux_distro() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        LINUX_DISTRO=$ID
        LINUX_NAME=$PRETTY_NAME
        LINUX_ARCHITECTURE=$(uname -m)
    else
        echo -e "${RED}[ERROR]:${NC} Unsupported Linux distribution found.\n"
        exit 1
    fi
    echo -e "${GREEN}[*]${NC} Detected OS:${YELLOW} ${PRETTY_NAME} ${LINUX_ARCHITECTURE} (${LINUX_DISTRO})${NC}"
}

#############################
# Install required packages #
#############################
install_packages() {
    echo -e "${BLUE}[i]${NC} Checking availability of required packages..."

    # Array to store the required packages
    REQUIRED_PACKAGES=(curl tor jq xxd)
    # Array to store the missing packages
    MISSING_PACKAGES=()

    # Look for the missing packages
    for pkg in "${REQUIRED_PACKAGES[@]}"; do
        if ! command -v "${pkg}" >/dev/null 2>&1; then
            MISSING_PACKAGES+=("${pkg}")
        fi
    done

    # Move on if all required packages are installed already
    if [ ${#MISSING_PACKAGES[@]} -eq 0 ]; then
        echo -e "${GREEN}[*]${NC} All required packages are already installed."
        return
    fi

    # Install the missing packages based on the Linux Distro
    echo -e "${BLUE}[i]${NC} Installing required packages..."
    local INSTALL_ATTEMPTED=false

    case "${LINUX_DISTRO}" in
    arch | manjaro | blackarch)
        INSTALL_ATTEMPTED=true
        pacman -S --needed --noconfirm "${MISSING_PACKAGES[@]}" >/dev/null 2>&1
        ;;
    debian | ubuntu | kali | parrot)
        INSTALL_ATTEMPTED=true
        apt update >/dev/null 2>&1
        apt install -y "${MISSING_PACKAGES[@]}" >/dev/null 2>&1
        ;;
    fedora)
        INSTALL_ATTEMPTED=true
        dnf install -y "${MISSING_PACKAGES[@]}" >/dev/null 2>&1
        ;;
    opensuse)
        INSTALL_ATTEMPTED=true
        zypper install -y ${MISSING_PACKAGES[@]} >/dev/null 2>&1
        ;;
    *)
        echo -e "${RED}[ERROR]:${NC} Unsupported Linux distribution. Install '${MISSING_PACKAGES[@]}' manually on your system.\n"}
        ;;
    esac

    # Exit if Install Attempt is made and got unsuccessful in it
    if ${INSTALL_ATTEMPTED} && [ $? -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Package installation failed unexpectadely."
        exit 1
    elif ${INSTALL_ATTEMPTED}; then
        echo -e "${GREEN}[*]:${NC} All required packages installed successfully."
    fi
}

#################################################
# Create a TOR Group and add Current User to it #
#################################################
configure_user_group() {
    # Declare a TOR Group based on Linux distribution
    case "${LINUX_DISTRO}" in
    arch | blackarch | manjaro | fedora | opensuse)
        TOR_GROUP="tor"
        ;;
    debian | ubuntu | kali | parrot)
        TOR_GROUP="debian-tor"
        ;;
    *)
        echo -e "${RED}[x]${NC} Unable to determine TOR group for your Linux Distribution."
        echo -e "${YELLOW}[w]${NC} Please create a TOR Group and add your current user into it manually for your system."
        return
        ;;
    esac

    # Create a TOR Service group if not already existing
    if ! getent group "${TOR_GROUP}" >/dev/null; then
        echo -e "${YELLOW}[w]${NC} Group '${TOR_GROUP}' not found. Creating it..."

        if groupadd "${TOR_GROUP}" >/dev/null 2>&1; then
            echo -e "${GREEN}[*]${NC} Group '${TOR_GROUP}' created successfully."
        else
            echo -e "${RED}[ERROR]${NC} Failed to create group '${TOR_GROUP}'"
            return
        fi
    else
        echo -e "${GREEN}[*]${NC} Group '${TOR_GROUP}' already exist."
    fi

    # Add the current user to the TOR Group
    if ! groups "$SUDO_USER" | grep -q "\b${TOR_GROUP}\b"; then
        echo -e "${BLUE}[i]${NC} Adding user '$SUDO_USER' to group '${TOR_GROUP}' ..."

        if usermod -aG "${TOR_GROUP}" "$SUDO_USER" >/dev/null 2>&1; then
            echo -e "${GREEN}[*]${NC} User '$SUDO_USER' added to group '${TOR_GROUP}' successfully."
        else
            echo -e "${RED}[ERROR]${NC} Failed to '${SUDO_USER}' to group '${TOR_GROUP}'"
        fi
    else
        echo -e "${GREEN}[*]${NC} User '$SUDO_USER' is already part of group '${TOR_GROUP}'"
    fi
}

##########################
# Configure TOR services #
##########################
configure_tor() {
    echo -e "${BLUE}[i]${NC} Configuring TOR Service..."
    local TORRC_FILE="/etc/tor/torrc"
    local NEEDS_UPDATE=0

    # Check if required parameters are properly set or not
    grep -q "^ControlPort 9051" "${TORRC_FILE}" || NEEDS_UPDATE=1
    grep -q "^CookieAuthentication 1" "${TORRC_FILE}" || NEEDS_UPDATE=1
    grep -q "^CookieAuthFileGroupReadable 1" "${TORRC_FILE}" || NEEDS_UPDATE=1

    # Set up and update the TORRC with required parameters
    if [ "${NEEDS_UPDATE}" -eq 1 ]; then
        echo -e "${BLUE}[i]${NC} Updating TORRC with required TOR Network settings..."
        {
            echo ""
            echo "# Configurations added by [reIPtor]"
            echo "ControlPort 9051"
            echo "CookieAuthentication 1"
            echo "CookieAuthFileGroupReadable 1"
        } | tee -a "${TORRC_FILE}" >/dev/null 2>&1

        systemctl restart tor >/dev/null 2>&1
        echo -e "${GREEN}[*]${NC} TOR Service configured successfully."
    else
        echo -e "${GREEN}[i]${NC} TOR Service is already configured, Skipping configs..."
    fi
}

##############################
# Change TOR IP periodically #
##############################
change_tor_ip() {
    local COOKIE=$(xxd -ps /var/run/tor/control.authcookie 2>/dev/null | tr -d '\n')
    printf "AUTHENTICATE %s\r\nSIGNAL NEWNYM\r\nQUIT\r\n" "$COOKIE" | nc 127.0.0.1 9051 >/dev/null 2>&1

    local IP=$(curl -s --socks5-hostname 127.0.0.1:9050 https://check.torproject.org/api/ip 2>/dev/null | jq -r .IP 2>/dev/null)
    echo "$(date '+%Y-%m-%d %H:%M:%S') - New TOR IP: ${IP}"
}

#####################
# main: Entry Point #
# ###################
main() {
    # Calling the custom routines for executions
    show_ascii_banner
    check_root_privellages
    detect_linux_distro
    install_packages
    configure_user_group
    configure_tor

    # Get the interval from the User to change the TOR IP
    echo ""
    read -p "Enter time interval to change your IP (in sec) [default is 15s]: " TIME_INTERVAL
    TIME_INTERVAL=${TIME_INTERVAL:-15}

    echo -e "${BLUE}[i]${NC} Changing your TOR IP at every ${TIME_INTERVAL} seconds..."

    while true; do
        change_tor_ip
        sleep "${TIME_INTERVAL}"
    done

    echo -e "${BLUE}[i]${NC} Exiting reIPtor..."
}

# Run the main Script
main
