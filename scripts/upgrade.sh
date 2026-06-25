#!/bin/bash

##############################################################################
# routatic-proxy Auto-Upgrade Script
# 
# This script automatically upgrades the routatic-proxy service to the
# latest version while preserving your configuration.
#
# Usage: ./scripts/upgrade.sh
#        ./scripts/upgrade.sh --force    (skip safety checks)
#        ./scripts/upgrade.sh --dry-run  (preview changes without applying)
##############################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;36m'
NC='\033[0m' # No Color

# Config
BINARY_NAME="routatic-proxy"
LEGACY_BINARY_NAME="oc-go-cc"
SERVICE_PORT="3456"
CONFIG_DIR="$HOME/.config/routatic-proxy"
LEGACY_CONFIG_DIR="$HOME/.config/oc-go-cc"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOG_FILE="/tmp/routatic-proxy-upgrade-$(date +%Y%m%d-%H%M%S).log"

# Flags
DRY_RUN=false
FORCE_UPGRADE=false

##############################################################################
# Helper Functions
##############################################################################

log_info() {
    echo -e "${BLUE}ℹ${NC}  $*" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}✓${NC}  $*" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC}  $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}✗${NC}  $*" | tee -a "$LOG_FILE"
}

print_header() {
    echo -e "\n${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

print_section() {
    echo -e "\n${BLUE}──────────────────────────────────────────────────────${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}──────────────────────────────────────────────────────${NC}\n"
}

##############################################################################
# Argument Parsing
##############################################################################

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            log_warning "DRY RUN MODE - No changes will be applied"
            shift
            ;;
        --force)
            FORCE_UPGRADE=true
            log_warning "FORCE MODE - Skipping safety checks"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run    Preview changes without applying them"
            echo "  --force      Skip safety checks and proceed"
            echo "  --help       Show this help message"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

##############################################################################
# Pre-flight Checks
##############################################################################

print_header "ROUTATIC-PROXY AUTO-UPGRADE"

log_info "Upgrade log: $LOG_FILE"
log_info "Starting pre-flight checks..."

# Check if routatic-proxy is installed
if ! command -v $BINARY_NAME &> /dev/null; then
    log_error "$BINARY_NAME is not installed or not in PATH"
    echo "Install it first with: brew install routatic-proxy (macOS/Linux)"
    echo "                    or: scoop install routatic-proxy (Windows)"
    exit 1
fi

# Get current version
CURRENT_VERSION=$($BINARY_NAME --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
log_success "Current version: $CURRENT_VERSION"

# Check if service is running
print_section "Service Status Check"
if $BINARY_NAME status &> /dev/null 2>&1; then
    log_warning "Service is currently running on port $SERVICE_PORT"
    SERVICE_RUNNING=true
else
    log_info "Service is not running"
    SERVICE_RUNNING=false
fi

# Check for configuration backups
print_section "Configuration Backup"
if [ -d "$CONFIG_DIR" ]; then
    BACKUP_DIR="$CONFIG_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    log_info "Found existing config at: $CONFIG_DIR"
    log_info "Will backup to: $BACKUP_DIR"
elif [ -d "$LEGACY_CONFIG_DIR" ]; then
    BACKUP_DIR="$LEGACY_CONFIG_DIR.backup.$(date +%Y%m%d-%H%M%S)"
    log_info "Found legacy config at: $LEGACY_CONFIG_DIR"
    log_info "Will backup to: $BACKUP_DIR"
else
    log_warning "No configuration directory found (first run?)"
    BACKUP_DIR=""
fi

# Check Go installation (if building from source)
if [ ! -d "$PROJECT_DIR/.git" ] && command -v go &> /dev/null; then
    GO_VERSION=$(go version | awk '{print $3}')
    log_success "Go compiler found: $GO_VERSION"
fi

##############################################################################
# Upgrade Selection
##############################################################################

print_section "Upgrade Method Detection"

# Detect installation method
INSTALL_METHOD="unknown"

if command -v brew &> /dev/null; then
    FORMULA_PATH=$(brew --cellar $BINARY_NAME 2>/dev/null | head -1 || echo "")
    if [ -d "$FORMULA_PATH" ]; then
        INSTALL_METHOD="homebrew"
        log_success "Installation method: Homebrew"
    fi
fi

if [ "$INSTALL_METHOD" = "unknown" ] && [ -d "$PROJECT_DIR/.git" ]; then
    INSTALL_METHOD="source"
    log_success "Installation method: Source (Git repository)"
fi

if [ "$INSTALL_METHOD" = "unknown" ]; then
    INSTALL_METHOD="binary"
    log_warning "Installation method: Binary (location unknown)"
fi

##############################################################################
# Dry-Run Preview
##############################################################################

if [ "$DRY_RUN" = true ]; then
    print_section "DRY-RUN: Upgrade Plan"
    
    case $INSTALL_METHOD in
        homebrew)
            echo "1. Run: brew update"
            echo "2. Run: brew upgrade $BINARY_NAME"
            ;;
        source)
            echo "1. Change to: $PROJECT_DIR"
            echo "2. Run: git pull origin main"
            echo "3. Run: go build -o bin/$BINARY_NAME ./cmd/routatic-proxy"
            echo "4. Run: cp bin/$BINARY_NAME \$GOPATH/bin/ or \$HOME/go/bin/"
            ;;
        binary)
            echo "Cannot determine binary location for automatic upgrade"
            echo "Please manually download the latest release from:"
            echo "https://github.com/routatic/proxy/releases"
            ;;
    esac
    
    if [ "$SERVICE_RUNNING" = true ]; then
        echo ""
        echo "Service Actions:"
        echo "1. Run: $BINARY_NAME stop"
        echo "2. [Upgrade binary]"
        echo "3. Run: $BINARY_NAME serve"
    fi
    
    if [ -n "$BACKUP_DIR" ]; then
        echo ""
        echo "Configuration:"
        echo "1. Backup: cp -r $CONFIG_DIR $BACKUP_DIR"
    fi
    
    echo ""
    log_success "Dry-run complete. Run without --dry-run to apply changes."
    exit 0
fi

##############################################################################
# User Confirmation
##############################################################################

if [ "$FORCE_UPGRADE" = false ]; then
    print_section "Confirmation Required"
    
    echo "This script will:"
    echo ""
    
    if [ "$SERVICE_RUNNING" = true ]; then
        echo "  1. Stop the running $BINARY_NAME service"
    fi
    
    case $INSTALL_METHOD in
        homebrew)
            echo "  2. Update and upgrade $BINARY_NAME via Homebrew"
            ;;
        source)
            echo "  2. Pull latest changes from Git repository"
            echo "  3. Build the new version"
            echo "  4. Install to your PATH"
            ;;
        binary)
            echo "  2. Unable to upgrade - binary location unknown"
            echo "     Please download manually from GitHub releases"
            exit 1
            ;;
    esac
    
    if [ -n "$BACKUP_DIR" ]; then
        echo "  5. Create backup of configuration"
    fi
    
    if [ "$SERVICE_RUNNING" = true ]; then
        echo "  6. Restart the $BINARY_NAME service"
    fi
    
    echo ""
    read -p "Continue with upgrade? (yes/no) " -n 3 -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        log_warning "Upgrade cancelled by user"
        exit 0
    fi
fi

##############################################################################
# Execution
##############################################################################

print_header "EXECUTING UPGRADE"

# Step 1: Backup Configuration
if [ -n "$BACKUP_DIR" ]; then
    print_section "Step 1: Backing Up Configuration"
    if [ -d "$CONFIG_DIR" ]; then
        cp -r "$CONFIG_DIR" "$BACKUP_DIR"
        log_success "Configuration backed up to: $BACKUP_DIR"
    elif [ -d "$LEGACY_CONFIG_DIR" ]; then
        cp -r "$LEGACY_CONFIG_DIR" "$BACKUP_DIR"
        log_success "Legacy configuration backed up to: $BACKUP_DIR"
    fi
fi

# Step 2: Stop Service
print_section "Step 2: Stopping Service"
if [ "$SERVICE_RUNNING" = true ]; then
    log_info "Attempting to stop $BINARY_NAME service..."
    if $BINARY_NAME stop &> /dev/null 2>&1; then
        log_success "Service stopped successfully"
    else
        log_warning "Could not stop service via 'stop' command"
        log_info "Attempting to kill process on port $SERVICE_PORT..."
        if command -v lsof &> /dev/null; then
            PID=$(lsof -ti :$SERVICE_PORT)
            if [ -n "$PID" ]; then
                kill -9 "$PID" 2>/dev/null || true
                sleep 1
                log_success "Process killed (PID: $PID)"
            fi
        fi
    fi
    
    # Verify port is free
    sleep 2
    if lsof -i :$SERVICE_PORT &> /dev/null 2>&1; then
        log_error "Port $SERVICE_PORT is still in use. Manual intervention required."
        exit 1
    fi
    log_success "Port $SERVICE_PORT is now free"
else
    log_info "Service is not running, skipping stop"
fi

# Step 3: Upgrade Binary
print_section "Step 3: Upgrading Binary"

case $INSTALL_METHOD in
    homebrew)
        log_info "Running: brew update"
        brew update | tee -a "$LOG_FILE"
        
        log_info "Running: brew upgrade $BINARY_NAME"
        brew upgrade $BINARY_NAME | tee -a "$LOG_FILE"
        ;;
        
    source)
        log_info "Changing to project directory: $PROJECT_DIR"
        cd "$PROJECT_DIR"
        
        log_info "Running: git pull origin main"
        git pull origin main | tee -a "$LOG_FILE"
        
        log_info "Building new version..."
        make build 2>&1 | tee -a "$LOG_FILE"
        
        log_info "Installing to PATH..."
        make install 2>&1 | tee -a "$LOG_FILE"
        ;;
esac

# Step 4: Verify Installation
print_section "Step 4: Verifying Installation"
if command -v $BINARY_NAME &> /dev/null; then
    NEW_VERSION=$($BINARY_NAME --version 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
    log_success "New version: $NEW_VERSION"
    
    if [ "$CURRENT_VERSION" != "$NEW_VERSION" ]; then
        log_success "Successfully upgraded from $CURRENT_VERSION to $NEW_VERSION"
    else
        log_warning "Version appears unchanged (may be normal for development builds)"
    fi
else
    log_error "Binary not found after upgrade. Something went wrong."
    exit 1
fi

# Step 5: Restart Service
print_section "Step 5: Restarting Service"
if [ "$SERVICE_RUNNING" = true ]; then
    log_info "Starting service on port $SERVICE_PORT..."
    sleep 1
    
    # Start in background
    $BINARY_NAME serve -b &> /tmp/routatic-proxy.log &
    SERVE_PID=$!
    
    sleep 3
    
    # Verify it's running
    if $BINARY_NAME status &> /dev/null 2>&1; then
        log_success "Service started successfully (PID: $SERVE_PID)"
    else
        log_error "Service failed to start. Check logs:"
        cat /tmp/routatic-proxy.log | tee -a "$LOG_FILE"
        exit 1
    fi
else
    log_info "Service was not running before upgrade, skipping restart"
fi

##############################################################################
# Summary
##############################################################################

print_header "UPGRADE COMPLETE ✓"

log_success "routatic-proxy has been successfully upgraded!"
echo ""
echo "Summary:"
echo "  Version upgraded: $CURRENT_VERSION → $NEW_VERSION"
echo "  Installation method: $INSTALL_METHOD"

if [ -n "$BACKUP_DIR" ]; then
    echo "  Configuration backup: $BACKUP_DIR"
fi

if [ "$SERVICE_RUNNING" = true ]; then
    echo "  Service status: Running ✓"
    echo "  Proxy URL: http://127.0.0.1:$SERVICE_PORT"
fi

echo ""
echo "Next steps:"
echo "  1. Verify Claude Code still works:"
echo "     export ANTHROPIC_BASE_URL=http://127.0.0.1:$SERVICE_PORT"
echo "     export ANTHROPIC_AUTH_TOKEN=unused"
echo "     claude"
echo ""
echo "  2. To view upgrade logs: cat $LOG_FILE"
echo ""

if [ -n "$BACKUP_DIR" ]; then
    echo "  3. To restore from backup (if needed):"
    echo "     rm -rf ~/.config/routatic-proxy"
    echo "     cp -r $BACKUP_DIR ~/.config/routatic-proxy"
    echo ""
fi

log_success "Upgrade completed at $(date)"
