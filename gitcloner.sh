#!/bin/bash

# ============================================================================
# DEFENSIVE SHELL OPTIONS - MUST BE AT THE VERY BEGINNING
# ============================================================================
# Store current shell options
OLD_SET_OPTIONS="$-"

# Enable defensive options
set -eu

# pipefail is trickier - we'll set it but be careful
set -o pipefail || {
    echo "Warning: pipefail not supported, some error detection may be limited" >&2
}
# ============================================================================

# ============================================================================
# Gitcloner.sh - Complete Version
# Purpose: clones git repositories listed in a file to the user's home directory
# Usage: ./gitcloner_full.sh 
# Example: ./gitcloner_full.sh ./repolist.txt
# You need to create a file with one git repository URL per line.
# Example repolist.txt:
# https://github.com/user/repo.git # line 1
# https://some-other-repo-url.git # line 2
# https://another-repo-url.git # line 3
# ============================================================================
# Author: ZBH33
# Version: 1.1 (Fixed)
# ============================================================================

# ============================================
# CONFIGURATION
# ============================================

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_NAME="$(basename "$0")"

# Configuration files
REPO_LIST_FILE="${SCRIPT_DIR}/repositories.txt"
CONFIG_FILE="${SCRIPT_DIR}/config.conf"

# Default settings
DEFAULT_CLONE_DIR="${HOME}/repositories"
VERBOSITY=3  # Default verbosity level: INFO and above

CURRENT_DATE=$(date '+%Y-%m-%d')
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')

# ============================================
# PATH UTILITY FUNCTIONS
# ============================================

# Path utility functions
normalize_path() {
    local path="$1"
    
    # Convert Windows paths to Unix style if needed
    if [[ "$path" =~ ^[A-Za-z]: ]]; then
        # Windows path with drive letter
        local drive_letter="${path:0:1}"
        local rest="${path:2}"
        path="/${drive_letter,,}${rest//\\//}"
    fi
    
    # Remove duplicate slashes
    echo "$path" | sed 's|//*|/|g'
}

join_paths() {
    local base="$1"
    local rel="$2"
    
    base=$(normalize_path "$base")
    rel=$(normalize_path "$rel")
    
    # Remove trailing slash from base
    base="${base%/}"
    
    # Remove leading slash from relative
    rel="${rel#/}"
    
    echo "${base}/${rel}"
}

# ============================================
# LOGGING MODULE (EMBEDDED)
# ============================================

# Logging Configuration - defaults, can be overridden by config file
LOG_DIR=$(join_paths "${HOME}" "logs/${SCRIPT_NAME}/logs_$(date '+%Y%m%d')")
LOG_FILE=""  # Will be set in init_logging after LOG_DIR is created
ERROR_LOG_FILE=""  # Will be set in init_logging after LOG_DIR is created
# Default log settings - can be overridden by config
: "${MAX_LOG_SIZE_MB:=10}"  # Use default of 10 if not set in config
: "${MAX_LOG_FILES:=30}"    # Use default of 30 if not set in config

# Color definitions (for terminal output only)
if [ -t 1 ]; then
    NC='\033[0m'        # No Color
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
else
    NC=''
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
fi

# Numeric log levels for comparison
LOG_LEVEL_FATAL=0
LOG_LEVEL_ERROR=1
LOG_LEVEL_WARNING=2
LOG_LEVEL_INFO=3
LOG_LEVEL_SUCCESS=3  # Same as INFO level
LOG_LEVEL_DEBUG=4

# Get current verbosity description
get_verbosity_description() {
    case "$VERBOSITY" in
        0) echo "FATAL only (quiet)" ;;
        1) echo "ERROR and above" ;;
        2) echo "WARNING and above" ;;
        3) echo "INFO and above (normal)" ;;
        4) echo "DEBUG and above (verbose)" ;;
        *) echo "Unknown ($VERBOSITY)" ;;
    esac
}

# Initialize logging system
init_logging() {
    # Create log directory first - CRITICAL: Must create directory BEFORE any log_message calls
    mkdir -p "$LOG_DIR" 2>/dev/null || {
        # Use echo for initial error since logging isn't ready yet
        echo "[ERROR] Failed to create log directory: $LOG_DIR" >&2
        return 1
    }
    
    # Now that directory exists, we can define log files
    LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_$(date '+%Y%m%d').log"
    ERROR_LOG_FILE="${LOG_DIR}/${SCRIPT_NAME}_errors_$(date '+%Y%m%d').log"
    
    # Rotate logs if they exceed maximum size
    rotate_logs "$LOG_FILE" "$MAX_LOG_SIZE_MB"
    rotate_logs "$ERROR_LOG_FILE" "$MAX_LOG_SIZE_MB"
    
    # Clean up old log files
    cleanup_old_logs
    
    # Log initialization - only now that files are ready
    log_message "INFO" "Logging initialized"
    log_message "DEBUG" "Log verbosity level set to: $VERBOSITY"
    log_message "DEBUG" "Main log: $LOG_FILE"
    log_message "DEBUG" "Error log: $ERROR_LOG_FILE"
    
    return 0
}

# Get numeric value for log level
get_log_level_number() {
    local level="$1"
    case "$level" in
        "FATAL")   echo $LOG_LEVEL_FATAL ;;
        "ERROR")   echo $LOG_LEVEL_ERROR ;;
        "WARNING") echo $LOG_LEVEL_WARNING ;;
        "INFO")    echo $LOG_LEVEL_INFO ;;
        "SUCCESS") echo $LOG_LEVEL_SUCCESS ;;
        "DEBUG")   echo $LOG_LEVEL_DEBUG ;;
        *)         echo $LOG_LEVEL_INFO ;;  # Default
    esac
}

# Check if message should be displayed based on verbosity
should_log() {
    local message_level="$1"
    local message_level_num=$(get_log_level_number "$message_level")
    
    # Always show FATAL and ERROR messages regardless of verbosity
    if [ "$message_level" = "FATAL" ] || [ "$message_level" = "ERROR" ]; then
        return 0
    fi
    
    # Check if message level is within current verbosity
    if [ "$message_level_num" -le "$VERBOSITY" ]; then
        return 0
    else
        return 1
    fi
}

# Rotate log file if it exceeds maximum size
rotate_logs() {
    local log_file="$1"
    local max_size_mb="$2"
    
    [ -f "$log_file" ] || return 0
    
    local size_bytes=$(stat -c%s "$log_file" 2>/dev/null || stat -f%z "$log_file" 2>/dev/null)
    local size_mb=$((size_bytes / 1024 / 1024))
    
    if [ "$size_mb" -ge "$max_size_mb" ]; then
        local timestamp=$(date '+%Y%m%d_%H%M%S')
        local rotated_file="${log_file}.${timestamp}"
        mv "$log_file" "$rotated_file" 2>/dev/null && \
        log_message "INFO" "Rotated log file: $log_file -> $rotated_file"
    fi
}

# Clean up old log files
cleanup_old_logs() {
    local pattern="${LOG_DIR}/*.log.*"
    local files=($(ls -t $pattern 2>/dev/null))
    local count=${#files[@]}
    
    if [ "$count" -gt "$MAX_LOG_FILES" ]; then
        for ((i=MAX_LOG_FILES; i<count; i++)); do
            rm -f "${files[$i]}" 2>/dev/null && \
            log_message "DEBUG" "Removed old log file: ${files[$i]}"
        done
    fi
}

# Main logging function
log_message() {
    local level="${1:-INFO}"
    local message="${2:-}"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local line_number="${BASH_LINENO[0]}"
    
    # Format log entry with additional context
    local log_entry="[$timestamp] [$level] [${SCRIPT_NAME}:${line_number}] $message"
    
    # Always write to main log file (full logging)
    echo "$log_entry" >> "$LOG_FILE"
    
    # Write to error log for error levels
    case "$level" in
        "ERROR"|"FATAL")
            echo "$log_entry" >> "$ERROR_LOG_FILE"
            
            # For FATAL errors, optionally send notification
            if [ "$level" = "FATAL" ]; then
                send_alert "$log_entry"
            fi
            ;;
    esac
    
    # Terminal output with colors and verbosity control
    if should_log "$level"; then
        case "$level" in
            "DEBUG")
                # DEBUG messages only show when verbosity is 4+
                if [ "$VERBOSITY" -ge 4 ]; then
                    echo -e "${CYAN}[DEBUG]${NC} $message" >&2
                fi
                ;;
            "INFO")
                echo -e "${BLUE}[INFO]${NC} $message" >&2
                ;;
            "SUCCESS")
                echo -e "${GREEN}[SUCCESS]${NC} $message" >&2
                ;;
            "WARNING")
                echo -e "${YELLOW}[WARNING]${NC} $message" >&2
                ;;
            "ERROR")
                echo -e "${RED}[ERROR]${NC} $message" >&2
                ;;
            "FATAL")
                echo -e "${BOLD}${RED}[FATAL]${NC} $message" >&2
                ;;
            *)
                echo -e "${MAGENTA}[$level]${NC} $message" >&2
                ;;
        esac
    fi
}

# Set verbosity level
set_verbosity() {
    local level="$1"
    case "$level" in
        0|1|2|3|4)
            VERBOSITY=$level
            log_message "DEBUG" "Verbosity level changed to: $VERBOSITY"
            ;;
        "FATAL"|"fatal")
            VERBOSITY=0
            ;;
        "ERROR"|"error")
            VERBOSITY=1
            ;;
        "WARNING"|"warning")
            VERBOSITY=2
            ;;
        "INFO"|"info")
            VERBOSITY=3
            ;;
        "DEBUG"|"debug")
            VERBOSITY=4
            ;;
        *)
            log_message "WARNING" "Invalid verbosity level: $level. Using default (3)"
            VERBOSITY=3
            ;;
    esac
}

# Log command execution with error trapping
log_and_run() {
    local command="$1"
    local description="${2:-$command}"
    
    log_message "DEBUG" "Executing: $description"
    
    # Temporarily disable set -e for this function
    # This allows us to capture and handle errors without exiting
    set +e
    
    # Execute command and capture output
    local output
    local exit_code
    
    output=$(eval "$command" 2>&1)
    exit_code=$?
    
    # Restore set -e
    set -e
    
    if [ $exit_code -eq 0 ]; then
        log_message "SUCCESS" "Command completed successfully: $description"
        # Show output only in debug mode
        if [ -n "$output" ] && [ "$VERBOSITY" -ge 4 ]; then
            log_message "DEBUG" "Output: $output"
        fi
    else
        log_message "ERROR" "Command failed with exit code $exit_code: $description"
        if [ -n "$output" ]; then
            log_message "ERROR" "Error output: $output"
        fi
    fi
    
    return $exit_code
}

# Send alert for critical errors (example implementation)
send_alert() {
    local message="$1"
    
    # Example: Send email (requires mail command)
    # echo "$message" | mail -s "Script Error Alert" admin@example.com
    
    # Example: Send to syslog
    logger -t "$(basename "$0")" "FATAL_ERROR: $message"
    
    # Example: Send to external monitoring service
    # curl -X POST -H "Content-Type: application/json" \
    #      -d "{\"message\":\"$message\"}" \
    #      https://monitoring.example.com/alerts >/dev/null 2>&1
    
    log_message "DEBUG" "Alert sent for: $message"
}

# Create a stack trace on error
log_stack_trace() {
    local depth=${1:-10}
    
    # Only show stack trace in DEBUG mode
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "Stack trace (most recent call first):"
        for ((i=1; i<depth; i++)); do
            local func="${FUNCNAME[$i]}"
            local line="${BASH_LINENO[$((i-1))]}"
            local src="${BASH_SOURCE[$i]}"
            
            if [ -n "$func" ] && [ -n "$line" ] && [ -n "$src" ]; then
                log_message "DEBUG" "  $i: $func at $src:$line"
            fi
        done
    fi
}

# Log script termination
log_script_exit() {
    local exit_code=$?
    local signal="${1:-}"
    
    if [ -n "$signal" ]; then
        log_message "WARNING" "Script received signal: $signal"
    fi
    
    if [ $exit_code -eq 0 ]; then
        log_message "SUCCESS" "Script completed successfully"
    else
        log_message "ERROR" "Script exited with error code: $exit_code"
        log_stack_trace
    fi
    
    # Flush any buffered output
    sync 2>/dev/null
}

# Set up traps for error handling
setup_traps() {
    # Trap errors
    trap 'log_message "ERROR" "Error on line $LINENO"; log_stack_trace' ERR
    
    # Trap script exit
    trap 'log_script_exit' EXIT
    
    # Trap signals
    trap 'log_script_exit SIGINT' SIGINT
    trap 'log_script_exit SIGTERM' SIGTERM
    trap 'log_script_exit SIGHUP' SIGHUP
    
    log_message "DEBUG" "Traps configured for error handling"
}

# ============================================
# OS DETECTION MODULE (EMBEDDED)
# ============================================

# Simple OS detection function
detect_os_type() {
    local kernel_name=$(uname -s)
    
    case "$kernel_name" in
        "Linux")
            OS_TYPE="linux"
            ;;
        "Darwin")
            OS_TYPE="macos"
            ;;
        "CYGWIN"*|"MINGW"*|"MSYS"*)
            OS_TYPE="windows"
            ;;
        *)
            OS_TYPE="unknown"
            if [ -f /proc/version ] && grep -qi "microsoft" /proc/version; then
                OS_TYPE="linux"  # WSL detection
            fi
            ;;
    esac
    
    # Ensure OS_TYPE is exported for all functions
    export OS_TYPE
}

# Initialize OS_TYPE with a default value before detection
OS_TYPE="unknown"

# Quick detection without function call (auto-runs when sourced)
detect_os_type

# ============================================
# CONFIGURATION LOADING FUNCTIONS
# ============================================

# Function to safely source configuration files
safe_source_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log_message "DEBUG" "Config file not found: $config_file"
        return 1
    fi
    
    log_message "DEBUG" "Sourcing configuration from: $config_file"
    
    # Process the config file line by line to fix path issues
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$line" ]] && continue
        
        # Fix $(dirname "$0") references to use SCRIPT_DIR
        if [[ "$line" =~ '\$\(dirname\s*"\$0"\)' ]]; then
            line="${line//\$(dirname \"\$0\")/$SCRIPT_DIR}"
        fi
        
        # Evaluate the line
        eval "$line" 2>/dev/null || log_message "WARNING" "Failed to process config line: $line"
    done < "$config_file"
    
    log_message "DEBUG" "Configuration loaded successfully"
    return 0
}

# ============================================
# GITCLONER HELPER FUNCTIONS
# ============================================

# Print usage information
print_usage() {
    cat << EOF
Usage: $0 [options] [repolist]

GitCloner
===========================
Clones git repositories from a list file to OS-appropriate directories.

Options:
  -d, --dry-run      Preview what would be cloned without actually doing it
  -r, --retries N    Number of retry attempts for failed clones (default: 1)
  -l, --log DIR      Custom log directory (default: ~/.repo_setup/logs)
  -v, --verbose LEVEL  Set verbosity level (0-4, default: 3)
                      0: FATAL only (quiet)
                      1: ERROR and above
                      2: WARNING and above
                      3: INFO and above (normal)
                      4: DEBUG and above (verbose)
  -q, --quiet        Silent mode (equivalent to -v 0)
  -h, --help         Show this help message

Examples:
  $0 repositories.txt                    # Normal operation
  $0 -d repositories.txt                 # Dry run mode
  $0 -v 4 repositories.txt               # Verbose debugging mode
  $0 -v 1 repositories.txt               # Only show errors and above
  $0 -r 3 -v 2 repositories.txt          # 3 retries, show warnings and above
  $0 --dry-run --verbose 4 --retries 2 repositories.txt

EOF
}

# ============================================
# INITIALIZATION FUNCTIONS
# ============================================

# Initialize the setup
initialize_setup() {
    # Log verbosity setting
    log_message "DEBUG" "Verbosity level: $VERBOSITY ($(get_verbosity_description))"
    
    # Detect OS type
    log_message "DEBUG" "Detecting operating system..."
    log_message "DEBUG" "OS Type: ${OS_TYPE:-unknown}"
    
    # Set OS-specific clone directory
    set_os_specific_dirs
    
    # Check for required commands
    check_requirements
    
    # Load configuration
    load_configuration
    
    return 0
}

# Set OS-specific directories
set_os_specific_dirs() {
    local os_type="${OS_TYPE:-unknown}"


    case "$os_type" in
        "linux")
            CLONE_DIR=$(join_paths "${HOME}" "Projects")
            log_message "INFO" "Linux detected, using ${CLONE_DIR} for repositories"
            ;;
        "macos")
            CLONE_DIR=$(join_paths "${HOME}" "Development")
            log_message "INFO" "macOS detected, using ${CLONE_DIR} for repositories"
            ;;
        "windows")
            CLONE_DIR=$(join_paths "${HOME}" "Documents/Git")
            log_message "INFO" "Windows detected, using ${CLONE_DIR} for repositories"
            ;;
        *)
            CLONE_DIR="${DEFAULT_CLONE_DIR}"
            log_message "WARNING" "Unknown OS (${os_type}), using default directory: ${CLONE_DIR}"
            ;;
    esac
    
    # Create clone directory if it doesn't exist
    if [ ! -d "$CLONE_DIR" ]; then
        log_message "INFO" "Creating repository directory: ${CLONE_DIR}"
        mkdir -p "$CLONE_DIR"
        if [ $? -eq 0 ]; then
            log_message "SUCCESS" "Created directory: ${CLONE_DIR}"
        else
            log_message "ERROR" "Failed to create directory: ${CLONE_DIR}"
            return 1
        fi
    fi
}

# Check for required commands
check_requirements() {
    log_message "DEBUG" "Checking system requirements..."
    
    local required_commands="git"
    local missing_commands=""
    local os_type="${OS_TYPE:-unknown}"
    
    for cmd in $required_commands; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_commands="$missing_commands $cmd"
        fi
    done
    
    if [ -n "$missing_commands" ]; then
        log_message "ERROR" "Missing required commands:${missing_commands}"
        
        # Offer to install git based on OS
        case "$os_type" in
            "linux")
                log_message "INFO" "To install git on Linux, run:"
                log_message "INFO" "  Ubuntu/Debian: sudo apt-get install git"
                log_message "INFO" "  CentOS/RHEL: sudo yum install git"
                log_message "INFO" "  Fedora: sudo dnf install git"
                log_message "INFO" "  Arch: sudo pacman -S git"
                ;;
            "macos")
                log_message "INFO" "To install git on macOS:"
                log_message "INFO" "  Option 1: brew install git"
                log_message "INFO" "  Option 2: Download from https://git-scm.com/download/mac"
                ;;
            "windows")
                log_message "INFO" "To install git on Windows:"
                log_message "INFO" "  Download Git for Windows from https://git-scm.com/download/win"
                ;;
            *)
                log_message "INFO" "To install git, visit: https://git-scm.com/downloads"
                ;;
        esac
        
        return 1
    else
        log_message "DEBUG" "All required commands are available"
        log_message "DEBUG" "Git version: $(git --version 2>/dev/null | head -n1)"
        return 0
    fi
}

# Load configuration from file
load_configuration() {
    log_message "INFO" "Loading configuration..."
    
    # Check for config file
    if [ -f "$CONFIG_FILE" ]; then
        log_message "INFO" "Loading configuration from: ${CONFIG_FILE}"
        
        # Safely source the config file with path fixes
        safe_source_config "$CONFIG_FILE"
        
        # Apply configuration overrides for logging
        if [ -n "${MAX_LOG_SIZE_MB_CONFIG:-}" ]; then
            MAX_LOG_SIZE_MB="$MAX_LOG_SIZE_MB_CONFIG"
            log_message "DEBUG" "Using config MAX_LOG_SIZE_MB: $MAX_LOG_SIZE_MB"
        fi
        
        if [ -n "${MAX_LOG_FILES_CONFIG:-}" ]; then
            MAX_LOG_FILES="$MAX_LOG_FILES_CONFIG"
            log_message "DEBUG" "Using config MAX_LOG_FILES: $MAX_LOG_FILES"
        fi
        
        if [ -n "${DEFAULT_CLONE_DIR:-}" ]; then
            CLONE_DIR="${CLONE_DIR}"
            log_message "DEBUG" "Using config CLONE DIR: $DEFAULT_CLONE_DIR"
        fi

        log_message "SUCCESS" "Configuration loaded successfully"
    else
        log_message "INFO" "No configuration file found at ${CONFIG_FILE}, using defaults"
        
        # Create a sample config file
        create_sample_config
    fi
}

# Create a sample configuration file
create_sample_config() {
    cat > "${CONFIG_FILE}.example" << 'EOF'
# ============================================================================
# Gitcloner Configuration File
# ============================================================================

# ============================================
# GENERAL SETTINGS
# ============================================

# Repository file (default: repositories.txt in script directory)
# REPO_LIST_FILE="/path/to/your/repositories.txt"

# Verbosity level: 0=minimal, 1=normal, 2=detailed, 3=debug
# VERBOSITY=1

# Maximum retry attempts for failed clones
# MAX_RETRIES="2"

# Delay between clone attempts (in seconds)
# CLONE_DELAY="3"

# Log directory
# LOG_DIR="/var/log/gitcloner"

# Maximum log file size in MB
# MAX_LOG_SIZE_MB="10"

# Maximum number of log files to keep
# MAX_LOG_FILES="30"

# Log format (simple, detailed, json)
#LOG_FORMAT="detailed"

# ============================================
# REPOSITORY SETTINGS
# ============================================

# Override OS-specific clone directory

# CLONE_DIR="${SCRIPT_DIR}"

# Repository list file (default: repositories.txt in script directory)
# REPO_LIST_FILE=${SCRIPT_DIR}/repositories.txt"

# Repository patterns to exclude (space-separated glob patterns)
# Example: "*test* *demo* *example*"
# EXCLUDE_PATTERNS=""

# Repository patterns to include (if set, only these will be processed)
# INCLUDE_PATTERNS=""

# Validate repository URLs before cloning (true/false)
# VALIDATE_URLS=true

# ============================================
# GIT SETTINGS
# ============================================

# Git user configuration
# GIT_USER_NAME="Your Name"
# GIT_USER_EMAIL="your.email@example.com"

# Git configuration options (space-separated key=value pairs)
# Example: "init.defaultBranch=main pull.rebase=true"
# GIT_CONFIG_OPTIONS="init.defaultBranch=main"

# Default branch to checkout (if not master/main)
# DEFAULT_BRANCH="dev"

# SSH key to use
# SSH_KEY_PATH="${HOME}/.ssh/$env:USERNAME@Github"

# Git protocol preference (ssh, https, or auto)
# GIT_PROTOCOL="auto"

# ============================================
# POST-CLONE ACTIONS
# ============================================

# Run setup.sh if found in repository (true/false)
# RUN_SETUP_SCRIPTS=true

# Run post-clone commands (space-separated)
# Example: "npm install" or "make build"
# POST_CLONE_COMMANDS=""

# Run post-clone commands only for specific patterns
# Example: "*node*:*npm install* *python*:*pip install -r requirements.txt*"
# POST_CLONE_PATTERN_COMMANDS=""

# Set repository permissions (octal, empty to skip)
# REPOSITORY_PERMISSIONS="755"

# ============================================================================
# END OF CONFIGURATION
# ============================================================================
EOF
    
    log_message "INFO" "Sample configuration created: ${CONFIG_FILE}.example"
}

# ============================================
# REPOSITORY FUNCTIONS
# ============================================

# Scan and display current folder contents
scan_current_folder() {
    log_message "DEBUG" "Scanning current working directory..."
    
    local current_dir="$(pwd)"
    log_message "DEBUG" "Current directory: ${current_dir}"
    
    # Count files and directories
    local file_count=$(find . -maxdepth 1 -type f | wc -l)
    local dir_count=$(find . -maxdepth 1 -type d | wc -l)
    local txt_files=$(find . -maxdepth 1 -type f -name "*.txt" 2>/dev/null)
    local txt_count=$(printf '%s\n' "${txt_files}" | grep -c '.' 2>/dev/null || echo "0")

    log_message "DEBUG" "Found ${txt_count} .txt file(s)"
    log_message "DEBUG" "Contents: ${file_count} files, ${dir_count} directories (including .)"
    
    # List files with details (only in verbose mode)
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "Detailed listing:"
        ls -la | while read line; do
            log_message "DEBUG" "  $line"
        done
    fi
    
    # Check for existing git repositories
    local git_repos=$(find . -maxdepth 2 -name ".git" -type d 2>/dev/null | wc -l)
    if [ "$git_repos" -gt 0 ]; then
        log_message "INFO" "Found ${git_repos} git repository(ies) in current directory"
    fi
}

# Read repository list from file
read_repository_list() {
    log_message "INFO" "Reading repository list from: ${REPO_LIST_FILE}"
    
    # Check if repository file exists
    if [ ! -f "$REPO_LIST_FILE" ]; then
        log_message "ERROR" "Repository list file not found: ${REPO_LIST_FILE}"
        log_message "INFO" "Creating sample repository file..."
        create_sample_repo_list
        return 1
    fi
    
    # Count total lines efficiently
    local total_lines=0
    if command -v wc >/dev/null 2>&1; then
        total_lines=$(wc -l < "$REPO_LIST_FILE" 2>/dev/null)
        total_lines=${total_lines// /}
    else
        # Fallback for systems without wc
        while IFS= read -r _; do
            total_lines=$((total_lines + 1))
        done < "$REPO_LIST_FILE"
    fi
    
    if [ "$total_lines" -eq 0 ]; then
        log_message "WARNING" "Repository list file is empty: ${REPO_LIST_FILE}"
        return 1
    fi
    
    # Parse the repository file efficiently
    REPOSITORIES=()
    local line_num=0
    local valid_repos=0
    
    while IFS= read -r line || [ -n "$line" ]; do
        line_num=$((line_num + 1))
        
        # Skip empty lines and comments using shell builtins (no external commands)
        # Remove leading whitespace
        while [[ "$line" == [[:space:]]* ]]; do
            line="${line:1}"
        done
        
        # Skip if empty or starts with #
        [[ -z "$line" || "$line" == "#"* ]] && continue
        
        # Trim trailing whitespace using shell builtin
        while [[ "$line" == *[[:space:]] ]]; do
            line="${line:0:${#line}-1}"
        done
        
        # Parse line: format can be just URL, or URL + custom directory
        # Use shell parameter expansion instead of awk/sed
        local repo_url="$line"
        local custom_dir=""
        
        # Check if line contains whitespace (indicating custom directory)
        if [[ "$line" =~ [[:space:]] ]]; then
            # Extract first field (URL)
            repo_url="${line%%[[:space:]]*}"
            
            # Extract everything after first whitespace (custom directory)
            custom_dir="${line#*[[:space:]]}"
            
            # Trim any extra whitespace from custom_dir
            while [[ "$custom_dir" == [[:space:]]* ]]; do
                custom_dir="${custom_dir:1}"
            done
            while [[ "$custom_dir" == *[[:space:]] ]]; do
                custom_dir="${custom_dir:0:${#custom_dir}-1}"
            done
        fi
        
        # Validate URL format
        if [[ "$repo_url" =~ ^(https?|git|ssh):// ]] || [[ "$repo_url" =~ ^git@ ]]; then
            REPOSITORIES+=("$repo_url|$custom_dir")
            valid_repos=$((valid_repos + 1))
            log_message "DEBUG" "Valid repository ${valid_repos}: ${repo_url}"
        else
            log_message "WARNING" "Invalid repository URL on line ${line_num}: ${repo_url}"
        fi
    done < "$REPO_LIST_FILE"
    
    if [ "$valid_repos" -eq 0 ]; then
        log_message "ERROR" "No valid repositories found in ${REPO_LIST_FILE}"
        return 1
    fi
    
    log_message "SUCCESS" "Successfully parsed ${valid_repos} valid repositories"
    return 0
}

# Create a sample repository list file
create_sample_repo_list() {
    cat > "$REPO_LIST_FILE" << 'EOF'
# Repository List File
# ====================
# Format: <repository_url> [optional_custom_directory]
# One repository per line
# Lines starting with # are comments

# Example repositories:
https://github.com/torvalds/linux.git linux-kernel
https://github.com/git/git.git git-source

# SSH format (requires SSH key setup):
# git@github.com:username/repository.git custom-folder

# More examples:
# https://github.com/docker/docker-ce.git
# https://github.com/kubernetes/kubernetes.git k8s-source
EOF
    
    log_message "SUCCESS" "Created sample repository list: ${REPO_LIST_FILE}"
    log_message "INFO" "Please edit this file with your repository URLs and run the script again"
}

# Clone a single repository
clone_repository() {
    local repo_info="$1"
    local repo_url=$(echo "$repo_info" | cut -d'|' -f1)
    local custom_dir=$(echo "$repo_info" | cut -d'|' -f2)
    
    # Extract repository name from URL
    local repo_name=$(basename "$repo_url" .git)
    
    # Determine target directory
    local target_dir=""
    if [ -n "$custom_dir" ]; then
        target_dir=$(join_paths "${CLONE_DIR}" "${custom_dir}")
    else
        target_dir=$(join_paths "${CLONE_DIR}" "${repo_name}")
    fi
    
    log_message "INFO" "Processing repository: ${repo_name}"
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "  URL: ${repo_url}"
        log_message "DEBUG" "  Target: ${target_dir}"
    fi
    
    # Check if directory already exists
    if [ -d "$target_dir" ]; then
        log_message "WARNING" "Directory already exists: ${target_dir}"
        
        # Check if it's already a git repository
        if [ -d "${target_dir}/.git" ]; then
            log_message "INFO" "Git repository already exists, checking for updates..."
            
            # Try to update existing repository
            update_existing_repo "$target_dir" "$repo_url"
            return $?
        else
            log_message "WARNING" "Directory exists but is not a git repository"
            
            # Ask for confirmation to overwrite (if interactive and not in quiet mode)
            if [ -t 0 ] && [ "$VERBOSITY" -ge 2 ]; then
                read -p "Overwrite directory? (y/N): " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    log_message "INFO" "Skipping repository: ${repo_name}"
                    return 2
                fi
            fi
            
            # Backup existing directory
            local backup_dir="${target_dir}.backup.$(date +%Y%m%d_%H%M%S)"
            log_message "INFO" "Backing up existing directory to: ${backup_dir}"
            mv "$target_dir" "$backup_dir" 2>/dev/null
        fi
    fi
    
    # Create parent directory if needed
    local parent_dir=$(dirname "$target_dir")
    if [ ! -d "$parent_dir" ]; then
        mkdir -p "$parent_dir"
        log_message "DEBUG" "Created parent directory: ${parent_dir}"
    fi
    
    # Clone the repository with retry logic
    log_message "INFO" "Cloning repository to: ${target_dir}"
    
    local clone_success=false
    local attempt=1
    local max_attempts="${MAX_RETRIES:-1}"
    
    while [ $attempt -le $max_attempts ]; do
        if [ $attempt -gt 1 ]; then
            log_message "INFO" "Retry attempt $attempt of $max_attempts in ${RETRY_DELAY:-1} seconds..."
            sleep "${RETRY_DELAY:-1}"
        fi
        
        if git clone "$repo_url" "$target_dir" 2>&1 | tee -a "$LOG_FILE"; then
            clone_success=true
            break
        else
            log_message "WARNING" "Clone attempt $attempt failed for: ${repo_name}"
            attempt=$((attempt + 1))
        fi
    done
    
    if [ "$clone_success" = true ]; then
        log_message "SUCCESS" "Successfully cloned: ${repo_name}"
        
        # Additional repository setup
        setup_repository "$target_dir"
        
        return 0
    else
        log_message "ERROR" "Failed to clone repository after ${max_attempts} attempts: ${repo_name}"
        if [ "$VERBOSITY" -ge 4 ]; then
            log_message "DEBUG" "Clone command failed: git clone ${repo_url} ${target_dir}"
        fi
        
        # Clean up failed clone directory
        if [ -d "$target_dir" ]; then
            rm -rf "$target_dir"
            log_message "DEBUG" "Cleaned up failed clone directory: ${target_dir}"
        fi
        
        return 1
    fi
}

# Update an existing git repository
update_existing_repo() {
    local repo_dir="$1"
    local repo_url="$2"
    
    log_message "INFO" "Updating existing repository: ${repo_dir}"
    
    # Check current remote URL
    local current_url=$(cd "$repo_dir" && git remote get-url origin 2>/dev/null)
    
    if [ "$current_url" != "$repo_url" ]; then
        log_message "WARNING" "Remote URL mismatch:"
        log_message "WARNING" "  Expected: ${repo_url}"
        log_message "WARNING" "  Current:  ${current_url}"
        
        # Update remote URL if different
        if [ -t 0 ] && [ "$VERBOSITY" -ge 2 ]; then
            read -p "Update remote URL? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                (cd "$repo_dir" && git remote set-url origin "$repo_url")
                log_message "INFO" "Updated remote URL to: ${repo_url}"
            fi
        fi
    fi
    
    # Pull latest changes
    log_message "INFO" "Pulling latest changes..."
    
    # Try main branch first
    if (cd "$repo_dir" && git pull origin main 2>&1 | tee -a "$LOG_FILE"; test ${PIPESTATUS[0]} -eq 0); then
        log_message "SUCCESS" "Repository updated successfully from main branch"
        return 0
    fi
    
    # Try master branch if main failed
    if (cd "$repo_dir" && git pull origin master 2>&1 | tee -a "$LOG_FILE"; test ${PIPESTATUS[0]} -eq 0); then
        log_message "SUCCESS" "Repository updated successfully from master branch"
        return 0
    fi
    
    # Both attempts failed
    log_message "ERROR" "Failed to update repository from both main and master branches"
    
    # Check if there are uncommitted changes
    local uncommitted=$(cd "$repo_dir" && git status --porcelain 2>/dev/null | wc -l)
    if [ "$uncommitted" -gt 0 ]; then
        log_message "WARNING" "Repository has ${uncommitted} uncommitted changes"
        
        if [ -t 0 ] && [ "$VERBOSITY" -ge 2 ]; then
            read -p "Stash changes and pull? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                (cd "$repo_dir" && git stash && git pull origin main && git stash pop 2>/dev/null || 
                 cd "$repo_dir" && git stash && git pull origin master && git stash pop 2>/dev/null)
                log_message "INFO" "Stashed changes, pulled, and reapplied changes"
            fi
        fi
    fi
    
    return 1
}

# Additional repository setup
setup_repository() {
    local repo_dir="$1"
    
    log_message "DEBUG" "Performing additional repository setup..."
    
    # Check if there's a setup script
    if [ -f "${repo_dir}/setup.sh" ]; then
        log_message "INFO" "Found setup.sh, executing..."
        
        if (cd "$repo_dir" && chmod +x setup.sh && ./setup.sh 2>&1 | tee -a "$LOG_FILE"); then
            log_message "SUCCESS" "Repository setup script executed successfully"
        else
            log_message "WARNING" "Repository setup script failed or had warnings"
        fi
    fi
    
    # Check for README
    local readme_file=$(find "$repo_dir" -maxdepth 1 -iname "readme*" | head -1)
    if [ -n "$readme_file" ] && [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "Repository has README: $(basename "$readme_file")"
    fi
}

# Process all repositories
process_all_repositories() {
    
    local success_count=0
    local skip_count=0
    local fail_count=0
    local total_count=${#REPOSITORIES[@]}
    
    # Process each repository
    for repo_info in "${REPOSITORIES[@]}"; do
        clone_repository "$repo_info"
        local result=$?
        
        case $result in
            0)  # Success
                success_count=$((success_count + 1))
                ;;
            1)  # Failure
                fail_count=$((fail_count + 1))
                ;;
            2)  # Skipped
                skip_count=$((skip_count + 1))
                ;;
        esac
        
        # Small delay between clones to be nice to the server
        sleep 1
    done
    
    # Summary
    log_message "SUCCESS" "Successfully cloned: ${success_count} repositories"
    
    if [ "$skip_count" -gt 0 ]; then
        log_message "WARNING" "Skipped: ${skip_count} repositories"
    fi
    
    if [ "$fail_count" -gt 0 ]; then
        log_message "ERROR" "Failed: ${fail_count} repositories"
    fi
    
    log_message "INFO" "Total processed: ${total_count} repositories"
    
    # Return non-zero if any failures occurred
    if [ "$fail_count" -gt 0 ]; then
        return 1
    else
        return 0
    fi
}

# ============================================
# FINAL SUMMARY FUNCTION
# ============================================

# Generate comprehensive final summary report
generate_final_summary() {
    local summary_separator="================================================================================"
    local separator_length=${#summary_separator}
    
    # Calculate total repositories processed from main variables (if available)
    local total_repos="${#REPOSITORIES[@]}"
    local processed_count=0
    local success_count=0
    local failed_count=0
    local skipped_count=0
    
    # Try to count directories in CLONE_DIR as a proxy for success count
    if [ -d "$CLONE_DIR" ]; then
        success_count=$(find "$CLONE_DIR" -maxdepth 1 -type d ! -name "$(basename "$CLONE_DIR")" 2>/dev/null | wc -l)
        processed_count=$success_count
    fi
    

    clear

    log_message "INFO" "$summary_separator"
    log_message "INFO" "                       GIT CLONER - EXECUTION SUMMARY"
    log_message "INFO" "$summary_separator"
    
    # Basic script info
    log_message "INFO" "SCRIPT EXECUTION DETAILS:"
    log_message "INFO" "  Script Name:    ${SCRIPT_NAME}"
    log_message "INFO" "  Executed by:    $(whoami)"
    log_message "INFO" "  Execution Time: $(date '+%Y-%m-%d %H:%M:%S %Z')"
    log_message "INFO" "  Script Version: 1.0"
    log_message "INFO" "  OS Type:        ${OS_TYPE:-unknown}"
    log_message "INFO" ""
    
    # Repository processing summary
    log_message "INFO" "REPOSITORY PROCESSING SUMMARY:"
    log_message "INFO" "  Source File:    ${REPO_LIST_FILE}"
    log_message "INFO" "  Total Listed:   ${total_repos} repository(ies)"
    log_message "INFO" "  Processed:      ${processed_count} repository(ies)"

    if [ $success_count -gt 0 ]; then
        log_message "INFO" "  Successfully:   ${success_count} repository(ies)"
    fi
    
    if [ ${failed_count:-0} -gt 0 ]; then
        log_message "INFO" "  Failed:         ${failed_count} repository(ies)"
    fi
    
    if [ ${skipped_count:-0} -gt 0 ]; then
        log_message "INFO" "  Skipped:        ${skipped_count} repository(ies)"
    fi
    
    log_message "INFO" ""
    
    # Directory structure info
    log_message "INFO" "DIRECTORY STRUCTURE:"
    log_message "INFO" "  Source Script:  ${SCRIPT_DIR}/"
    log_message "INFO" "  Clone Target:   ${CLONE_DIR}/"
    
    # Show clone directory contents
    if [ -d "$CLONE_DIR" ]; then
        local dir_count=$(find "$CLONE_DIR" -maxdepth 1 -type d 2>/dev/null | wc -l)
        local file_count=$(find "$CLONE_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l)
        
        # Subtract 1 for the directory itself
        dir_count=$((dir_count - 1))
        
        log_message "INFO" "  Contents:       ${dir_count} director(ies)"
        
        # Show directory listing in verbose mode
        if [ "$VERBOSITY" -ge 4 ]; then
            log_message "INFO" "  Directory Listing:"
            
            # Check if tree command is available for prettier output
            if command -v tree >/dev/null 2>&1 && [ "$VERBOSITY" -ge 4 ]; then
                # Use tree for detailed view in debug mode
                tree -L 2 "$CLONE_DIR" 2>/dev/null | while IFS= read -r line; do
                    log_message "DEBUG" "    $line"
                done
            else
                # Simple ls output
                ls -la "$CLONE_DIR" 2>/dev/null | while IFS= read -r line; do
                    log_message "INFO" "    $line"
                done
            fi
        fi
    else
        log_message "WARNING" "  Clone directory does not exist: ${CLONE_DIR}"
    fi
    
    log_message "INFO" ""
    
    # Logging info
    log_message "INFO" "LOGGING INFORMATION:"
    log_message "INFO" "  Main Log File:  ${LOG_FILE}"
    log_message "INFO" "  Error Log:      ${ERROR_LOG_FILE}"
    log_message "INFO" "  Log Directory:  ${LOG_DIR}"
    log_message "INFO" "  Verbosity:      Level ${VERBOSITY} ($(get_verbosity_description))"
    log_message "INFO" ""
    
    # System info (debug mode only)
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "SYSTEM INFORMATION:"
        log_message "DEBUG" "  Bash Version:   ${BASH_VERSION}"
        log_message "DEBUG" "  Git Version:    $(git --version 2>/dev/null || echo "Not available")"
        log_message "DEBUG" "  Disk Usage:     $(df -h "$CLONE_DIR" 2>/dev/null | tail -1 || echo "Not available")"
        log_message "DEBUG" ""
    fi
    
    # Final status message
    if [ ${failed_count:-0} -eq 0 ] && [ $success_count -gt 0 ]; then
        log_message "SUCCESS" "✅ SUCCESS: All repositories processed successfully!"
    elif [ ${failed_count:-0} -gt 0 ]; then
        log_message "WARNING" "⚠️  WARNING: Some repositories failed to process. Check error log for details."
    elif [ $processed_count -eq 0 ]; then
        log_message "INFO" "ℹ️  INFO: No repositories were processed."
    fi
    
    log_message "INFO" "$summary_separator"
    
    # Reminder for next steps (info mode and above)
    if [ "$VERBOSITY" -ge 2 ]; then
        log_message "INFO" "NEXT STEPS:"
        log_message "INFO" "  1. Check individual repositories in: ${CLONE_DIR}/"
        log_message "INFO" "  2. Review detailed logs in: ${LOG_DIR}/"
        log_message "INFO" "  3. Update repository list in: ${REPO_LIST_FILE}"
        
        if [ -f "${CONFIG_FILE}.example" ] && [ ! -f "$CONFIG_FILE" ]; then
            log_message "INFO" "  4. Customize settings by copying: ${CONFIG_FILE}.example -> ${CONFIG_FILE}"
        fi
        
        log_message "INFO" ""
    fi
    
    # Provide command for quick navigation (debug mode only)
    if [ "$VERBOSITY" -ge 4 ] && [ -d "$CLONE_DIR" ]; then
        log_message "DEBUG" "QUICK NAVIGATION COMMANDS:"
        log_message "DEBUG" "  cd ${CLONE_DIR} && ls -la"
        log_message "DEBUG" "  tail -f ${LOG_FILE}"
        log_message "DEBUG" ""
    fi
    
    # Final timing note
    log_message "INFO" "Script execution completed at: $(date '+%H:%M:%S')"
    log_message "INFO" "$summary_separator"
    
    return 0
}

# ============================================
# Main Script Execution
# ============================================

# Parse command line options
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--retries)
            MAX_RETRIES="$2"
            shift 2
            ;;
        -l|--log)
            LOG_DIR="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSITY="$2"
            shift 2
            ;;
        -q|--quiet)
            VERBOSITY=0
            shift
            ;;
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
            # If it's a file, use it as repo list
            if [ -f "$1" ]; then
                REPO_LIST_FILE="$1"
            else
                # Otherwise treat as username (for backward compatibility)
                USERNAME="$1"
            fi
            shift
            ;;
    esac
done

# ============================================
# MAIN EXECUTION
# ============================================

main() {
    # Initialize logging (from logging.sh)
    if ! init_logging; then
        echo "ERROR: Failed to initialize logging system"
        exit 1
    fi

    # Set verbosity in logging module before initialization
    set_verbosity "$VERBOSITY"
    
    
    # Setup error traps (from logging.sh)
    setup_traps
    
    # Log script start with verbosity info
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "Verbosity level: $VERBOSITY ($(get_verbosity_description))"
    fi
    
    # Initialize the setup
    if ! initialize_setup; then
        log_message "ERROR" "Initialization failed"
        exit 1
    fi
    
    # Scan current folder
    scan_current_folder
    
    # Read repository list
    if ! read_repository_list; then
        log_message "ERROR" "Failed to read repository list"
        exit 1
    fi
    
    # Process all repositories
    if ! process_all_repositories; then
        log_message "WARNING" "Some repositories failed to clone"
    fi
    
    # Final summary
    generate_final_summary
    
    # Final directory listing (only in debug mode for brevity)
    if [ "$VERBOSITY" -ge 4 ]; then
        log_message "DEBUG" "Quick directory listing of ${CLONE_DIR}:"
        if [ -d "$CLONE_DIR" ]; then
            ls -la "$CLONE_DIR" 2>/dev/null | while IFS= read -r line; do
                log_message "DEBUG" "  $line"
            done
        fi
    fi
}

# Run main function
main "$@"