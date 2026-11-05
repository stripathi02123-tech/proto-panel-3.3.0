#!/bin/bash
# =========================================================
# Proto Panel - Automated Installation & Management Script
# =========================================================

# Ensure running in bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash > /dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
fi

# Enhanced 256-color palette for professional hosting CLI
GREEN='\033[38;5;48m'
EMERALD='\033[38;5;42m'
CYAN='\033[38;5;51m'
TEAL='\033[38;5;37m'
BLUE='\033[38;5;75m'
VIOLET='\033[38;5;141m'
YELLOW='\033[38;5;220m'
AMBER='\033[38;5;214m'
ORANGE='\033[38;5;208m'
RED='\033[38;5;196m'
WHITE='\033[1;37m'
LIGHT='\033[38;5;252m'
GRAY='\033[38;5;242m'
DARKGRAY='\033[38;5;236m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# ----------------------------------------------------------------------------
# Remote payload configuration
#
# The installer is a BOOTSTRAP: when it does not find a local panel it downloads
# the panel ZIP straight from GitHub, unzips it and then runs the normal
# pipeline (deps -> self-heal -> build -> PM2 -> owner account).
# Override any of these with environment variables or flags:
#   PROTO_REPO=<owner/repo> bash install.sh          # different GitHub repo
#   PROTO_BRANCH=<name>     bash install.sh          # different branch/tag
#   PROTO_ZIP_URL=<url>     bash install.sh          # custom archive URL
#   bash install.sh --repo owner/repo --branch dev   # same, as flags
#   bash install.sh --zip /path/to/Proto-Panel.zip  # local file (offline)
#   bash install.sh --zip https://.../panel.zip     # explicit URL
#   PROTO_TARGET_DIR=<dir>  bash install.sh          # extraction target
#   PROTO_RUNTIME_MODE=local|docker bash install.sh  # headless runtime pick
#   PROTO_ZIP_SHA256=<hash> bash install.sh          # optional integrity check
# ----------------------------------------------------------------------------
PANEL_REPO="${PROTO_REPO:-stripathi02123-tech/proto-panel}"
PANEL_BRANCH="${PROTO_BRANCH:-main}"
PANEL_ZIP_URL="${PROTO_ZIP_URL:-}"
PANEL_ZIP_RELEASE_URL="https://github.com/${PANEL_REPO}/releases/latest/download/Proto-Panel.zip"
PANEL_ZIP_FALLBACK_URL="https://codeload.github.com/${PANEL_REPO}/zip/refs/heads/${PANEL_BRANCH}"
PANEL_TARGET_DIR="${PROTO_TARGET_DIR:-Proto-Panel}"
LOCAL_ZIP_ARG=""

# Headless runtime selection (also settable via --runtime docker|local)
RUN_CHOICE="${RUN_CHOICE:-}"
if [ -z "$RUN_CHOICE" ] && [ -n "${PROTO_RUNTIME_MODE:-}" ]; then
    case "$PROTO_RUNTIME_MODE" in
        docker|1) RUN_CHOICE="1" ;;
        local|node|nodejs|2) RUN_CHOICE="2" ;;
    esac
fi

CACHED_OS_TYPE=""
CACHED_SYS_ARCH=""
CACHED_SYS_IP=""

detect_os() {
    OS_TYPE="Linux"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE=${PRETTY_NAME:-${ID:-"Linux"}}
    elif command -v uname &> /dev/null; then
        OS_TYPE=$(uname -s)
    fi
}

get_sys_ip() {
    if [ -n "$CACHED_SYS_IP" ]; then
        echo "$CACHED_SYS_IP"
        return
    fi
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    fi
    if [ -z "$ip" ] || [ "$ip" = "127.0.0.1" ]; then
        ip=$(curl -s --connect-timeout 0.5 --max-time 0.8 ifconfig.me 2>/dev/null || echo "127.0.0.1")
    fi
    CACHED_SYS_IP="${ip:-127.0.0.1}"
    echo "$CACHED_SYS_IP"
}

check_port_active() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":$port " && return 0
    elif command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -q ":$port " && return 0
    elif [ -d "/proc/net" ]; then
        local hex=$(printf '%04X' "$port")
        grep -q ":$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null && return 0
    fi
    return 1
}

detect_sys_meta() {
    if [ -z "$CACHED_OS_TYPE" ]; then
        detect_os
        CACHED_OS_TYPE="$OS_TYPE"
        CACHED_SYS_ARCH=$(uname -m 2>/dev/null || echo "x86_64")
    fi
    OS_TYPE="$CACHED_OS_TYPE"
    SYS_ARCH="$CACHED_SYS_ARCH"
    SYS_RAM=$(free -h 2>/dev/null | awk '/^Mem:/{print $3 "/" $2}' || echo "N/A")
    SYS_IP=$(get_sys_ip)
    
    SYS_STATE="${GRAY}○ STOPPED${NC}"
    if check_port_active 6767; then
        SYS_STATE="${GREEN}● ONLINE (:6767)${NC}"
    elif check_port_active 3000; then
        SYS_STATE="${CYAN}● DEV MODE (:3000)${NC}"
    elif run_pm2 list 2>/dev/null | grep -q "proto-main.*online"; then
        SYS_STATE="${GREEN}● ONLINE (:6767)${NC}"
    elif run_pm2 list 2>/dev/null | grep -q "proto-admin.*online"; then
        SYS_STATE="${CYAN}● DEV MODE (:3000)${NC}"
    fi
}

print_banner() {
    if [ -t 1 ]; then
        clear 2>/dev/null || true
    fi
    detect_sys_meta
    echo -e "
  ${EMERALD}${BOLD}╭──────────────────────────────────────────────────────────────╮
  │  ${WHITE}██╗████████╗ ██████╗${EMERALD}   ${BOLD}${WHITE}PROTO CONTROL PANEL${EMERALD}                     │
  │  ${WHITE}██║╚══██╔══╝██╔════╝${EMERALD}   ${CYAN}Next-Gen Minecraft Server Manager${EMERALD}          │
  │  ${WHITE}██║   ██║   ██║  ███╗${EMERALD}  ${AMBER}v3.2.0${NC}${EMERALD} · ${GREEN}Production Ready${EMERALD}                      │
  ├──────────────────────────────────────────────────────────────┤
  │  ${GRAY}System :${NC} ${WHITE}${OS_TYPE} (${SYS_ARCH})${EMERALD}
  │  ${GRAY}Memory :${NC} ${WHITE}${SYS_RAM}${NC}   ${GRAY}IP:${NC} ${CYAN}${SYS_IP}${EMERALD}   ${GRAY}Status:${NC} ${SYS_STATE}${EMERALD}
  ╰──────────────────────────────────────────────────────────────╯${NC}
"
}

log_info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "  ${GREEN}✔${NC} $1"; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "  ${RED}✖${NC} $1"; }

run_pm2() {
    if command -v pm2 &> /dev/null; then
        pm2 "$@"
    elif [ -x "/usr/local/bin/pm2" ]; then
        /usr/local/bin/pm2 "$@"
    elif [ -x "./node_modules/.bin/pm2" ]; then
        ./node_modules/.bin/pm2 "$@"
    else
        return 1
    fi
}

get_docker_cmd() {
    if docker info > /dev/null 2>&1; then
        echo "docker"
    elif command -v sudo &> /dev/null && sudo docker info > /dev/null 2>&1; then
        echo "sudo docker"
    else
        echo "docker"
    fi
}

get_compose_cmd() {
    local d_cmd=$(get_docker_cmd)
    if $d_cmd compose version > /dev/null 2>&1; then
        echo "$d_cmd compose"
    elif command -v docker-compose > /dev/null 2>&1; then
        echo "docker-compose"
    elif command -v sudo &> /dev/null && sudo docker-compose version > /dev/null 2>&1; then
        echo "sudo docker-compose"
    else
        echo "$d_cmd compose"
    fi
}

run_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo > /dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

# ----------------------------------------------------------------------------
# ZIP FETCH / EXTRACT helpers (bootstrap phase)
# ----------------------------------------------------------------------------

http_get() {
    # http_get <url> <output-file>  (curl with wget fallback, retries included)
    # NOTE: progress output must stay on STDERR - callers capture stdout via $(...)
    local url="$1" out="$2"
    if command -v curl > /dev/null 2>&1; then
        curl -fSL --retry 3 --retry-delay 2 --connect-timeout 15 -o "$out" "$url"
    elif command -v wget > /dev/null 2>&1; then
        wget --tries=3 --timeout=20 -O "$out" "$url"
    else
        return 127
    fi
}

ensure_fetch_tools() {
    # Need: a downloader (curl or wget) + an unzip capability
    local need=""
    if ! command -v curl > /dev/null 2>&1 && ! command -v wget > /dev/null 2>&1; then
        need="curl"
    fi
    if ! command -v unzip > /dev/null 2>&1 \
       && ! command -v bsdtar > /dev/null 2>&1 \
       && ! command -v python3 > /dev/null 2>&1 \
       && ! command -v busybox > /dev/null 2>&1; then
        need="${need:+$need }unzip"
    fi
    if [ -z "$need" ]; then return 0; fi

    echo "  Installing required download tools:${need} ..."
    export DEBIAN_FRONTEND=noninteractive
    if command -v apt-get > /dev/null 2>&1; then
        run_root apt-get update -y -q > /dev/null 2>&1 || true
        run_root apt-get install -y -q $need ca-certificates > /dev/null 2>&1 || true
    elif command -v dnf > /dev/null 2>&1; then
        run_root dnf install -y -q $need ca-certificates > /dev/null 2>&1 || true
    elif command -v yum > /dev/null 2>&1; then
        run_root yum install -y -q $need ca-certificates > /dev/null 2>&1 || true
    elif command -v apk > /dev/null 2>&1; then
        run_root apk add --no-cache $need ca-certificates > /dev/null 2>&1 || true
    elif command -v pacman > /dev/null 2>&1; then
        run_root pacman -Sy --noconfirm $need > /dev/null 2>&1 || true
    elif command -v zypper > /dev/null 2>&1; then
        run_root zypper -n install $need > /dev/null 2>&1 || true
    fi

    command -v curl > /dev/null 2>&1 || command -v wget > /dev/null 2>&1 || {
        echo "Neither curl nor wget is available."; return 1;
    }
    command -v unzip > /dev/null 2>&1 || command -v bsdtar > /dev/null 2>&1 \
        || command -v python3 > /dev/null 2>&1 || command -v busybox > /dev/null 2>&1 \
        || { echo "No unzip capability available."; return 1; }
    return 0
}

fetch_panel_zip() {
    # Echos the path of the downloaded archive on STDOUT; all progress output
    # goes to STDERR because callers capture stdout via $(...).
    # Order: --zip argument (file or URL) -> PROTO_ZIP_URL -> live main-branch
    # source archive -> GitHub release asset (when one gets published).
    local dest="/tmp/proto-panel-download-$$.zip"
    local urls=()

    if [ -n "$LOCAL_ZIP_ARG" ]; then
        if [ -f "$LOCAL_ZIP_ARG" ]; then
            echo "$LOCAL_ZIP_ARG"
            return 0
        fi
        # looks like a URL -> try it first
        case "$LOCAL_ZIP_ARG" in
            http://*|https://*) urls+=("$LOCAL_ZIP_ARG") ;;
            *) echo "Archive not found: $LOCAL_ZIP_ARG" >&2; return 1 ;;
        esac
    fi
    [ -n "$PANEL_ZIP_URL" ] && urls+=("$PANEL_ZIP_URL")
    urls+=("$PANEL_ZIP_FALLBACK_URL" "$PANEL_ZIP_RELEASE_URL")

    local u
    for u in "${urls[@]}"; do
        echo "  Fetching panel archive from:" >&2
        echo "    $u" >&2
        rm -f "$dest"
        if http_get "$u" "$dest" && [ -s "$dest" ]; then
            # sanity check: must be a ZIP (PK\x03\x04), not an HTML error page
            if head -c 2 "$dest" | grep -q "PK"; then
                echo "$dest"
                return 0
            fi
            echo "  ...response was not a ZIP archive, trying next mirror" >&2
        fi
    done
    rm -f "$dest"
    echo "Could not download the panel archive from any source." >&2
    return 1
}

extract_zip_file() {
    # extract_zip_file <zip-file> <dest-dir>  (unzip -> bsdtar -> python3 -> busybox)
    local zip="$1" dest="$2"
    mkdir -p "$dest"
    if command -v unzip > /dev/null 2>&1; then
        unzip -q -o "$zip" -d "$dest"
    elif command -v bsdtar > /dev/null 2>&1; then
        bsdtar -xf "$zip" -C "$dest"
    elif command -v python3 > /dev/null 2>&1; then
        python3 - "$zip" "$dest" <<'PYEOF'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PYEOF
    elif command -v busybox > /dev/null 2>&1; then
        busybox unzip -o -q "$zip" -d "$dest"
    else
        echo "No unzip tool available."
        return 1
    fi
}

find_panel_payload() {
    # find_panel_payload <dir> <depth>
    # Locates the directory that actually holds the panel source (package.json).
    # Understands every layout the repo can ship:
    #   1. plain source tree            -> <dir>/package.json
    #   2. single GitHub wrapper dir    -> proto-panel-main/.../package.json
    #   3. zip-inside-zip               -> repo contains Proto-Panel-vX.zip
    # Echoes the payload dir on success, returns 1 when nothing is found.
    local dir="$1" depth="${2:-0}"
    [ -f "$dir/package.json" ] && { echo "$dir"; return 0; }

    # Case 2: a single top-level wrapper directory (GitHub branch archives)
    local count first
    count=$(ls -A "$dir" 2>/dev/null | wc -l | tr -d ' ')
    first=$(ls -A "$dir" 2>/dev/null | head -n 1)
    if [ "$count" = "1" ] && [ -d "$dir/$first" ]; then
        find_panel_payload "$dir/$first" "$depth" && return 0
    fi

    # Case 3: the repo ships the panel archive as a nested zip file
    if [ "$depth" -lt 3 ]; then
        local inner biggest="" biggest_size=0 s
        for inner in "$dir"/*.zip; do
            [ -f "$inner" ] || continue
            head -c 2 "$inner" 2>/dev/null | grep -q "PK" || continue
            s=$(stat -c %s "$inner" 2>/dev/null || wc -c < "$inner" 2>/dev/null || echo 0)
            if [ "$s" -gt "$biggest_size" ]; then
                biggest="$inner"; biggest_size=$s
            fi
        done
        if [ -n "$biggest" ]; then
            local sub="$dir/.unzipped-$depth-$$"
            mkdir -p "$sub"
            if extract_zip_file "$biggest" "$sub"; then
                find_panel_payload "$sub" $((depth + 1)) && return 0
            fi
            rm -rf "$sub"
        fi
    fi
    return 1
}

ensure_panel_payload() {
    # Make sure we are inside a panel checkout; if not, fetch the release ZIP
    # from GitHub, extract it into $PANEL_TARGET_DIR and cd into it.
    # Never touches .data/, backups/ or .env (they are never inside the zip).
    if [ -f "package.json" ]; then return 0; fi
    if [ -f "Proto/package.json" ]; then cd "Proto" || return 1; return 0; fi        # legacy clone layout
    if [ -f "$PANEL_TARGET_DIR/package.json" ]; then cd "$PANEL_TARGET_DIR" || return 1; return 0; fi

    log_info "No local panel found - fetching the latest release from GitHub..."
    ensure_fetch_tools || return 1

    local zip
    zip=$(fetch_panel_zip) || return 1

    # Optional integrity check
    if [ -n "${PROTO_ZIP_SHA256:-}" ]; then
        local actual=""
        if command -v sha256sum > /dev/null 2>&1; then
            actual=$(sha256sum "$zip" | awk '{print $1}')
        elif command -v shasum > /dev/null 2>&1; then
            actual=$(shasum -a 256 "$zip" | awk '{print $1}')
        fi
        if [ -n "$actual" ] && [ "$actual" != "$PROTO_ZIP_SHA256" ]; then
            echo "SHA-256 mismatch for the downloaded archive:"
            echo "  expected: $PROTO_ZIP_SHA256"
            echo "  actual:   $actual"
            [ "$zip" != "$LOCAL_ZIP_ARG" ] && rm -f "$zip"
            return 1
        fi
        log_success "Archive checksum verified."
    fi

    local tmp
    tmp=$(mktemp -d /tmp/proto-panel-extract.XXXXXX) || return 1

    echo "  Extracting archive..."
    if ! extract_zip_file "$zip" "$tmp"; then
        rm -rf "$tmp"; [ "$zip" != "$LOCAL_ZIP_ARG" ] && rm -f "$zip"
        echo "Failed to extract the panel archive."
        return 1
    fi

    # GitHub zips are wrapped in a single top-level directory (e.g.
    # proto-panel-main/ or Proto-Panel-3.2.0/). Strip it when present.
    local payload
    payload=$(find_panel_payload "$tmp" 0) || {
        rm -rf "$tmp"; [ "$zip" != "$LOCAL_ZIP_ARG" ] && rm -f "$zip"
        echo "The archive does not contain a Proto Panel installation (package.json missing)."
        return 1
    }

    mkdir -p "$PANEL_TARGET_DIR"
    # Overlay the payload; local runtime state (.data/.env/backups) is never in
    # the zip, so it survives untouched.
    cp -a "$payload"/. "$PANEL_TARGET_DIR"/
    rm -rf "$tmp"
    [ "$zip" != "$LOCAL_ZIP_ARG" ] && rm -f "$zip"

    log_success "Panel extracted to: $PANEL_TARGET_DIR"
    cd "$PANEL_TARGET_DIR" || return 1
    return 0
}

execute_step() {
    local msg="$1"
    shift
    local step_id="proto_step_$RANDOM"
    local log_file="/tmp/${step_id}.log"
    rm -f "$log_file"
    
    local is_optional=0
    case "$msg" in
        *"Java"*) is_optional=1 ;;
    esac

    printf "  ${GRAY}│${NC}  ${CYAN}⚙${NC}  %-44s " "$msg"
    
    # Run command in background and capture all stdout and stderr
    "$@" > "$log_file" 2>&1 &
    local pid=$!
    
    if [ -t 1 ]; then
        local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        while kill -0 $pid 2>/dev/null; do
            local temp=${spinstr#?}
            printf "${CYAN}[%c]${NC}" "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep 0.1
            printf "\b\b\b"
        done
    else
        while kill -0 $pid 2>/dev/null; do
            sleep 1
        done
    fi
    
    local status=0
    wait $pid 2>/dev/null || status=$?
    
    if [ $status -eq 0 ]; then
        printf "\r  ${GRAY}│${NC}  ${GREEN}✔${NC}  %-44s ${GREEN}[DONE]${NC}\n" "$msg"
    elif [ $is_optional -eq 1 ]; then
        printf "\r  ${GRAY}│${NC}  ${YELLOW}ℹ${NC}  %-44s ${YELLOW}[DOCKER JVM]${NC}\n" "$msg"
        return 0
    else
        printf "\r  ${GRAY}│${NC}  ${RED}✖${NC}  %-44s ${RED}[FAILED]${NC}\n" "$msg"
        echo -e "\n  ${RED}┌── STEP FAILED: $msg ──────────────────────────────┐${NC}"
        echo -e "  ${RED}│  Exit Code: $status${NC}"
        echo -e "  ${RED}│  Log details:${NC}"
        if [ -s "$log_file" ]; then
            tail -n 25 "$log_file" | sed 's/^/  │  /'
        else
            echo "  │  No error logs produced."
        fi
        echo -e "  ${RED}└───────────────────────────────────────────────────┘${NC}\n"
        exit 1
    fi
    return $status
}

check_system_deps() {
    detect_os
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    export UCF_FORCE_CONFFOLD=1

    local MISSING_DEPS=""
    for cmd in curl git tar jq; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            MISSING_DEPS="$MISSING_DEPS $cmd"
        fi
    done

    if [ -n "$MISSING_DEPS" ]; then
        if command -v apt-get > /dev/null 2>&1; then
            local APT_OPTS="-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::http::Timeout=10 -o Acquire::ftp::Timeout=10"
            if [ "$EUID" -eq 0 ]; then
                apt-get update $APT_OPTS > /dev/null 2>&1 || true
                apt-get install $APT_OPTS $MISSING_DEPS build-essential ca-certificates xz-utils > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo apt-get update $APT_OPTS > /dev/null 2>&1 || true
                sudo apt-get install $APT_OPTS $MISSING_DEPS build-essential ca-certificates xz-utils > /dev/null 2>&1 || true
            fi
        elif command -v yum > /dev/null 2>&1; then
            if [ "$EUID" -eq 0 ]; then
                yum update -y -q > /dev/null 2>&1 || true
                yum install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo yum update -y -q > /dev/null 2>&1 || true
                sudo yum install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            fi
        elif command -v dnf > /dev/null 2>&1; then
            if [ "$EUID" -eq 0 ]; then
                dnf install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo dnf install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            fi
        fi
    fi

    # Ensure swap if memory is low (< 2GB) and swap is low (< 512MB) to prevent OOM kills during build/run
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "2048")
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo "0")
    if [ -n "$total_mem" ] && [ "$total_mem" -lt 2000 ] && [ "$total_swap" -lt 512 ]; then
        if command -v swapon &> /dev/null && command -v sudo &> /dev/null; then
            if [ ! -f "/swapfile" ]; then
                if command -v fallocate &> /dev/null; then
                    sudo fallocate -l 2G /swapfile > /dev/null 2>&1 || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 > /dev/null 2>&1 || true
                else
                    sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 > /dev/null 2>&1 || true
                fi
                sudo chmod 600 /swapfile > /dev/null 2>&1 || true
                sudo mkswap /swapfile > /dev/null 2>&1 || true
                sudo swapon /swapfile > /dev/null 2>&1 || true
            else
                sudo swapon /swapfile > /dev/null 2>&1 || true
            fi
        fi
    fi

    for cmd in curl git tar; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Required system dependency '$cmd' is missing."
            return 1
        fi
    done
    return 0
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1 || true
        if command -v systemctl &> /dev/null; then
            sudo systemctl enable --now docker > /dev/null 2>&1 || true
        elif command -v service &> /dev/null; then
            sudo service docker start > /dev/null 2>&1 || true
        fi
    fi
    
    if ! command -v docker &> /dev/null; then
        echo "Docker could not be installed automatically. Please install Docker and retry."
        return 1
    fi
    
    # Check Docker daemon connectivity
    if ! docker info > /dev/null 2>&1; then
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker > /dev/null 2>&1 || true
        elif command -v service &> /dev/null; then
            sudo service docker start > /dev/null 2>&1 || true
        fi
        if ! docker info > /dev/null 2>&1; then
            if command -v sudo &> /dev/null && sudo docker info > /dev/null 2>&1; then
                sudo usermod -aG docker "$USER" 2>/dev/null || true
            else
                echo "Docker daemon is not running or current user lacks permission to access /var/run/docker.sock."
                return 1
            fi
        fi
    fi
    
    local d_cmd=$(get_docker_cmd)
    if ! $d_cmd compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose > /dev/null 2>&1 || true
        sudo chmod +x /usr/local/bin/docker-compose > /dev/null 2>&1 || true
    fi
    
    local c_cmd=$(get_compose_cmd)
    if ! $c_cmd version &> /dev/null; then
        echo "Docker Compose is required but could not be installed."
        return 1
    fi
    return 0
}

install_node() {
    local NEED_NODE=0
    if ! command -v node &> /dev/null; then
        NEED_NODE=1
    else
        local NODE_MAJOR=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
        if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 20 ]; then
            NEED_NODE=1
        fi
    fi

    if [ "$NEED_NODE" -eq 1 ]; then
        if command -v apt-get &> /dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1 || true
            sudo apt-get install -y nodejs > /dev/null 2>&1 || true
        fi
        
        local CURRENT_MAJOR=0
        if command -v node &> /dev/null; then
            CURRENT_MAJOR=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
        fi
        
        if [ "$CURRENT_MAJOR" -lt 20 ]; then
            local ARCH=$(uname -m)
            local NODE_ARCH="x64"
            case "$ARCH" in
                x86_64) NODE_ARCH="x64" ;;
                aarch64|arm64) NODE_ARCH="arm64" ;;
                armv7l) NODE_ARCH="armv7l" ;;
                *) NODE_ARCH="x64" ;;
            esac
            local NODE_DIST="node-v22.13.1-linux-${NODE_ARCH}"
            curl -fsSL "https://nodejs.org/dist/v22.13.1/${NODE_DIST}.tar.xz" -o /tmp/node22.tar.xz > /dev/null 2>&1 || true
            if [ -f "/tmp/node22.tar.xz" ]; then
                sudo tar -xJf /tmp/node22.tar.xz -C /usr/local --strip-components=1 > /dev/null 2>&1 || true
                rm -f /tmp/node22.tar.xz
            fi
        fi
    fi
    
    if ! command -v node &> /dev/null; then
        echo "Node.js (>=20) installation failed."
        return 1
    fi
    
    local VER=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
    if [ "$VER" -lt 20 ]; then
        echo "Node.js version must be >= 20. Current: $(node -v)"
        return 1
    fi

    if ! command -v npm &> /dev/null; then
        echo "npm is not installed."
        return 1
    fi
    return 0
}

install_java() {
    trap 'return 0' TERM INT

    # 1. Quick check: Is Java already working in PATH?
    if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
        echo "Java runtime already active: $(java -version 2>&1 | head -n 1)"
        return 0
    fi

    # 2. Check common JVM installation directories
    for cand in /usr/lib/jvm/java-21-openjdk-*/bin/java \
                /usr/lib/jvm/java-17-openjdk-*/bin/java \
                /usr/lib/jvm/default-java/bin/java \
                /usr/lib/jvm/java-11-openjdk-*/bin/java \
                /usr/lib/jvm/*-openjdk*/bin/java \
                /opt/java/bin/java \
                /opt/proto-java/bin/java \
                /usr/local/java/bin/java; do
        if [ -x "$cand" ]; then
            echo "Found existing JVM at: $cand"
            if [ "$EUID" -eq 0 ]; then
                ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            fi
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
                return 0
            fi
        fi
    done

    # 3. If Docker is available, host Java is not strictly required
    if command -v docker > /dev/null 2>&1; then
        echo "Docker detected. Minecraft servers will utilize containerized Java runtimes."
        return 0
    fi

    echo "Configuring OpenJDK runtime..."

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    export UCF_FORCE_CONFFOLD=1

    if command -v apt-get > /dev/null 2>&1; then
        local APT_OPTS="-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::http::Timeout=10 -o Acquire::ftp::Timeout=10"
        if [ "$EUID" -eq 0 ]; then
            apt-get install $APT_OPTS openjdk-21-jre-headless > /dev/null 2>&1 || \
            apt-get install $APT_OPTS openjdk-17-jre-headless > /dev/null 2>&1 || \
            apt-get install $APT_OPTS default-jre-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo apt-get install $APT_OPTS openjdk-21-jre-headless > /dev/null 2>&1 || \
            sudo apt-get install $APT_OPTS openjdk-17-jre-headless > /dev/null 2>&1 || \
            sudo apt-get install $APT_OPTS default-jre-headless > /dev/null 2>&1 || true
        fi
    elif command -v dnf > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            dnf install -y java-21-openjdk-headless > /dev/null 2>&1 || dnf install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo dnf install -y java-21-openjdk-headless > /dev/null 2>&1 || sudo dnf install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        fi
    elif command -v yum > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            yum install -y java-21-openjdk-headless > /dev/null 2>&1 || yum install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo yum install -y java-21-openjdk-headless > /dev/null 2>&1 || sudo yum install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        fi
    elif command -v apk > /dev/null 2>&1; then
        apk add --no-cache openjdk21-jre-headless > /dev/null 2>&1 || apk add --no-cache openjdk17-jre-headless > /dev/null 2>&1 || true
    elif command -v pacman > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            pacman -Sy --noconfirm jre21-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo pacman -Sy --noconfirm jre21-openjdk-headless > /dev/null 2>&1 || true
        fi
    fi

    # Check if package manager installed Java successfully
    if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
        return 0
    fi

    # Check discovered JVM directories again
    for cand in /usr/lib/jvm/java-21-openjdk-*/bin/java \
                /usr/lib/jvm/java-17-openjdk-*/bin/java \
                /usr/lib/jvm/default-java/bin/java \
                /usr/lib/jvm/*-openjdk*/bin/java; do
        if [ -x "$cand" ]; then
            if [ "$EUID" -eq 0 ]; then
                ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            fi
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1; then
                return 0
            fi
        fi
    done

    # 4. Direct lightweight headless JRE fallback via Adoptium
    local ARCH=$(uname -m)
    local ADOPT_ARCH=""
    case "$ARCH" in
        x86_64) ADOPT_ARCH="x64" ;;
        aarch64|arm64) ADOPT_ARCH="aarch64" ;;
        *) ADOPT_ARCH="" ;;
    esac

    if [ -n "$ADOPT_ARCH" ] && command -v curl > /dev/null 2>&1; then
        echo "Attempting fast binary runtime fetch..."
        local JRE_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/${ADOPT_ARCH}/jre/hotspot/normal/eclipse"
        curl -fsSL --connect-timeout 8 --max-time 45 "$JRE_URL" -o /tmp/proto_jre.tar.gz > /dev/null 2>&1 || true
        if [ -f "/tmp/proto_jre.tar.gz" ] && [ -s "/tmp/proto_jre.tar.gz" ]; then
            if [ "$EUID" -eq 0 ]; then
                mkdir -p /opt/proto-java
                tar -xzf /tmp/proto_jre.tar.gz -C /opt/proto-java --strip-components=1 > /dev/null 2>&1 || true
                if [ -x "/opt/proto-java/bin/java" ]; then
                    ln -sf /opt/proto-java/bin/java /usr/local/bin/java 2>/dev/null || true
                fi
            elif command -v sudo > /dev/null 2>&1; then
                sudo mkdir -p /opt/proto-java
                sudo tar -xzf /tmp/proto_jre.tar.gz -C /opt/proto-java --strip-components=1 > /dev/null 2>&1 || true
                if [ -x "/opt/proto-java/bin/java" ]; then
                    sudo ln -sf /opt/proto-java/bin/java /usr/local/bin/java 2>/dev/null || true
                fi
            fi
            rm -f /tmp/proto_jre.tar.gz 2>/dev/null || true
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1; then
                echo "Java OpenJDK runtime installed successfully."
                return 0
            fi
        fi
        rm -f /tmp/proto_jre.tar.gz 2>/dev/null || true
    fi

    echo "Notice: Host Java setup completed with container fallback."
    echo "Note: Docker-managed Minecraft servers will run using containerized Java."
    return 0
}

setup_docker_env() {
    install_docker
    cat << 'EOF2' > Dockerfile
FROM node:22-alpine
RUN apk add --no-cache docker-cli git make g++ python3 curl
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit --no-fund --legacy-peer-deps
COPY . .
RUN if [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then NODE_OPTIONS="--max-old-space-size=2048" npm run build; fi
EXPOSE 6767 6868
CMD ["npm", "start"]
EOF2
    
    if [ ! -f "docker-compose.yml" ]; then
        cat << 'EOF2' > docker-compose.yml
version: '3.8'
services:
  proto-main:
    build: .
    container_name: proto-main
    restart: unless-stopped
    ports:
      - "6767:6767"
      - "6868:6868"
    environment:
      - NODE_ENV=production
      - PORT=6767
      - PROTO_HOST_DATA_PATH=${PWD}/.data
      - PROTO_OWNER_USER=${PROTO_OWNER_USER:-}
      - PROTO_OWNER_PASS=${PROTO_OWNER_PASS:-}
    volumes:
      - ./.data:/app/.data
      - ./backups:/app/backups
      - /var/run/docker.sock:/var/run/docker.sock

  proto-admin:
    build: .
    container_name: proto-admin
    restart: unless-stopped
    command: npm run dev
    ports:
      - "3000:3000"
      - "6869:6869"
    environment:
      - NODE_ENV=development
      - PORT=3000
      - PROTO_HOST_DATA_PATH=${PWD}/.data
      - PROTO_OWNER_USER=${PROTO_OWNER_USER:-}
      - PROTO_OWNER_PASS=${PROTO_OWNER_PASS:-}
    volumes:
      - ./.data:/app/.data
      - ./backups:/app/backups
      - /var/run/docker.sock:/var/run/docker.sock
EOF2
    fi
}

setup_node_env() {
    local RUNTIME_PREF=$1
    install_node

    if ! command -v pm2 &> /dev/null && [ ! -x "/usr/local/bin/pm2" ] && [ ! -x "./node_modules/.bin/pm2" ]; then
        if [ "$EUID" -eq 0 ]; then
            npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        elif command -v sudo &> /dev/null; then
            sudo npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        else
            npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        fi
    fi
    
    local DEFAULT_RT="docker"
    local ENABLE_DOCKER="true"
    
    if [ "$RUNTIME_PREF" = "local" ]; then
        DEFAULT_RT="local"
        ENABLE_DOCKER="false"
    else
        # Ensure Docker is ready on host for Minecraft server containers
        if ! command -v docker &> /dev/null; then
            echo "Installing Docker for Minecraft server containers..."
            install_docker 2>/dev/null || true
        fi
        if command -v systemctl &> /dev/null; then
            systemctl enable --now docker 2>/dev/null || sudo systemctl enable --now docker 2>/dev/null || true
        elif command -v service &> /dev/null; then
            service docker start 2>/dev/null || sudo service docker start 2>/dev/null || true
        fi
        if [ -S "/var/run/docker.sock" ]; then
            chmod 666 /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        fi
    fi
    
    cat << EOF2 > ecosystem.config.cjs
module.exports = {
  apps: [
    {
      name: "proto-main",
      script: "npm",
      args: "start",
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: "1G",
      env: {
        NODE_ENV: "production",
        PORT: 6767,
        DEFAULT_RUNTIME: "${DEFAULT_RT}",
        ENABLE_DOCKER: "${ENABLE_DOCKER}",
        DOCKER_SOCKET_PATH: "/var/run/docker.sock"
      }
    },
    {
      name: "proto-admin",
      script: "npm",
      args: "run dev",
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: "2G",
      env: {
        NODE_ENV: "development",
        PORT: 3000,
        DEFAULT_RUNTIME: "${DEFAULT_RT}",
        ENABLE_DOCKER: "${ENABLE_DOCKER}",
        DOCKER_SOCKET_PATH: "/var/run/docker.sock"
      }
    }
  ]
};
EOF2
}

# ----------------------------------------------------------------------------
# Native binding verification & self-healing (npm optional-deps bug, npm/cli#4828)
#
# DESIGN FIX: npm can silently skip platform-specific OPTIONAL dependencies
# (@tailwindcss/oxide-linux-x64-gnu, lightningcss-linux-x64-gnu,
# @esbuild/linux-x64, @rollup/rollup-linux-x64-gnu, ...) when a
# package-lock.json generated on another machine/arch is present.
# The old installer only checked that directories/binaries existed, so a
# broken tree passed as "installed" and 'vite build' crashed while loading
# vite.config.ts with:  "Error: Cannot find native binding".
# These helpers actually LOAD every native module and, when one is broken,
# wipe node_modules + package-lock.json so npm re-resolves for THIS platform.
# ----------------------------------------------------------------------------
native_bindings_ok() {
    command -v node > /dev/null 2>&1 || return 1
    [ -d "node_modules" ] || return 1

    local mods=()
    [ -d "node_modules/@tailwindcss/oxide" ] && mods+=("@tailwindcss/oxide")
    [ -d "node_modules/lightningcss" ]      && mods+=("lightningcss")
    [ -d "node_modules/esbuild" ]           && mods+=("esbuild")
    [ -d "node_modules/rollup" ]            && mods+=("rollup")
    [ -d "node_modules/@swc/core" ]         && mods+=("@swc/core")

    local m
    for m in "${mods[@]}"; do
        node -e "require('${m}')" > /dev/null 2>&1 || return 1
    done
    return 0
}

clean_reinstall_deps() {
    local heal_log="/tmp/proto_npm_heal_$$.log"
    echo "Self-heal: removing node_modules + package-lock.json and re-installing for this platform..."
    rm -rf node_modules package-lock.json
    npm install --no-audit --no-fund --legacy-peer-deps > "$heal_log" 2>&1 || \
    npm install --no-audit --no-fund --legacy-peer-deps --force >> "$heal_log" 2>&1
    local st=$?
    if [ $st -ne 0 ]; then
        echo "Clean re-install failed. Last output:"
        tail -n 20 "$heal_log" | sed 's/^/  │  /'
    fi
    rm -f "$heal_log"
    return $st
}

rebuild_native_deps() {
    # Light heal: npm >= 11.4 blocks package install scripts by default
    # ("npm warn install-scripts"), which leaves esbuild & friends without
    # their downloaded native binaries. 'npm rebuild' re-runs those scripts.
    echo "Rebuilding native build modules (esbuild / tailwindcss-oxide / lightningcss / rollup)..."
    npm rebuild esbuild @tailwindcss/oxide lightningcss rollup > /dev/null 2>&1 || true
}

heal_native_deps() {
    # Full heal ladder: rebuild (install-scripts blocking) -> clean reinstall
    # (lockfile/platform mismatch, npm/cli#4828) -> rebuild again -> verify.
    if ! native_bindings_ok; then
        rebuild_native_deps
    fi
    if ! native_bindings_ok; then
        clean_reinstall_deps || true
        rebuild_native_deps
    fi
    native_bindings_ok
}

install_dependencies() {
    if [ ! -f "package.json" ]; then
        echo "Error: package.json not found in $(pwd)."
        return 1
    fi
    if [ -d "node_modules" ] && \
       [ -d "node_modules/express" ] && \
       [ -d "node_modules/react" ] && \
       [ -d "node_modules/vite" ] && \
       [ -x "node_modules/.bin/vite" ] && \
       [ -x "node_modules/.bin/esbuild" ] && \
       [ -x "node_modules/.bin/tsx" ] && \
       native_bindings_ok; then
        return 0
    fi
    echo "Installing panel dependencies..."
    npm install --no-audit --no-fund --legacy-peer-deps 2>&1 || npm install --no-audit --no-fund --legacy-peer-deps --force 2>&1
    
    if [ ! -d "node_modules/express" ] || [ ! -x "node_modules/.bin/vite" ]; then
        echo "Failed to install critical npm dependencies."
        return 1
    fi

    # DESIGN FIX: verify the native build modules really load; heal npm bug 4828
    # and the npm>=11.4 install-scripts blocking before building anything.
    if ! native_bindings_ok; then
        echo "Warning: platform native modules missing (npm optional-deps / install-scripts issue)."
        if ! heal_native_deps; then
            echo "Native build modules are still unavailable after self-healing."
            return 1
        fi
        echo "Native modules verified after self-healing."
    fi
    return 0
}

setup_owner() {
    npm run createuser
}

setup_owner_docker() {
    local TARGET=$1
    if [ -n "$PROTO_OWNER_USER" ] && [ -n "$PROTO_OWNER_PASS" ]; then
        local DOCKER_CLI=$(get_docker_cmd)
        sleep 2
        $DOCKER_CLI exec -e PROTO_OWNER_USER="$PROTO_OWNER_USER" -e PROTO_OWNER_PASS="$PROTO_OWNER_PASS" "$TARGET" npm run createuser 2>&1 || {
            if command -v node &> /dev/null && [ -f "scripts/createuser.ts" ] && [ -d "node_modules" ]; then
                npm run createuser 2>&1 || true
            fi
        }
    fi
}

build_application() {
    echo "Building application bundle..."
    rm -rf dist
    export NODE_OPTIONS="--max-old-space-size=2048"
    local build_log="/tmp/proto_build_$$.log"
    npm run build > "$build_log" 2>&1
    local status=$?

    # DESIGN FIX: if the failure is the missing-native-binding class
    # (npm/cli#4828 / blocked install scripts), heal the dependency tree and
    # retry once instead of killing the whole install at the build stage.
    if [ $status -ne 0 ] && grep -qiE "Cannot find native binding|npm has a bug related to optional dependencies|Cannot find module '@rollup|Cannot find module '@esbuild|Could not load lightningcss|ERR_DLOPEN_FAILED|no native build was found" "$build_log" 2>/dev/null; then
        echo "Build hit missing native bindings - healing dependencies and retrying once..."
        heal_native_deps || true
        rm -rf dist
        npm run build > "$build_log" 2>&1
        status=$?
    fi

    if [ $status -ne 0 ] || [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then
        echo "Build failed: dist/server.cjs or dist/index.html is missing."
        echo "--- Last build output ---"
        tail -n 30 "$build_log" 2>/dev/null | sed 's/^/  /'
        rm -f "$build_log"
        return 1
    fi
    rm -f "$build_log"
    return 0
}

start_panel_docker() {
    local TARGET=$1
    local DOCKER_CLI=$(get_docker_cmd)
    local COMPOSE_CLI=$(get_compose_cmd)

    export PWD=$(pwd)

    # Free up port from PM2 if it was previously running under local Node.js
    if command -v pm2 &> /dev/null || [ -f "node_modules/.bin/pm2" ]; then
        run_pm2 delete "$TARGET" > /dev/null 2>&1 || true
        if [ "$TARGET" = "proto-main" ]; then
            run_pm2 delete "proto-panel" > /dev/null 2>&1 || true
        fi
    fi

    # Remove any existing container with the same name to prevent naming collision
    $DOCKER_CLI rm -f "$TARGET" > /dev/null 2>&1 || true

    # Pre-build on host if node/npm are present and dist is not yet built (saves container memory)
    if [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then
        if command -v npm &> /dev/null && [ -d "node_modules" ]; then
            NODE_OPTIONS="--max-old-space-size=2048" npm run build > /dev/null 2>&1 || true
        fi
    fi

    echo "Starting container $TARGET via $COMPOSE_CLI..."
    if ! $COMPOSE_CLI up -d --build "$TARGET"; then
        echo "Docker Compose command failed to build or start $TARGET."
        echo "--- Docker Compose Logs ---"
        $COMPOSE_CLI logs --tail 50 "$TARGET" 2>&1 || true
        return 1
    fi
    
    local container_status=""
    local check_attempts=0
    while [ $check_attempts -lt 15 ]; do
        sleep 2
        container_status=$($DOCKER_CLI inspect --format '{{.State.Status}}' "$TARGET" 2>/dev/null || echo "not_found")
        if [ "$container_status" = "running" ]; then
            break
        elif [ "$container_status" = "exited" ] || [ "$container_status" = "dead" ]; then
            echo "Docker container $TARGET failed to start. Status: $container_status"
            echo "--- Docker Logs for $TARGET ---"
            $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
            return 1
        fi
        check_attempts=$((check_attempts + 1))
    done

    if [ "$container_status" != "running" ]; then
        echo "Docker container $TARGET is not in running state (Status: $container_status)."
        echo "--- Container Status ---"
        $DOCKER_CLI ps -a --filter "name=$TARGET" 2>&1 || true
        echo "--- Docker Logs for $TARGET ---"
        $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
        return 1
    fi
    return 0
}

start_panel_node() {
    local TARGET=$1
    if [ "$TARGET" = "proto-main" ]; then
        run_pm2 delete proto-panel 2>/dev/null || true
        # Clean up conflicting Docker container if previously running via Docker
        local DOCKER_CLI=$(get_docker_cmd)
        $DOCKER_CLI rm -f proto-main proto-panel 2>/dev/null || true
    fi
    # Ensure Docker daemon is running and socket accessible for Minecraft containers
    if command -v systemctl &> /dev/null; then
        systemctl enable --now docker 2>/dev/null || sudo systemctl enable --now docker 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service docker start 2>/dev/null || sudo service docker start 2>/dev/null || true
    fi
    if [ -S "/var/run/docker.sock" ]; then
        chmod 666 /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    fi
    run_pm2 delete "$TARGET" 2>/dev/null || true
    run_pm2 start ecosystem.config.cjs --only "$TARGET"
    run_pm2 save --force 2>/dev/null || true
}

health_check() {
    local PORT=$1
    local RUNTIME_TYPE=$2
    local TARGET=$3
    local ATTEMPTS=0
    local MAX_ATTEMPTS=30
    local DOCKER_CLI=$(get_docker_cmd)

    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if curl -s -f "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1 || curl -s -f "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
            return 0
        fi
        
        if [ "$RUNTIME_TYPE" = "docker" ]; then
            local cstatus=$($DOCKER_CLI inspect --format '{{.State.Status}}' "$TARGET" 2>/dev/null || echo "not_found")
            if [ "$cstatus" = "exited" ] || [ "$cstatus" = "dead" ] || [ "$cstatus" = "not_found" ]; then
                echo "Container $TARGET is not running during health check (Status: $cstatus)."
                echo "--- Logs for $TARGET ---"
                $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
                return 1
            fi
        else
            if run_pm2 list 2>/dev/null | grep "$TARGET" | grep -qE "errored|stopped"; then
                echo "PM2 process $TARGET crashed or stopped."
                echo "--- Logs for $TARGET ---"
                run_pm2 logs "$TARGET" --lines 40 --nostream 2>&1 || true
                return 1
            fi
        fi
        
        sleep 2
        ATTEMPTS=$((ATTEMPTS + 1))
    done

    echo "Health check timed out waiting for application on port $PORT."
    if [ "$RUNTIME_TYPE" = "docker" ]; then
        echo "--- Container Status ---"
        $DOCKER_CLI ps -a --filter "name=$TARGET" || true
        echo "--- Docker Logs ---"
        $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
    else
        echo "--- PM2 Status ---"
        run_pm2 list || true
        echo "--- PM2 Logs ---"
        run_pm2 logs "$TARGET" --lines 50 --nostream || true
    fi
    return 1
}

check_port() {
    local PORT=$1
    if command -v ss &> /dev/null; then
        if ss -lnt | grep -q ":$PORT "; then return 1; fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$PORT "; then return 1; fi
    elif command -v lsof &> /dev/null; then
        if lsof -i :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then return 1; fi
    fi
    return 0
}

show_status() {
    detect_sys_meta
    local MAIN_STATUS="${RED}● OFFLINE${NC}"
    local DEV_STATUS="${RED}● OFFLINE${NC}"
    local SFTP_STATUS="${RED}● OFFLINE${NC}"
    
    if check_port_active 6767 || (run_pm2 list 2>/dev/null | grep "proto-main" | grep -q "online") || (command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^proto-main$"); then
        MAIN_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    if check_port_active 3000 || (run_pm2 list 2>/dev/null | grep "proto-admin" | grep -q "online") || (command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^proto-admin$"); then
        DEV_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    if [ "$MAIN_STATUS" = "${GREEN}● ONLINE${NC}" ] || [ "$DEV_STATUS" = "${GREEN}● ONLINE${NC}" ]; then
        SFTP_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    echo ""
    echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║                    PROTO PANEL LIVE STATUS                     ║"
    echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ║                                                              ║"
    echo -e "  ║  • Main Panel       : ${MAIN_STATUS} ${CYAN}http://${SYS_IP}:6767${NC}"
    echo -e "  ║  • Developer Panel  : ${DEV_STATUS} ${CYAN}http://${SYS_IP}:3000${NC}"
    echo -e "  ║  • SFTP Service     : ${SFTP_STATUS} ${YELLOW}Port 2022${NC}"
    echo -e "  ║  • Host Memory      : ${WHITE}${SYS_RAM}${NC}"
    echo -e "  ║  • Host System      : ${WHITE}${OS_TYPE} (${SYS_ARCH})${NC}"
    echo -e "  ║                                                              ║"
    echo -e "  ${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

install_panel() {
    local TARGET=$1
    local PANEL_NAME="Main Panel"
    local PORT="6767"
    local SERVICE_NAME="proto-main"
    
    if [ "$TARGET" = "dev" ]; then
        PANEL_NAME="Developer Panel"
        PORT="3000"
        SERVICE_NAME="proto-admin"
    fi

    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}SELECT RUNTIME ENVIRONMENT${NC} ${GRAY}─────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}${BOLD}[1]${NC}  ${WHITE}${BOLD}Node.js + PM2 (Recommended)${NC}                                ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Panel runs natively via PM2 on host                     ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Minecraft servers run in isolated Docker containers      ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}${BOLD}[2]${NC}  ${WHITE}${BOLD}Pure Local Node.js${NC}                                        ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Panel and servers run directly on host                   ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${YELLOW}${BOLD}[3]${NC}  ${WHITE}${BOLD}Back to Main Menu${NC}                                         ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    local MODE_CHOICE=""
    if [ -n "$RUN_CHOICE" ]; then
        MODE_CHOICE="$RUN_CHOICE"
    elif [ ! -t 0 ]; then
        MODE_CHOICE="1"
    else
        echo -ne "  ${CYAN}╭──${NC} ${BOLD}Choose runtime mode [1-3]${NC}: "
        read -r MODE_CHOICE
    fi

    if [ "$MODE_CHOICE" = "3" ]; then
        return
    fi

    if [ "$MODE_CHOICE" != "1" ] && [ "$MODE_CHOICE" != "2" ]; then
        log_error "Invalid selection: '$MODE_CHOICE'"
        sleep 1
        return
    fi
    
    if [ "$TARGET" = "main" ]; then
        print_banner
        echo -e "  ${GRAY}┌──${NC} ${BOLD}CREATE OWNER ACCOUNT${NC} ${GRAY}───────────────────────────────────────┐${NC}"
        echo -e "  ${GRAY}│${NC}  Set login credentials for the primary administrator account: ${GRAY}│${NC}"
        echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
        
        local OWNER_USER=""
        local OWNER_PASS=""
        local OWNER_PASS2=""
        
        if [ -n "$PROTO_OWNER_USER" ] && [ -n "$PROTO_OWNER_PASS" ]; then
            OWNER_USER="$PROTO_OWNER_USER"
            OWNER_PASS="$PROTO_OWNER_PASS"
        elif [ ! -t 0 ]; then
            # DESIGN FIX: never fall back to a static weak password in
            # non-interactive mode - generate a random one and show it.
            OWNER_USER="owner"
            OWNER_PASS="$(head -c 24 /dev/urandom | base64 2>/dev/null | tr -dc 'A-Za-z0-9' | head -c 16)"
            [ "${#OWNER_PASS}" -ge 8 ] || OWNER_PASS="proto-$(date +%s)"
            echo -e "  ${YELLOW}⚠ Non-interactive mode: generated owner credentials${NC}"
            echo -e "  ${GRAY}│${NC}  ${BOLD}Username${NC}: ${WHITE}${OWNER_USER}${NC}"
            echo -e "  ${GRAY}│${NC}  ${BOLD}Password${NC}: ${WHITE}${OWNER_PASS}${NC}"
        else
            while true; do
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Username${NC} (min 3 chars): "
                read -r OWNER_USER
                if [ ${#OWNER_USER} -ge 3 ]; then
                    break
                else
                    echo -e "  ${YELLOW}⚠ Username must be at least 3 characters. Try again.${NC}"
                fi
            done
            
            while true; do
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Password${NC} (min 6 chars): "
                read -r -s OWNER_PASS
                echo ""
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Confirm Password${NC}       : "
                read -r -s OWNER_PASS2
                echo ""
                if [ ${#OWNER_PASS} -lt 6 ]; then
                    echo -e "  ${YELLOW}⚠ Password must be at least 6 characters. Try again.${NC}"
                elif [ "$OWNER_PASS" = "$OWNER_PASS2" ] && [ -n "$OWNER_PASS" ]; then
                    break
                else
                    echo -e "  ${YELLOW}⚠ Passwords do not match or are empty. Try again.${NC}"
                fi
            done
        fi
        echo -e "  ${GRAY}└───${NC}"
        echo ""
        
        export PROTO_OWNER_USER="$OWNER_USER"
        export PROTO_OWNER_PASS="$OWNER_PASS"
    fi
    
    # Environment Setup
    mkdir -p .data backups
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
        else
            echo "PORT=6767" > .env
            echo "JWT_SECRET=$(head -c 32 /dev/urandom | base64 2>/dev/null || openssl rand -base64 32)" >> .env
        fi
    fi

    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}INSTALLATION PROGRESS${NC} ${GRAY}───────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"

    execute_step "System Requirement Check" check_system_deps
    
    if [ "$MODE_CHOICE" = "1" ] || [ "$MODE_CHOICE" = "2" ]; then
        local RUNTIME_ARG="docker"
        if [ "$MODE_CHOICE" = "1" ]; then
            RUNTIME_ARG="docker"
            execute_step "Docker Engine Setup & Check" install_docker
            execute_step "Java Runtime Environment Check" install_java
            execute_step "Node.js & PM2 Environment Setup" setup_node_env "docker"
        else
            RUNTIME_ARG="local"
            execute_step "Java Runtime Environment" install_java
            execute_step "Node.js & PM2 Environment Setup" setup_node_env "local"
        fi
        execute_step "NPM Dependencies Installation" install_dependencies
        if [ "$TARGET" = "main" ]; then
            execute_step "Owner Account Provisioning" setup_owner
            execute_step "Application Production Build" build_application
            execute_step "PM2 Background Service Launch" start_panel_node proto-main
            execute_step "Application Verification (Port 6767)" health_check 6767 pm2 proto-main
        else
            execute_step "Application Production Build" build_application
            execute_step "PM2 Background Service Launch" start_panel_node proto-admin
            execute_step "Application Verification (Port 3000)" health_check 3000 pm2 proto-admin
        fi
    fi
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    detect_sys_meta
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║  ✔  INSTALLATION COMPLETED & VERIFIED SUCCESSFULLY           ║"
    echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ║                                                              ║"
    if [ "$TARGET" = "main" ]; then
        echo -e "  ║  • Access URL    : ${CYAN}http://${SYS_IP}:6767${NC}                        "
        echo -e "  ║  • Username      : ${WHITE}${OWNER_USER}${NC}                                  "
        echo -e "  ║  • Password      : ${WHITE}${OWNER_PASS}${NC}                                  "
        echo -e "  ║  • SFTP Port     : ${YELLOW}2022${NC} (Built-in Web & SFTP Server)         "
    else
        echo -e "  ║  • Access URL    : ${CYAN}http://${SYS_IP}:3000${NC} (Developer Panel)        "
    fi
    echo -e "  ║  • Process       : ${GREEN}Managed via PM2 (Auto-restarts enabled)${NC}      "
    echo -e "  ║                                                              ║"
    echo -e "  ║  ${BOLD}Helpful Commands:${NC}                                          ║"
    echo -e "  ║    pm2 status         - View running panel processes         ║"
    echo -e "  ║    pm2 logs $SERVICE_NAME   - Stream live console logs              ║"
    echo -e "  ║    bash update.sh     - Update panel anytime                 ║"
    echo -e "  ║                                                              ║"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

update_panel() {
    if [ ! -f "update.sh" ]; then
        log_error "update.sh not found."
        return
    fi
    bash update.sh
}

create_owner_user() {
    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}SETUP OWNER ACCOUNT${NC} ${GRAY}─────────────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    
    local OWNER_USER=""
    local OWNER_PASS=""
    local OWNER_PASS2=""
    
    while true; do
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Username${NC} (min 3 chars): "
        read -r OWNER_USER
        if [ ${#OWNER_USER} -ge 3 ]; then
            break
        else
            echo -e "  ${YELLOW}⚠ Username must be at least 3 characters. Try again.${NC}"
        fi
    done
    
    while true; do
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Password${NC} (min 6 chars): "
        read -r -s OWNER_PASS
        echo ""
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Confirm Password${NC}       : "
        read -r -s OWNER_PASS2
        echo ""
        if [ ${#OWNER_PASS} -lt 6 ]; then
            echo -e "  ${YELLOW}⚠ Password must be at least 6 characters. Try again.${NC}"
        elif [ "$OWNER_PASS" = "$OWNER_PASS2" ] && [ -n "$OWNER_PASS" ]; then
            break
        else
            echo -e "  ${YELLOW}⚠ Passwords do not match or are empty. Try again.${NC}"
        fi
    done
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    export PROTO_OWNER_USER="$OWNER_USER"
    export PROTO_OWNER_PASS="$OWNER_PASS"
    execute_step "Setting up Owner Account" setup_owner
    log_success "Owner user setup completed successfully!"
}

uninstall_panel() {
    if [ -f "uninstall.sh" ]; then
        bash uninstall.sh "$@"
        exit 0
    elif [ -n "$PANEL_ROOT" ] && [ -f "$PANEL_ROOT/uninstall.sh" ]; then
        bash "$PANEL_ROOT/uninstall.sh" "$@"
        exit 0
    elif [ -f "$PANEL_TARGET_DIR/uninstall.sh" ]; then
        bash "$PANEL_TARGET_DIR/uninstall.sh" "$@"
        exit 0
    elif [ -f "/opt/proto/uninstall.sh" ]; then
        bash "/opt/proto/uninstall.sh" "$@"
        exit 0
    elif [ -f "$HOME/Proto/uninstall.sh" ]; then
        bash "$HOME/Proto/uninstall.sh" "$@"
        exit 0
    else
        log_error "uninstall.sh script not found."
        return
    fi
}

# ----------------------------------------------------------------------------
# Entry point: parse bootstrap flags, fetch the panel payload when needed,
# then dispatch (direct mode or interactive menu).
# ----------------------------------------------------------------------------

# Flags: --zip <file|url>  --dir <target>  --runtime docker|local
#        --repo <owner/repo>  --branch <name>
# (positional "main" / "dev" and a bare "Proto-Panel.zip" argument still work)
while [ $# -gt 0 ]; do
    case "$1" in
        --zip|--archive)
            LOCAL_ZIP_ARG="$2"; shift 2 ;;
        --repo)
            PANEL_REPO="$2"; PANEL_ZIP_FALLBACK_URL="https://codeload.github.com/${PANEL_REPO}/zip/refs/heads/${PANEL_BRANCH}"; PANEL_ZIP_RELEASE_URL="https://github.com/${PANEL_REPO}/releases/latest/download/Proto-Panel.zip"; shift 2 ;;
        --branch)
            PANEL_BRANCH="$2"; PANEL_ZIP_FALLBACK_URL="https://codeload.github.com/${PANEL_REPO}/zip/refs/heads/${PANEL_BRANCH}"; shift 2 ;;
        --dir|--target)
            PANEL_TARGET_DIR="$2"; shift 2 ;;
        --runtime)
            case "$2" in
                docker|1) RUN_CHOICE="1" ;;
                local|node|nodejs|2) RUN_CHOICE="2" ;;
            esac
            shift 2 ;;
        main|dev)
            break ;;
        *.zip)
            LOCAL_ZIP_ARG="$1"; shift ;;
        *)
            shift ;;
    esac
done

# BOOTSTRAP: fetch the release zip from GitHub + extract it when no local
# panel is present (skipped automatically when run inside an existing panel).
if ! ensure_panel_payload; then
    echo -e "  ${RED}✖${NC} Could not obtain the Proto Panel payload. Check your network connection"
    echo -e "    or pass a local archive: ${CYAN}bash install.sh --zip Proto-Panel.zip${NC}"
    exit 1
fi

# Direct invocation support: bash install.sh main / bash install.sh dev
if [ "${1:-}" = "main" ]; then
    install_panel "main"
    exit 0
elif [ "${1:-}" = "dev" ]; then
    install_panel "dev"
    exit 0
fi

while true; do
    print_banner
    echo -e "  ${EMERALD}${BOLD}╭──${NC} ${BOLD}${WHITE}CONTROL MENU${NC} ${EMERALD}─────────────────────────────────────────╮${NC}"
    echo -e "  ${EMERALD}│${NC}                                                              ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${GREEN}${BOLD}[1]${NC}  ${WHITE}${BOLD}Initialize Main Panel${NC}     ${GRAY}Production Mode (:6767)         ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${CYAN}${BOLD}[2]${NC}  ${WHITE}${BOLD}Initialize Dev Panel${NC}      ${GRAY}Developer Mode (:3000)          ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${AMBER}${BOLD}[3]${NC}  ${WHITE}${BOLD}Update & Auto-Repair${NC}      ${GRAY}Self-Healing Requirement Check  ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${VIOLET}${BOLD}[4]${NC}  ${WHITE}${BOLD}Create / Reset Owner${NC}      ${GRAY}Setup Administrator Account     ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${BLUE}${BOLD}[5]${NC}  ${WHITE}${BOLD}System & Service Status${NC}   ${GRAY}Live Port, RAM & Health Monitor ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${RED}${BOLD}[6]${NC}  ${WHITE}${BOLD}Uninstall Proto Panel${NC}       ${GRAY}Clean Removal & Service Wipe   ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}  ${GRAY}${BOLD}[0]${NC}  ${WHITE}${BOLD}Exit Installer${NC}            ${GRAY}Close this terminal menu       ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}│${NC}                                                              ${EMERALD}│${NC}"
    echo -e "  ${EMERALD}╰─────────────────────────────────────────────────────────────╯${NC}"
    echo ""
    echo -ne "  ${EMERALD}▶${NC} ${BOLD}Choose option [0-6]${NC}: "
    if ! read -r CHOICE; then
        echo ""
        break
    fi
    case "$CHOICE" in
        1)
            install_panel "main"
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        2)
            install_panel "dev"
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        3)
            update_panel
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        4)
            create_owner_user
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        5)
            show_status
            if [ -t 0 ]; then read -p "  Press Enter to return to main menu..." || true; fi
            ;;
        6)
            uninstall_panel
            exit 0
            ;;
        0|exit|q)
            echo -e "\n  ${GREEN}✔ Goodbye! Have a great time managing your Minecraft servers.${NC}\n"
            exit 0
            ;;
        *)
            log_error "Invalid option selected: '$CHOICE'"
            sleep 1.2
            ;;
    esac
done
