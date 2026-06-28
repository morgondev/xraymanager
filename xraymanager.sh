#!/bin/bash
# ============================================================
#  Xray PR Build Manager
#  Installs custom Xray-core with PR #5844 (UserConnTracker)
#  Supports: PasarGuard Node | 3X-UI | Marzban | Marzneshin
#  by Meysam
# ============================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Common settings
GO_VERSION="1.26.1"
PR_REPO="https://github.com/ImMohammad20000/Xray-core.git"
PR_BRANCH="UserConnTracker"
PR_COMMIT_HASH="95b1321"
XRAY_SOURCE_DIR="/root/Xray-core"

# PasarGuard settings
PG_NODE_DIR="/opt/pg-node"
PG_COMPOSE_FILE="$PG_NODE_DIR/docker-compose.yml"
PG_BACKUP_DIR="/opt/pg-node-backups"
PG_XRAY_DIR="/opt/pasarguard-xray"
PG_XRAY_BIN="$PG_XRAY_DIR/xray"
PG_CONTAINER_NAME="node"

# 3X-UI settings
XUI_DIR="/usr/local/x-ui"
XUI_BIN_DIR="$XUI_DIR/bin"
XUI_BACKUP_DIR="/opt/x-ui-backups"
XUI_SERVICE="x-ui"
XUI_XRAY_BIN=""

# Marzban settings
MZ_DIR="/opt/marzban"
MZ_COMPOSE_FILE="$MZ_DIR/docker-compose.yml"
MZ_ENV_FILE="$MZ_DIR/.env"
MZ_DATA_DIR="/var/lib/marzban"
MZ_XRAY_DIR="$MZ_DATA_DIR/xray-core"
MZ_XRAY_BIN="$MZ_XRAY_DIR/xray"
MZ_BACKUP_DIR="/opt/marzban-backups"
MZ_CONTAINER_NAME="marzban-marzban-1"

# Marzneshin settings
MN_DIR="/etc/opt/marzneshin"
MN_COMPOSE_FILE="$MN_DIR/docker-compose.yml"
MN_DATA_DIR="/var/lib/marznode"
MN_XRAY_BIN="$MN_DATA_DIR/xray"
MN_BACKUP_DIR="/opt/marzneshin-backups"
MN_NODE_CONTAINER="marzneshin-marznode-1"

# Detected docker compose command
DOCKER_COMPOSE_CMD=""

# ============================================================
# Helpers
# ============================================================
print_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    echo "============================================================"
    echo "    Xray PR Build Manager (PR #5844 - UserConnTracker)"
    echo "    Supports: PasarGuard | 3X-UI | Marzban | Marzneshin"
    echo -e "    By - ${RED}Meysam${CYAN}${BOLD}"
    echo -e "    Telegram Channel: ${RED}@morgondev${CYAN}${BOLD}"
    echo "============================================================"
    echo -e "${NC}"
}

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_error()   { echo -e "${RED}[FAIL]${NC} $1"; }
print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_step()    { echo -e "\n${CYAN}${BOLD}>>> $1${NC}"; }

press_enter() {
    echo ""
    read -p "Press Enter to continue..." dummy
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "Please run this script as root"
        exit 1
    fi
}

get_go_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "arm" ;;
        *)       echo "amd64" ;;
    esac
}

detect_xui_arch() {
    local arch=$(uname -m)
    case "$arch" in
        x86_64)  XUI_XRAY_BIN="$XUI_BIN_DIR/xray-linux-amd64" ;;
        aarch64) XUI_XRAY_BIN="$XUI_BIN_DIR/xray-linux-arm64-v8a" ;;
        armv7l)  XUI_XRAY_BIN="$XUI_BIN_DIR/xray-linux-arm32-v7a" ;;
        *)
            print_error "Unsupported architecture: $arch"
            return 1
            ;;
    esac

    if [ ! -f "$XUI_XRAY_BIN" ] && [ -d "$XUI_BIN_DIR" ]; then
        local found=$(ls "$XUI_BIN_DIR"/xray-linux-* 2>/dev/null | head -1)
        [ -n "$found" ] && XUI_XRAY_BIN="$found"
    fi
    return 0
}

detect_compose_cmd() {
    if docker compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker compose"
        return 0
    elif command -v docker-compose &> /dev/null && docker-compose version &> /dev/null; then
        DOCKER_COMPOSE_CMD="docker-compose"
        return 0
    fi
    return 1
}

# Auto-detect which panels are present on this server
# Sets global variables: PANEL_PG, PANEL_XUI, PANEL_MZ, PANEL_MN
auto_detect_panels() {
    PANEL_PG=0; PANEL_XUI=0; PANEL_MZ=0; PANEL_MN=0

    [ -f "$PG_COMPOSE_FILE" ] && PANEL_PG=1
    [ -d "$XUI_DIR" ] && systemctl list-unit-files 2>/dev/null | grep -q "^${XUI_SERVICE}.service" && PANEL_XUI=1
    [ -f "$MZ_COMPOSE_FILE" ] && PANEL_MZ=1
    [ -f "$MN_COMPOSE_FILE" ] && PANEL_MN=1
}

# Ask user to choose panel; auto-pick if only one is present
select_panel() {
    auto_detect_panels

    local detected=()
    [ "$PANEL_PG"  == "1" ] && detected+=("pg")
    [ "$PANEL_XUI" == "1" ] && detected+=("xui")
    [ "$PANEL_MZ"  == "1" ] && detected+=("mz")
    [ "$PANEL_MN"  == "1" ] && detected+=("mn")

    # If only one panel is detected, use it without asking
    if [ "${#detected[@]}" -eq 1 ]; then
        echo "${detected[0]}"
        return
    fi

    # Otherwise ask
    local tag
    >&2 echo ""
    >&2 echo -e "${BOLD}Select Panel:${NC}"
    >&2 echo ""

    tag=$( [ "$PANEL_PG"  == "1" ] && echo "${GREEN}[detected]${NC}" || echo "${RED}[not detected]${NC}" )
    >&2 echo -e "  ${GREEN}1${NC}) PasarGuard Node  $tag"

    tag=$( [ "$PANEL_XUI" == "1" ] && echo "${GREEN}[detected]${NC}" || echo "${RED}[not detected]${NC}" )
    >&2 echo -e "  ${YELLOW}2${NC}) 3X-UI / Sanaei   $tag"

    tag=$( [ "$PANEL_MZ"  == "1" ] && echo "${GREEN}[detected]${NC}" || echo "${RED}[not detected]${NC}" )
    >&2 echo -e "  ${BLUE}3${NC}) Marzban           $tag"

    tag=$( [ "$PANEL_MN"  == "1" ] && echo "${GREEN}[detected]${NC}" || echo "${RED}[not detected]${NC}" )
    >&2 echo -e "  ${CYAN}4${NC}) Marzneshin        $tag"

    >&2 echo -e "  ${RED}0${NC}) Back"
    >&2 echo ""
    read -p "Choose panel: " panel_choice >&2
    case $panel_choice in
        1) echo "pg" ;;
        2) echo "xui" ;;
        3) echo "mz" ;;
        4) echo "mn" ;;
        0) echo "back" ;;
        *) echo "invalid" ;;
    esac
}

# ============================================================
# Common build steps
# ============================================================
install_go() {
    if command -v go &> /dev/null; then
        local current_version=$(go version | awk '{print $3}' | sed 's/go//')
        print_info "Go is installed: $current_version"
        if [[ "$current_version" == "${GO_VERSION%.*}"* ]] || [[ "$current_version" > "${GO_VERSION%.*}" ]]; then
            return 0
        fi
        print_warn "Go version is outdated, updating..."
    fi

    local go_arch=$(get_go_arch)
    local tarball="go${GO_VERSION}.linux-${go_arch}.tar.gz"

    print_step "Installing Go ${GO_VERSION} (${go_arch})"
    cd /tmp || return 1
    wget -q --show-progress "https://go.dev/dl/${tarball}" || {
        print_error "Failed to download Go"
        return 1
    }
    rm -rf /usr/local/go
    tar -C /usr/local -xzf "${tarball}" || {
        print_error "Failed to extract Go"
        return 1
    }
    rm -f "${tarball}"

    export PATH=$PATH:/usr/local/go/bin
    if ! grep -q "/usr/local/go/bin" /root/.bashrc; then
        echo 'export PATH=$PATH:/usr/local/go/bin' >> /root/.bashrc
    fi

    if go version &> /dev/null; then
        print_success "Go installed: $(go version)"
        return 0
    fi
    print_error "Go installation failed"
    return 1
}

build_xray() {
    print_step "Cloning and building Xray from PR"

    if [ -d "$XRAY_SOURCE_DIR" ]; then
        print_info "Repo already exists, updating..."
        cd "$XRAY_SOURCE_DIR" || return 1
        git fetch origin "$PR_BRANCH" 2>&1 | tail -5
        git checkout "$PR_BRANCH" 2>&1 | tail -3
        git reset --hard "origin/$PR_BRANCH" 2>&1 | tail -3
    else
        cd /root || return 1
        git clone "$PR_REPO" Xray-core || { print_error "Clone failed"; return 1; }
        cd Xray-core || return 1
        git checkout "$PR_BRANCH" || { print_error "Branch checkout failed"; return 1; }
    fi

    local go_arch=$(get_go_arch)
    print_step "Building Xray for linux/${go_arch} (this may take a few minutes)"
    CGO_ENABLED=0 GOOS=linux GOARCH=${go_arch} go build \
        -o xray -trimpath -ldflags "-s -w -buildid=" ./main || {
        print_error "Build failed"
        return 1
    }

    [ ! -f "$XRAY_SOURCE_DIR/xray" ] && { print_error "Built binary not found"; return 1; }
    print_success "Build successful: $(./xray version | head -1)"
    return 0
}

# ============================================================
# PasarGuard handlers
# ============================================================
pg_check_prerequisites() {
    local missing=0
    for cmd in docker git wget tar; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed"
            missing=1
        fi
    done

    if ! detect_compose_cmd; then
        print_error "Neither 'docker compose' nor 'docker-compose' is installed"
        missing=1
    else
        print_info "Using compose command: $DOCKER_COMPOSE_CMD"
    fi

    if [ ! -f "$PG_COMPOSE_FILE" ]; then
        print_error "Compose file not found: $PG_COMPOSE_FILE"
        missing=1
    fi

    [ $missing -eq 1 ] && return 1
    return 0
}

pg_create_backup() {
    print_step "Creating backup"
    mkdir -p "$PG_BACKUP_DIR"
    local backup_file="$PG_BACKUP_DIR/docker-compose.yml.$(date +%Y%m%d_%H%M%S).backup"
    cp "$PG_COMPOSE_FILE" "$backup_file" || { print_error "Backup failed"; return 1; }
    ln -sf "$backup_file" "$PG_BACKUP_DIR/latest.backup"
    print_success "Backup created: $backup_file"
    return 0
}

pg_install_binary() {
    print_step "Copying binary to permanent location"
    mkdir -p "$PG_XRAY_DIR"
    cp "$XRAY_SOURCE_DIR/xray" "$PG_XRAY_BIN" || { print_error "Failed to copy binary"; return 1; }
    chmod +x "$PG_XRAY_BIN"
    print_success "Binary placed at $PG_XRAY_BIN"
    return 0
}

pg_update_compose() {
    print_step "Updating docker-compose"

    if grep -q "$PG_XRAY_BIN:/usr/local/bin/xray" "$PG_COMPOSE_FILE"; then
        print_info "Mount already exists in compose"
        return 0
    fi

    if ! grep -q "^    volumes:" "$PG_COMPOSE_FILE"; then
        print_error "No volumes section found in compose"
        return 1
    fi

    python3 << PYEOF
import sys

with open("$PG_COMPOSE_FILE", "r") as f:
    lines = f.readlines()

volumes_idx = None
for i, line in enumerate(lines):
    if line.strip() == "volumes:" and line.startswith("    "):
        volumes_idx = i

if volumes_idx is None:
    print("ERROR: volumes section not found")
    sys.exit(1)

last_volume_idx = volumes_idx
for i in range(volumes_idx + 1, len(lines)):
    line = lines[i]
    if line.strip().startswith("- "):
        last_volume_idx = i
    elif line.strip() and not line.startswith("      "):
        break
    elif not line.strip():
        continue

new_mount = "      - $PG_XRAY_BIN:/usr/local/bin/xray:ro\n"
new_lines = lines[:last_volume_idx + 1] + [new_mount] + lines[last_volume_idx + 1:]

with open("$PG_COMPOSE_FILE", "w") as f:
    f.writelines(new_lines)

print("OK")
PYEOF
    [ $? -ne 0 ] && { print_error "Failed to update compose"; return 1; }

    print_success "Compose updated"
    print_info "Current compose content:"
    echo -e "${YELLOW}"
    cat "$PG_COMPOSE_FILE"
    echo -e "${NC}"
    return 0
}

pg_restart_container() {
    print_step "Restarting node container"
    cd "$PG_NODE_DIR" || return 1
    $DOCKER_COMPOSE_CMD down || { print_error "Failed to stop container"; return 1; }
    $DOCKER_COMPOSE_CMD up -d || { print_error "Failed to start container"; return 1; }
    sleep 3
    print_success "Container restarted"
    return 0
}

pg_install() {
    pg_check_prerequisites || { print_error "Prerequisites not met"; return 1; }
    pg_create_backup       || return 1
    install_go             || return 1
    build_xray             || return 1
    pg_install_binary      || return 1
    pg_update_compose      || return 1
    pg_restart_container   || return 1
    return 0
}

pg_rollback() {
    detect_compose_cmd || { print_error "No docker compose command found"; return 1; }
    print_info "Using compose command: $DOCKER_COMPOSE_CMD"

    if [ ! -d "$PG_BACKUP_DIR" ] || [ -z "$(ls -A $PG_BACKUP_DIR 2>/dev/null)" ]; then
        print_error "No backups found"
        return 1
    fi

    print_info "Available backups:"
    echo ""
    ls -lt "$PG_BACKUP_DIR" | grep -v "latest.backup" | grep "backup$" | awk '{print "  " NR". "$9"  ("$6" "$7" "$8")"}' | head -10
    echo ""
    print_info "Latest backup: $(readlink -f $PG_BACKUP_DIR/latest.backup 2>/dev/null || echo 'N/A')"
    echo ""
    print_warn "This will:"
    echo "  - Restore compose from latest backup"
    echo "  - Restart the container"
    echo "  - Custom binary at $PG_XRAY_DIR will remain (only mount removed)"
    echo ""
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "Cancelled"; return 1; }

    [ ! -f "$PG_BACKUP_DIR/latest.backup" ] && { print_error "Latest backup not found"; return 1; }

    local pre_rollback="$PG_BACKUP_DIR/pre-rollback-$(date +%Y%m%d_%H%M%S).backup"
    cp "$PG_COMPOSE_FILE" "$pre_rollback"
    print_info "Pre-rollback snapshot: $pre_rollback"

    cp "$PG_BACKUP_DIR/latest.backup" "$PG_COMPOSE_FILE" || { print_error "Rollback failed"; return 1; }
    print_success "Compose restored from backup"

    print_info "Current compose content:"
    echo -e "${YELLOW}"
    cat "$PG_COMPOSE_FILE"
    echo -e "${NC}"

    pg_restart_container || return 1
    return 0
}

pg_status() {
    if detect_compose_cmd; then
        print_info "Compose command: $DOCKER_COMPOSE_CMD"
    else
        print_warn "No docker compose command detected"
    fi

    print_step "Container status"
    if docker ps --format "{{.Names}}" | grep -q "^${PG_CONTAINER_NAME}$"; then
        print_success "Node container is running"
        docker ps --filter "name=^${PG_CONTAINER_NAME}$" --format "  Status: {{.Status}}\n  Image: {{.Image}}"
    else
        print_error "Node container is not running"
        docker ps -a --format "{{.Names}}" | grep -q "^${PG_CONTAINER_NAME}$" && \
            docker ps -a --filter "name=^${PG_CONTAINER_NAME}$" --format "  Status: {{.Status}}"
        return 1
    fi

    print_step "Current Xray version"
    local xray_ver=$(docker exec "$PG_CONTAINER_NAME" xray version 2>/dev/null | head -1)
    if [ -z "$xray_ver" ]; then
        print_error "Cannot read Xray version"
    else
        echo "  $xray_ver"
        if echo "$xray_ver" | grep -q "$PR_COMMIT_HASH\|UserConnTracker"; then
            print_success "PR #5844 (UserConnTracker) build is active"
        elif [ -f "$PG_XRAY_BIN" ] && grep -q "$PG_XRAY_BIN" "$PG_COMPOSE_FILE"; then
            print_info "Mount is active but commit hash differs"
            print_info "Custom binary: $($PG_XRAY_BIN version 2>/dev/null | head -1)"
        else
            print_info "Default image binary is active"
        fi
    fi

    print_step "Mount status"
    if grep -q "$PG_XRAY_BIN:/usr/local/bin/xray" "$PG_COMPOSE_FILE"; then
        print_success "Mount is active in compose"
    else
        print_info "No mount in compose (default version)"
    fi

    if [ -f "$PG_XRAY_BIN" ]; then
        print_info "Custom binary present: $PG_XRAY_BIN ($(du -h $PG_XRAY_BIN | cut -f1))"
    else
        print_info "No custom binary present"
    fi

    print_step "Backups"
    if [ -d "$PG_BACKUP_DIR" ] && [ -n "$(ls -A $PG_BACKUP_DIR 2>/dev/null)" ]; then
        local count=$(ls "$PG_BACKUP_DIR"/*.backup 2>/dev/null | grep -v latest | wc -l)
        print_success "$count backup(s) in $PG_BACKUP_DIR"
        [ -L "$PG_BACKUP_DIR/latest.backup" ] && print_info "Latest: $(readlink -f $PG_BACKUP_DIR/latest.backup)"
    else
        print_warn "No backups found"
    fi

    print_step "Container resource usage"
    docker stats --no-stream --format "  CPU: {{.CPUPerc}}  |  RAM: {{.MemUsage}}  |  NET: {{.NetIO}}" "$PG_CONTAINER_NAME" 2>/dev/null

    print_step "Last 15 log lines"
    echo -e "${YELLOW}"
    docker logs --tail 15 "$PG_CONTAINER_NAME" 2>&1 | sed 's/^/  /'
    echo -e "${NC}"

    local err_count=$(docker logs --tail 100 "$PG_CONTAINER_NAME" 2>&1 | grep -ciE "panic|fatal" || echo "0")
    if [ "$err_count" -gt 0 ]; then
        print_warn "Found $err_count panic/fatal line(s) in last 100 log lines"
        echo "  See full log: docker logs $PG_CONTAINER_NAME"
    else
        print_success "No panics/fatals found in recent logs"
    fi
    return 0
}

# ============================================================
# 3X-UI handlers
# ============================================================
xui_check_prerequisites() {
    local missing=0
    for cmd in git wget tar systemctl; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed"
            missing=1
        fi
    done

    if [ ! -d "$XUI_DIR" ]; then
        print_error "3X-UI directory not found: $XUI_DIR"
        missing=1
    fi

    if ! systemctl list-unit-files 2>/dev/null | grep -q "^${XUI_SERVICE}.service"; then
        print_error "x-ui service not found"
        missing=1
    fi

    detect_xui_arch || missing=1

    if [ -z "$XUI_XRAY_BIN" ] || [ ! -f "$XUI_XRAY_BIN" ]; then
        print_error "Xray binary not found in $XUI_BIN_DIR"
        ls -la "$XUI_BIN_DIR" 2>/dev/null | sed 's/^/  /'
        missing=1
    fi

    [ $missing -eq 1 ] && return 1
    print_info "Detected Xray binary: $XUI_XRAY_BIN"
    return 0
}

xui_create_backup() {
    print_step "Creating backup of original Xray binary"
    mkdir -p "$XUI_BACKUP_DIR"
    local binary_name=$(basename "$XUI_XRAY_BIN")
    local backup_file="$XUI_BACKUP_DIR/${binary_name}.$(date +%Y%m%d_%H%M%S).backup"

    # If current binary is already custom, don't overwrite the existing backup
    if [ -f "$XUI_BACKUP_DIR/latest.backup" ]; then
        local current_ver=$("$XUI_XRAY_BIN" version 2>/dev/null | head -1)
        if echo "$current_ver" | grep -q "$PR_COMMIT_HASH"; then
            print_info "Current binary is already a custom build, keeping existing backup"
            return 0
        fi
    fi

    cp "$XUI_XRAY_BIN" "$backup_file" || { print_error "Backup failed"; return 1; }
    ln -sf "$backup_file" "$XUI_BACKUP_DIR/latest.backup"
    print_success "Backup created: $backup_file"
    return 0
}

xui_install_binary() {
    print_step "Replacing Xray binary in 3X-UI"
    cp "$XRAY_SOURCE_DIR/xray" "$XUI_XRAY_BIN" || { print_error "Failed to replace binary"; return 1; }
    chmod +x "$XUI_XRAY_BIN"
    print_success "Binary replaced at $XUI_XRAY_BIN"
    return 0
}

xui_restart_service() {
    print_step "Restarting x-ui service"
    systemctl restart "$XUI_SERVICE" || { print_error "Failed to restart x-ui service"; return 1; }
    sleep 3
    if systemctl is-active --quiet "$XUI_SERVICE"; then
        print_success "x-ui service restarted"
        return 0
    fi
    print_error "x-ui service failed to start"
    return 1
}

xui_install() {
    xui_check_prerequisites || { print_error "Prerequisites not met"; return 1; }
    xui_create_backup       || return 1
    install_go              || return 1
    build_xray              || return 1
    xui_install_binary      || return 1
    xui_restart_service     || return 1
    return 0
}

xui_rollback() {
    detect_xui_arch || return 1

    if [ ! -d "$XUI_BACKUP_DIR" ] || [ -z "$(ls -A $XUI_BACKUP_DIR 2>/dev/null)" ]; then
        print_error "No backups found"
        return 1
    fi

    print_info "Available backups:"
    echo ""
    ls -lt "$XUI_BACKUP_DIR" | grep -v "latest.backup" | grep "backup$" | awk '{print "  " NR". "$9"  ("$6" "$7" "$8")"}' | head -10
    echo ""
    print_info "Latest backup: $(readlink -f $XUI_BACKUP_DIR/latest.backup 2>/dev/null || echo 'N/A')"
    echo ""
    print_warn "This will:"
    echo "  - Restore Xray binary from latest backup"
    echo "  - Restart the x-ui service"
    echo ""
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "Cancelled"; return 1; }

    [ ! -f "$XUI_BACKUP_DIR/latest.backup" ] && { print_error "Latest backup not found"; return 1; }

    local pre_rollback="$XUI_BACKUP_DIR/pre-rollback-$(date +%Y%m%d_%H%M%S).backup"
    cp "$XUI_XRAY_BIN" "$pre_rollback"
    print_info "Pre-rollback snapshot: $pre_rollback"

    cp "$XUI_BACKUP_DIR/latest.backup" "$XUI_XRAY_BIN" || { print_error "Rollback failed"; return 1; }
    chmod +x "$XUI_XRAY_BIN"
    print_success "Binary restored from backup"

    xui_restart_service || return 1
    return 0
}

xui_status() {
    detect_xui_arch || return 1

    print_step "Service status"
    if systemctl is-active --quiet "$XUI_SERVICE"; then
        print_success "x-ui service is running"
        systemctl status "$XUI_SERVICE" --no-pager 2>/dev/null | grep -E "Active:|Main PID:" | sed 's/^/  /'
    else
        print_error "x-ui service is not running"
        systemctl status "$XUI_SERVICE" --no-pager 2>/dev/null | grep -E "Active:" | sed 's/^/  /'
        return 1
    fi

    print_step "Current Xray version"
    if [ ! -f "$XUI_XRAY_BIN" ]; then
        print_error "Xray binary not found at $XUI_XRAY_BIN"
        return 1
    fi
    local xray_ver=$("$XUI_XRAY_BIN" version 2>/dev/null | head -1)
    if [ -z "$xray_ver" ]; then
        print_error "Cannot read Xray version"
    else
        echo "  $xray_ver"
        if echo "$xray_ver" | grep -q "$PR_COMMIT_HASH\|UserConnTracker"; then
            print_success "PR #5844 (UserConnTracker) build is active"
        else
            print_info "Default 3X-UI Xray binary is active"
        fi
    fi

    print_step "Binary info"
    print_info "Path: $XUI_XRAY_BIN"
    print_info "Size: $(du -h $XUI_XRAY_BIN | cut -f1)"
    print_info "Modified: $(stat -c '%y' $XUI_XRAY_BIN | cut -d. -f1)"

    print_step "Backups"
    if [ -d "$XUI_BACKUP_DIR" ] && [ -n "$(ls -A $XUI_BACKUP_DIR 2>/dev/null)" ]; then
        local count=$(ls "$XUI_BACKUP_DIR"/*.backup 2>/dev/null | grep -v latest | wc -l)
        print_success "$count backup(s) in $XUI_BACKUP_DIR"
        [ -L "$XUI_BACKUP_DIR/latest.backup" ] && print_info "Latest: $(readlink -f $XUI_BACKUP_DIR/latest.backup)"
    else
        print_warn "No backups found"
    fi

    print_step "Last 15 log lines (journalctl)"
    echo -e "${YELLOW}"
    journalctl -u "$XUI_SERVICE" --no-pager -n 15 2>&1 | sed 's/^/  /'
    echo -e "${NC}"

    local err_count=$(journalctl -u "$XUI_SERVICE" --no-pager -n 100 2>&1 | grep -ciE "panic|fatal" || echo "0")
    if [ "$err_count" -gt 0 ]; then
        print_warn "Found $err_count panic/fatal line(s) in last 100 log lines"
        echo "  See full log: journalctl -u $XUI_SERVICE -f"
    else
        print_success "No panics/fatals found in recent logs"
    fi
    return 0
}

# ============================================================
# Marzban handlers
# ============================================================
mz_check_prerequisites() {
    local missing=0
    for cmd in docker git wget tar; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed"
            missing=1
        fi
    done

    if ! detect_compose_cmd; then
        print_error "Neither 'docker compose' nor 'docker-compose' is installed"
        missing=1
    else
        print_info "Using compose command: $DOCKER_COMPOSE_CMD"
    fi

    if [ ! -f "$MZ_COMPOSE_FILE" ]; then
        print_error "Marzban compose file not found: $MZ_COMPOSE_FILE"
        missing=1
    fi

    [ $missing -eq 1 ] && return 1
    return 0
}

mz_create_backup() {
    print_step "Creating backup"
    mkdir -p "$MZ_BACKUP_DIR"

    # Backup .env
    if [ -f "$MZ_ENV_FILE" ]; then
        local env_backup="$MZ_BACKUP_DIR/env.$(date +%Y%m%d_%H%M%S).backup"
        cp "$MZ_ENV_FILE" "$env_backup"
        ln -sf "$env_backup" "$MZ_BACKUP_DIR/env-latest.backup"
        print_success "Env backup: $env_backup"
    fi

    # Backup existing custom xray binary if present
    if [ -f "$MZ_XRAY_BIN" ]; then
        local current_ver=$("$MZ_XRAY_BIN" version 2>/dev/null | head -1)
        if echo "$current_ver" | grep -q "$PR_COMMIT_HASH"; then
            print_info "Current binary is already a custom build, keeping existing backup"
            return 0
        fi
        local bin_backup="$MZ_BACKUP_DIR/xray.$(date +%Y%m%d_%H%M%S).backup"
        cp "$MZ_XRAY_BIN" "$bin_backup"
        ln -sf "$bin_backup" "$MZ_BACKUP_DIR/xray-latest.backup"
        print_success "Binary backup: $bin_backup"
    fi

    return 0
}

mz_install_binary() {
    print_step "Copying binary to Marzban data directory"
    mkdir -p "$MZ_XRAY_DIR"
    cp "$XRAY_SOURCE_DIR/xray" "$MZ_XRAY_BIN" || { print_error "Failed to copy binary"; return 1; }
    chmod +x "$MZ_XRAY_BIN"
    print_success "Binary placed at $MZ_XRAY_BIN"
    return 0
}

mz_update_env() {
    print_step "Updating XRAY_EXECUTABLE_PATH in .env"

    if [ ! -f "$MZ_ENV_FILE" ]; then
        echo "XRAY_EXECUTABLE_PATH=$MZ_XRAY_BIN" > "$MZ_ENV_FILE"
        print_success "Created .env with XRAY_EXECUTABLE_PATH"
        return 0
    fi

    if grep -q "^XRAY_EXECUTABLE_PATH=" "$MZ_ENV_FILE"; then
        sed -i "s|^XRAY_EXECUTABLE_PATH=.*|XRAY_EXECUTABLE_PATH=$MZ_XRAY_BIN|" "$MZ_ENV_FILE"
        print_success "Updated XRAY_EXECUTABLE_PATH in .env"
    else
        echo "XRAY_EXECUTABLE_PATH=$MZ_XRAY_BIN" >> "$MZ_ENV_FILE"
        print_success "Added XRAY_EXECUTABLE_PATH to .env"
    fi
    return 0
}

mz_restart_container() {
    print_step "Restarting Marzban container"
    cd "$MZ_DIR" || return 1
    $DOCKER_COMPOSE_CMD down || { print_error "Failed to stop container"; return 1; }
    $DOCKER_COMPOSE_CMD up -d || { print_error "Failed to start container"; return 1; }
    sleep 3
    print_success "Container restarted"
    return 0
}

mz_install() {
    mz_check_prerequisites || { print_error "Prerequisites not met"; return 1; }
    mz_create_backup       || return 1
    install_go             || return 1
    build_xray             || return 1
    mz_install_binary      || return 1
    mz_update_env          || return 1
    mz_restart_container   || return 1
    return 0
}

mz_rollback() {
    detect_compose_cmd || { print_error "No docker compose command found"; return 1; }

    if [ ! -d "$MZ_BACKUP_DIR" ] || [ -z "$(ls -A $MZ_BACKUP_DIR 2>/dev/null)" ]; then
        print_error "No backups found"
        return 1
    fi

    print_info "Available backups:"
    echo ""
    ls -lt "$MZ_BACKUP_DIR" | grep "backup$" | grep -v "latest" | awk '{print "  " NR". "$9"  ("$6" "$7" "$8")"}' | head -10
    echo ""
    print_warn "This will:"
    echo "  - Restore .env from backup (removes XRAY_EXECUTABLE_PATH override)"
    echo "  - Remove custom binary at $MZ_XRAY_BIN"
    echo "  - Restart Marzban container (uses default image binary)"
    echo ""
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "Cancelled"; return 1; }

    # Restore .env
    if [ -f "$MZ_BACKUP_DIR/env-latest.backup" ]; then
        cp "$MZ_BACKUP_DIR/env-latest.backup" "$MZ_ENV_FILE" || { print_error "Env restore failed"; return 1; }
        print_success "Env restored from backup"
    else
        # Just remove the XRAY_EXECUTABLE_PATH line
        if [ -f "$MZ_ENV_FILE" ]; then
            sed -i '/^XRAY_EXECUTABLE_PATH=/d' "$MZ_ENV_FILE"
            print_success "Removed XRAY_EXECUTABLE_PATH from .env"
        fi
    fi

    # Remove custom binary
    if [ -f "$MZ_XRAY_BIN" ]; then
        rm -f "$MZ_XRAY_BIN"
        print_success "Removed custom binary"
    fi

    mz_restart_container || return 1
    return 0
}

mz_status() {
    if detect_compose_cmd; then
        print_info "Compose command: $DOCKER_COMPOSE_CMD"
    else
        print_warn "No docker compose command detected"
    fi

    print_step "Container status"
    local cname=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "marzban.*marzban" | head -1)
    [ -z "$cname" ] && cname="$MZ_CONTAINER_NAME"

    if docker ps --format "{{.Names}}" | grep -q "$cname"; then
        print_success "Marzban container is running ($cname)"
        docker ps --filter "name=$cname" --format "  Status: {{.Status}}\n  Image: {{.Image}}"
    else
        print_error "Marzban container is not running"
        return 1
    fi

    print_step "Current Xray version"
    local xray_ver=$(docker exec "$cname" xray version 2>/dev/null | head -1)
    if [ -z "$xray_ver" ]; then
        # Try via XRAY_EXECUTABLE_PATH
        local xray_path=$(docker exec "$cname" sh -c 'echo $XRAY_EXECUTABLE_PATH' 2>/dev/null)
        [ -n "$xray_path" ] && xray_ver=$(docker exec "$cname" "$xray_path" version 2>/dev/null | head -1)
    fi
    if [ -z "$xray_ver" ]; then
        print_error "Cannot read Xray version"
    else
        echo "  $xray_ver"
        if echo "$xray_ver" | grep -q "$PR_COMMIT_HASH\|UserConnTracker"; then
            print_success "PR #5844 (UserConnTracker) build is active"
        else
            print_info "Default Marzban Xray binary is active"
        fi
    fi

    print_step "Custom binary"
    if [ -f "$MZ_XRAY_BIN" ]; then
        print_info "Present: $MZ_XRAY_BIN ($(du -h $MZ_XRAY_BIN | cut -f1))"
    else
        print_info "No custom binary present"
    fi

    print_step "XRAY_EXECUTABLE_PATH"
    if [ -f "$MZ_ENV_FILE" ] && grep -q "^XRAY_EXECUTABLE_PATH=" "$MZ_ENV_FILE"; then
        print_info "$(grep '^XRAY_EXECUTABLE_PATH=' $MZ_ENV_FILE)"
    else
        print_info "Not set (using default)"
    fi

    print_step "Backups"
    if [ -d "$MZ_BACKUP_DIR" ] && [ -n "$(ls -A $MZ_BACKUP_DIR 2>/dev/null)" ]; then
        local count=$(ls "$MZ_BACKUP_DIR"/*.backup 2>/dev/null | grep -v latest | wc -l)
        print_success "$count backup(s) in $MZ_BACKUP_DIR"
    else
        print_warn "No backups found"
    fi

    print_step "Last 15 log lines"
    echo -e "${YELLOW}"
    docker logs --tail 15 "$cname" 2>&1 | sed 's/^/  /'
    echo -e "${NC}"

    local err_count=$(docker logs --tail 100 "$cname" 2>&1 | grep -ciE "panic|fatal" || echo "0")
    if [ "$err_count" -gt 0 ]; then
        print_warn "Found $err_count panic/fatal line(s) in last 100 log lines"
    else
        print_success "No panics/fatals found in recent logs"
    fi
    return 0
}

# ============================================================
# Marzneshin handlers
# ============================================================
mn_check_prerequisites() {
    local missing=0
    for cmd in docker git wget tar; do
        if ! command -v $cmd &> /dev/null; then
            print_error "$cmd is not installed"
            missing=1
        fi
    done

    if ! detect_compose_cmd; then
        print_error "Neither 'docker compose' nor 'docker-compose' is installed"
        missing=1
    else
        print_info "Using compose command: $DOCKER_COMPOSE_CMD"
    fi

    if [ ! -f "$MN_COMPOSE_FILE" ]; then
        print_error "Marzneshin compose file not found: $MN_COMPOSE_FILE"
        missing=1
    fi

    [ $missing -eq 1 ] && return 1
    return 0
}

mn_create_backup() {
    print_step "Creating backup"
    mkdir -p "$MN_BACKUP_DIR"

    # Backup compose file
    local compose_backup="$MN_BACKUP_DIR/docker-compose.yml.$(date +%Y%m%d_%H%M%S).backup"
    cp "$MN_COMPOSE_FILE" "$compose_backup" || { print_error "Compose backup failed"; return 1; }
    ln -sf "$compose_backup" "$MN_BACKUP_DIR/compose-latest.backup"
    print_success "Compose backup: $compose_backup"

    # Backup existing custom xray binary if present
    if [ -f "$MN_XRAY_BIN" ]; then
        local current_ver=$("$MN_XRAY_BIN" version 2>/dev/null | head -1)
        if echo "$current_ver" | grep -q "$PR_COMMIT_HASH"; then
            print_info "Current binary is already a custom build, keeping existing backup"
            return 0
        fi
        local bin_backup="$MN_BACKUP_DIR/xray.$(date +%Y%m%d_%H%M%S).backup"
        cp "$MN_XRAY_BIN" "$bin_backup"
        ln -sf "$bin_backup" "$MN_BACKUP_DIR/xray-latest.backup"
        print_success "Binary backup: $bin_backup"
    fi

    return 0
}

mn_install_binary() {
    print_step "Copying binary to Marznode data directory"
    mkdir -p "$MN_DATA_DIR"
    cp "$XRAY_SOURCE_DIR/xray" "$MN_XRAY_BIN" || { print_error "Failed to copy binary"; return 1; }
    chmod +x "$MN_XRAY_BIN"
    print_success "Binary placed at $MN_XRAY_BIN"
    return 0
}

mn_update_compose() {
    print_step "Updating Marzneshin compose for custom Xray"

    # Update XRAY_EXECUTABLE_PATH in marznode environment
    if grep -q "XRAY_EXECUTABLE_PATH:" "$MN_COMPOSE_FILE"; then
        sed -i "s|XRAY_EXECUTABLE_PATH:.*|XRAY_EXECUTABLE_PATH: \"$MN_XRAY_BIN\"|" "$MN_COMPOSE_FILE"
        print_success "Updated XRAY_EXECUTABLE_PATH in compose"
    else
        print_warn "XRAY_EXECUTABLE_PATH not found in compose, adding volume mount instead"
    fi

    # Ensure the binary is volume-mounted into the marznode container
    # The /var/lib/marznode is already mounted, so if our binary is there it's accessible
    if grep -q "$MN_DATA_DIR:/var/lib/marznode" "$MN_COMPOSE_FILE" || \
       grep -q "$MN_DATA_DIR:$MN_DATA_DIR" "$MN_COMPOSE_FILE"; then
        print_info "Data directory already mounted, binary will be accessible"
    else
        print_warn "$MN_DATA_DIR mount not found in compose"
        print_info "Adding volume mount for binary"
        # Add a direct mount for the binary
        python3 << PYEOF
import sys

with open("$MN_COMPOSE_FILE", "r") as f:
    content = f.read()

# Find marznode volumes section and add our mount
lines = content.split('\n')
in_marznode = False
volumes_idx = None
for i, line in enumerate(lines):
    if 'marznode:' in line and not line.strip().startswith('#'):
        in_marznode = True
    elif in_marznode and line.strip().startswith('volumes:'):
        volumes_idx = i
        break
    elif in_marznode and line and not line.startswith(' ') and not line.startswith('\t'):
        in_marznode = False

if volumes_idx is None:
    print("ERROR: marznode volumes section not found")
    sys.exit(1)

# Find last volume entry under marznode
last_vol = volumes_idx
for i in range(volumes_idx + 1, len(lines)):
    if lines[i].strip().startswith('- '):
        last_vol = i
    elif lines[i].strip() and not lines[i].startswith('      '):
        break

new_mount = "      - $MN_XRAY_BIN:/usr/local/bin/xray:ro"
lines.insert(last_vol + 1, new_mount)

with open("$MN_COMPOSE_FILE", "w") as f:
    f.write('\n'.join(lines))

print("OK")
PYEOF
        [ $? -ne 0 ] && { print_error "Failed to update compose"; return 1; }
    fi

    print_success "Compose updated"
    return 0
}

mn_restart_container() {
    print_step "Restarting Marzneshin containers"
    cd "$MN_DIR" || return 1

    # Try using marzneshin CLI first, fallback to docker compose
    if command -v marzneshin &> /dev/null; then
        marzneshin restart || { print_error "Failed to restart via CLI"; return 1; }
    else
        $DOCKER_COMPOSE_CMD -p marzneshin down || { print_error "Failed to stop containers"; return 1; }
        $DOCKER_COMPOSE_CMD -p marzneshin up -d || { print_error "Failed to start containers"; return 1; }
    fi
    sleep 3
    print_success "Containers restarted"
    return 0
}

mn_install() {
    mn_check_prerequisites || { print_error "Prerequisites not met"; return 1; }
    mn_create_backup       || return 1
    install_go             || return 1
    build_xray             || return 1
    mn_install_binary      || return 1
    mn_update_compose      || return 1
    mn_restart_container   || return 1
    return 0
}

mn_rollback() {
    detect_compose_cmd || { print_error "No docker compose command found"; return 1; }

    if [ ! -d "$MN_BACKUP_DIR" ] || [ -z "$(ls -A $MN_BACKUP_DIR 2>/dev/null)" ]; then
        print_error "No backups found"
        return 1
    fi

    print_info "Available backups:"
    echo ""
    ls -lt "$MN_BACKUP_DIR" | grep "backup$" | grep -v "latest" | awk '{print "  " NR". "$9"  ("$6" "$7" "$8")"}' | head -10
    echo ""
    print_warn "This will:"
    echo "  - Restore docker-compose.yml from backup"
    echo "  - Remove custom binary at $MN_XRAY_BIN"
    echo "  - Restart Marzneshin containers"
    echo ""
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "Cancelled"; return 1; }

    # Restore compose
    if [ -f "$MN_BACKUP_DIR/compose-latest.backup" ]; then
        local pre_rollback="$MN_BACKUP_DIR/pre-rollback-$(date +%Y%m%d_%H%M%S).backup"
        cp "$MN_COMPOSE_FILE" "$pre_rollback"
        print_info "Pre-rollback snapshot: $pre_rollback"

        cp "$MN_BACKUP_DIR/compose-latest.backup" "$MN_COMPOSE_FILE" || { print_error "Compose restore failed"; return 1; }
        print_success "Compose restored from backup"
    fi

    # Remove custom binary
    if [ -f "$MN_XRAY_BIN" ]; then
        rm -f "$MN_XRAY_BIN"
        print_success "Removed custom binary"
    fi

    mn_restart_container || return 1
    return 0
}

mn_status() {
    if detect_compose_cmd; then
        print_info "Compose command: $DOCKER_COMPOSE_CMD"
    else
        print_warn "No docker compose command detected"
    fi

    print_step "Container status"
    local cname=$(docker ps --format "{{.Names}}" 2>/dev/null | grep -E "marzneshin.*marznode" | head -1)
    [ -z "$cname" ] && cname="$MN_NODE_CONTAINER"

    if docker ps --format "{{.Names}}" | grep -q "$cname"; then
        print_success "Marznode container is running ($cname)"
        docker ps --filter "name=$cname" --format "  Status: {{.Status}}\n  Image: {{.Image}}"
    else
        print_error "Marznode container is not running"
        return 1
    fi

    print_step "Current Xray version"
    local xray_ver=$(docker exec "$cname" xray version 2>/dev/null | head -1)
    if [ -z "$xray_ver" ]; then
        local xray_path=$(docker exec "$cname" sh -c 'echo $XRAY_EXECUTABLE_PATH' 2>/dev/null)
        [ -n "$xray_path" ] && xray_ver=$(docker exec "$cname" "$xray_path" version 2>/dev/null | head -1)
    fi
    if [ -z "$xray_ver" ]; then
        print_error "Cannot read Xray version"
    else
        echo "  $xray_ver"
        if echo "$xray_ver" | grep -q "$PR_COMMIT_HASH\|UserConnTracker"; then
            print_success "PR #5844 (UserConnTracker) build is active"
        else
            print_info "Default Marzneshin Xray binary is active"
        fi
    fi

    print_step "Custom binary"
    if [ -f "$MN_XRAY_BIN" ]; then
        print_info "Present: $MN_XRAY_BIN ($(du -h $MN_XRAY_BIN | cut -f1))"
    else
        print_info "No custom binary present"
    fi

    print_step "XRAY_EXECUTABLE_PATH in compose"
    if grep -q "XRAY_EXECUTABLE_PATH:" "$MN_COMPOSE_FILE"; then
        print_info "$(grep 'XRAY_EXECUTABLE_PATH:' $MN_COMPOSE_FILE | head -1 | xargs)"
    else
        print_info "Not set (using default)"
    fi

    print_step "Backups"
    if [ -d "$MN_BACKUP_DIR" ] && [ -n "$(ls -A $MN_BACKUP_DIR 2>/dev/null)" ]; then
        local count=$(ls "$MN_BACKUP_DIR"/*.backup 2>/dev/null | grep -v latest | wc -l)
        print_success "$count backup(s) in $MN_BACKUP_DIR"
    else
        print_warn "No backups found"
    fi

    print_step "Last 15 log lines (marznode)"
    echo -e "${YELLOW}"
    docker logs --tail 15 "$cname" 2>&1 | sed 's/^/  /'
    echo -e "${NC}"

    local err_count=$(docker logs --tail 100 "$cname" 2>&1 | grep -ciE "panic|fatal" || echo "0")
    if [ "$err_count" -gt 0 ]; then
        print_warn "Found $err_count panic/fatal line(s) in last 100 log lines"
    else
        print_success "No panics/fatals found in recent logs"
    fi
    return 0
}

# ============================================================
# Main menu options - each asks panel first
# ============================================================
option_install() {
    print_header
    echo -e "${BOLD}Option 1: Install Xray with PR #5844 (UserConnTracker)${NC}"

    local panel=$(select_panel)
    case "$panel" in
        back)    return ;;
        invalid) print_error "Invalid choice"; sleep 1; return ;;
    esac

    print_header
    case "$panel" in
        pg)
            echo -e "${BOLD}Install on PasarGuard Node${NC}\n"
            print_warn "This will:"
            echo "  - Backup current docker-compose.yml"
            echo "  - Install Go if needed"
            echo "  - Clone and build Xray from PR"
            echo "  - Mount new binary into node container"
            echo "  - Restart container"
            ;;
        xui)
            echo -e "${BOLD}Install on 3X-UI${NC}\n"
            print_warn "This will:"
            echo "  - Backup current Xray binary"
            echo "  - Install Go if needed"
            echo "  - Clone and build Xray from PR"
            echo "  - Replace Xray binary in $XUI_BIN_DIR"
            echo "  - Restart x-ui service"
            ;;
        mz)
            echo -e "${BOLD}Install on Marzban${NC}\n"
            print_warn "This will:"
            echo "  - Backup current .env and Xray binary"
            echo "  - Install Go if needed"
            echo "  - Clone and build Xray from PR"
            echo "  - Place binary at $MZ_XRAY_BIN"
            echo "  - Set XRAY_EXECUTABLE_PATH in .env"
            echo "  - Restart Marzban container"
            ;;
        mn)
            echo -e "${BOLD}Install on Marzneshin (marznode)${NC}\n"
            print_warn "This will:"
            echo "  - Backup current compose and Xray binary"
            echo "  - Install Go if needed"
            echo "  - Clone and build Xray from PR"
            echo "  - Place binary at $MN_XRAY_BIN"
            echo "  - Update XRAY_EXECUTABLE_PATH in compose"
            echo "  - Restart Marzneshin containers"
            ;;
    esac
    echo ""
    read -p "Proceed? (y/n): " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && { print_info "Cancelled"; press_enter; return; }

    local panel_name=""
    case "$panel" in
        pg)  panel_name="PasarGuard";  pg_install  ;;
        xui) panel_name="3X-UI";       xui_install ;;
        mz)  panel_name="Marzban";     mz_install  ;;
        mn)  panel_name="Marzneshin";  mn_install  ;;
    esac

    if [ $? -eq 0 ]; then
        echo ""
        print_success "$panel_name installation completed!"
        print_info "Use option 3 to verify"
    fi
    press_enter
}

option_rollback() {
    print_header
    echo -e "${BOLD}Option 2: Rollback to default Xray${NC}"

    local panel=$(select_panel)
    case "$panel" in
        back)    return ;;
        invalid) print_error "Invalid choice"; sleep 1; return ;;
    esac

    print_header
    local panel_name=""
    case "$panel" in
        pg)  panel_name="PasarGuard";  echo -e "${BOLD}Rollback PasarGuard Node${NC}\n";  pg_rollback  ;;
        xui) panel_name="3X-UI";       echo -e "${BOLD}Rollback 3X-UI${NC}\n";            xui_rollback ;;
        mz)  panel_name="Marzban";     echo -e "${BOLD}Rollback Marzban${NC}\n";           mz_rollback  ;;
        mn)  panel_name="Marzneshin";  echo -e "${BOLD}Rollback Marzneshin${NC}\n";        mn_rollback  ;;
    esac

    if [ $? -eq 0 ]; then
        echo ""
        print_success "$panel_name rollback completed"
        print_info "Use option 3 to verify"
    fi
    press_enter
}

option_status() {
    print_header
    echo -e "${BOLD}Option 3: Service Status${NC}"

    local panel=$(select_panel)
    case "$panel" in
        back)    return ;;
        invalid) print_error "Invalid choice"; sleep 1; return ;;
    esac

    print_header
    case "$panel" in
        pg)  echo -e "${BOLD}PasarGuard Node Status${NC}\n";  pg_status  ;;
        xui) echo -e "${BOLD}3X-UI Status${NC}\n";            xui_status ;;
        mz)  echo -e "${BOLD}Marzban Status${NC}\n";           mz_status  ;;
        mn)  echo -e "${BOLD}Marzneshin Status${NC}\n";        mn_status  ;;
    esac
    press_enter
}

# ============================================================
# Main menu
# ============================================================
main_menu() {
    while true; do
        print_header

        # Show what panels are detected
        auto_detect_panels

        echo -e "${BOLD}Detected panels:${NC}"
        local pname pvar
        for pname_var in "PasarGuard Node:PANEL_PG" "3X-UI:PANEL_XUI" "Marzban:PANEL_MZ" "Marzneshin:PANEL_MN"; do
            pname="${pname_var%%:*}"
            pvar="${pname_var##*:}"
            if [ "${!pvar}" == "1" ]; then
                echo -e "  ${GREEN}o${NC} $pname"
            else
                echo -e "  ${RED}x${NC} $pname"
            fi
        done
        echo ""

        echo -e "${BOLD}Main Menu:${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}) Install Xray with PR #5844 (UserConnTracker)"
        echo -e "  ${YELLOW}2${NC}) Rollback to default Xray"
        echo -e "  ${BLUE}3${NC}) Show service status"
        echo -e "  ${RED}0${NC}) Exit"
        echo ""
        read -p "Choose option: " choice

        case $choice in
            1) option_install ;;
            2) option_rollback ;;
            3) option_status ;;
            0)
                echo -e "\n${GREEN}Goodbye${NC}\n"
                exit 0
                ;;
            *)
                print_error "Invalid option"
                sleep 1
                ;;
        esac
    done
}

# Start
check_root
main_menu
