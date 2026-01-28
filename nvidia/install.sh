#!/bin/bash

# ============================================================================
# DEFENSIVE SHELL OPTIONS
# ============================================================================
# Store current shell options
OLD_SET_OPTIONS="$-"

# Enable defensive options
set -eu

# pipefail is trickier - we'll set it but be careful
set -o pipefail || {
    echo "Warning: pipefail not supported, some error detection may be limited" >&2
}

# ============================================
# ============================================

# ============================================================================
# install-nvidia.sh -
# Purpose: Installs nvidia drivers
# Best Practice: sudo chmod +x ${SCRIPT_NAME}
# Usage: sudo bash ./${SCRIPT_NAME}  
# ============================================================================
# Author: ZBH33
# Version: 0.1
# ============================================================================

# ============================================
# CONFIGURATION
# ============================================

# Default settings
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"
LOG_DIR="/var/log/${SCRIPT_NAME}/logs_${TIMESTAMP}"
LOG_FILE=""  # Will be set in init_logging after LOG_DIR is created

# Aesthetics 
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
ICON='\xF0\x9F\x8C\x80'
NC='\033[0m'

# ============================================
# ============================================

# ============================================
# CONFIG FUNCTIONS
# ============================================

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            print_usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option $1"
            print_usage
            exit 1
            ;;
        *)
    esac
done

# Check if you're root user
require_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        error "This script must be run as root (use sudo)."
    fi
}

# ============================================
# ============================================

# ============================================
# PRINT FUNCTIONS
# ============================================

# Help Menu
print_usage() {
    cat <<EOF
Usage: sudo chmod +x ${SCRIPT_NAME} && sudo bash ./${SCRIPT_NAME}

Description:
  This script will install nvidia drivers.

Options:
  -h    Show this help message
EOF
}

# Print a message
print_message() {
    local color="$1"
    local message="$2"
    local line_number="${BASH_LINENO[0]}"

    echo -e "${color}${ICON} ${message}${NC}"

    log_entry="[$timestamp] [${SCRIPT_NAME}:${line_number}] $message"

    echo "${log_entry}" >> "$LOG_FILE"
}

print_debug() {
    print_message "${BLUE}" "DEBUG: $1"
}

print_error() {
    print_message "${RED}" "ERROR: $1"
}

print_warning() {
    print_message "${YELLOW}" "WARNING: $1"
}

print_success() {
    print_message "${GREEN}" "SUCCESS: $1"
}

print_info() {
    print_message "${NC}" "INFO: $1"
}

# Initialize logging system
init_logging() {
    # Create log directory first - CRITICAL: Must create directory BEFORE any print_message calls
    mkdir -p "${LOG_DIR}" 2>/dev/null || {
        # Use echo for initial error since logging isn't ready yet
        echo "[ERROR] Failed to create log directory: ${LOG_DIR}" >&2
        return 1
    }
    
    # Now that directory exists, we can define log files
    LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_${TIMESTAMP}.log"
    
    # Log initialization - only now that files are ready
    print_message "INFO" "Logging initialized"
    print_message "DEBUG" "Log verbosity level set to: $VERBOSITY"
    print_message "DEBUG" "Main log: $LOG_FILE"
    
    return 0
}

# ============================================
# PRECHECKS
require_root
# ============================================

if ! lspci | grep -qi nvidia; then
    error "No NVIDIA GPU detected via lspci. Aborting."
fi

print_message "NVIDIA GPU detected. Proceeding."

# ============================================
# SYSTEM UPDATE 
# ============================================

print_message "Updating system packages"
    ubuntu-drivers autoinstall --purge
    apt autoremove &&  apt update &&  apt upgrade -y

# ============================================
# DEPENDENCIES
# ============================================

print_message "Installing build dependencies"
    ubuntu-drivers autoinstall
    apt install nvidia-cuda-toolkit

# ============================================
# REBOOT NOTICE 
# ============================================

    nvidia-smi -pm 1
print_message "Installation complete. A reboot is required."


cat <<EOF
# ============================================
NVIDIA driver installation finished.
# ============================================

NEXT STEPS:
1. Reboot the system:
    sudo reboot

2. Verify after reboot:
    nvidia-smi
# ============================================
EOF
