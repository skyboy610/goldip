#!/bin/bash

BACKHAUL_BIN="/usr/local/bin/backhaul"
BACKHAUL_ARCHIVE="/tmp/backhaul_linux_amd64.tar.gz"
BACKHAUL_URL_PRIMARY="https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
BACKHAUL_URL_BACKUP="https://goldip.me/backhaul_linux_amd64.tar.gz"
SNIFFER_LOG="/root/backhaul.json"
TUNNEL_DB="/root/.goldip_tunnels.json"
MONITOR_PID_FILE="/var/run/goldip_monitor.pid"

declare -A COLORS=(
    [RESET]='\033[0m'
    [RED]='\033[38;5;196m'
    [GREEN]='\033[38;5;46m'
    [PINK]='\033[38;5;213m'
    [CYAN]='\033[38;5;51m'
    [YELLOW]='\033[38;5;226m'
    [ORANGE]='\033[38;5;208m'
    [NEWPINK]='\033[38;2;243;67;149m'
    [NEWORANGE]='\033[38;2;227;106;113m'
    [BLUE]='\033[38;5;33m'
    [OLIVE]='\033[38;5;142m'
    [PURPLE]='\033[38;5;93m'
    [MAGENTA]='\033[38;5;201m'
    [WHITE]='\033[97m'
    [BG_GREEN]='\033[48;5;28m'
    [BG_RED]='\033[48;5;196m'
    [BG_YELLOW]='\033[48;5;220m'
    [BG_BLUE]='\033[48;5;27m'
    [BG_CYAN]='\033[48;5;30m'
    [BG_ORANGE]='\033[48;5;208m'
)

print_color() {
    local color="$1"
    local text="$2"
    echo -e "${COLORS[$color]}${text}${COLORS[RESET]}"
}

print_box() {
    local bg_color="$1"
    local text_color="$2"
    local text="$3"
    echo -e "${COLORS[$bg_color]}${COLORS[$text_color]} ${text} ${COLORS[RESET]}"
}

clear_screen() {
    printf "\033c"
}

print_logo() {
    echo ""
    echo -e "${COLORS[PINK]}   ██████╗ ${COLORS[CYAN]} ██████╗ ${COLORS[YELLOW]}██╗     ${COLORS[PURPLE]}██████╗${COLORS[BLUE]}██╗${COLORS[MAGENTA]}██████╗ ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██╔════╝ ${COLORS[CYAN]}██╔═══██╗${COLORS[YELLOW]}██║     ${COLORS[PURPLE]}██╔══██╗${COLORS[BLUE]}██║${COLORS[MAGENTA]}██╔══██╗${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██║  ███╗${COLORS[CYAN]}██║   ██║${COLORS[YELLOW]}██║     ${COLORS[PURPLE]}██║  ██║${COLORS[BLUE]}██║${COLORS[MAGENTA]}██████╔╝${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██║   ██║${COLORS[CYAN]}██║   ██║${COLORS[YELLOW]}██║     ${COLORS[PURPLE]}██║  ██║${COLORS[BLUE]}██║${COLORS[MAGENTA]}██╔═══╝ ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ╚██████╔╝${COLORS[CYAN]}╚██████╔╝${COLORS[YELLOW]}███████╗${COLORS[PURPLE]}██████╔╝${COLORS[BLUE]}██║${COLORS[MAGENTA]}██║     ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}   ╚═════╝ ${COLORS[CYAN]} ╚═════╝ ${COLORS[YELLOW]}╚══════╝${COLORS[PURPLE]}╚═════╝ ${COLORS[BLUE]}╚═╝${COLORS[MAGENTA]}╚═╝     ${COLORS[RESET]}"
    echo ""
    print_color "CYAN" "  B A C K H A U L   T U N N E L   M A N A G E R"
    print_color "NEWORANGE" "  ═══════════════════════════════════════════════"
    echo ""

    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_box "BG_GREEN" "WHITE" "✓ Backhaul Installed"
    else
        print_box "BG_RED" "WHITE" "✗ Backhaul Not Installed"
    fi
    echo ""
}

print_header() {
    clear_screen
    print_logo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_box "BG_RED" "WHITE" "✗ This script must be run as root"
        exit 1
    fi
}

press_enter() {
    echo ""
    print_color "NEWORANGE" "Press Enter to continue..."
    read -r
}

init_tunnel_db() {
    if [[ ! -f "$TUNNEL_DB" ]]; then
        echo "{}" > "$TUNNEL_DB"
    fi
}

save_tunnel_info() {
    local name="$1"
    local service_name="$2"
    local port="$3"
    local dest_ip="$4"
    local protocol="$5"

    init_tunnel_db

    local temp_file
    temp_file=$(mktemp)
    jq --arg name "$name" \
       --arg service "$service_name" \
       --arg port "$port" \
       --arg dest "$dest_ip" \
       --arg proto "$protocol" \
       '.[$service] = {name: $name, port: $port, destination: $dest, protocol: $proto}' \
       "$TUNNEL_DB" > "$temp_file" 2>/dev/null \
    || echo "{\"$service_name\": {\"name\": \"$name\", \"port\": \"$port\", \"destination\": \"$dest_ip\", \"protocol\": \"$protocol\"}}" > "$temp_file"

    mv "$temp_file" "$TUNNEL_DB"
}

get_tunnel_info() {
    local service_name="$1"
    init_tunnel_db
    jq -r --arg service "$service_name" '.[$service] // empty' "$TUNNEL_DB" 2>/dev/null
}

delete_tunnel_info() {
    local service_name="$1"
    init_tunnel_db

    local temp_file
    temp_file=$(mktemp)
    jq --arg service "$service_name" 'del(.[$service])' "$TUNNEL_DB" > "$temp_file" 2>/dev/null
    mv "$temp_file" "$TUNNEL_DB"
}

check_vpn_port_conflict() {
    local new_ports="$1"
    local current_service="$2"

    IFS=',' read -ra new_ports_array <<< "$new_ports"

    for new_port in "${new_ports_array[@]}"; do
        new_port=$(echo "$new_port" | xargs | tr -d '"')

        if check_port_in_use "$new_port"; then
            local service_info
            service_info=$(ss -tulnp 2>/dev/null | grep ":${new_port} " | head -1)
            local process_info
            process_info=$(echo "$service_info" | awk '{print $NF}' | sed 's/users:((//' | sed 's/))//' | cut -d',' -f2 | tr -d '"')

            if [[ -z "$process_info" ]]; then
                process_info=$(lsof -i ":${new_port}" 2>/dev/null | tail -1 | awk '{print $1}')
            fi

            if [[ -z "$process_info" ]]; then
                process_info="Unknown Service"
            fi

            echo "system:$new_port:$process_info"
            return 1
        fi
    done

    for config_file in /root/backhaul-*.toml; do
        if [[ -f "$config_file" ]]; then
            local service_name
            service_name=$(basename "$config_file" .toml)

            if [[ "$service_name" == "$current_service" ]]; then
                continue
            fi

            local existing_ports
            existing_ports=$(grep "^ports = " "$config_file" 2>/dev/null | sed 's/ports = \[//g' | sed 's/\]//g' | tr -d '"' | tr -d ' ')

            if [[ -n "$existing_ports" ]]; then
                IFS=',' read -ra existing_ports_array <<< "$existing_ports"

                for new_port in "${new_ports_array[@]}"; do
                    new_port=$(echo "$new_port" | xargs | tr -d '"')

                    for existing_port in "${existing_ports_array[@]}"; do
                        existing_port=$(echo "$existing_port" | xargs)

                        if [[ "$new_port" == "$existing_port" ]]; then
                            echo "goldip:$existing_port:$service_name"
                            return 1
                        fi
                    done
                done
            fi
        fi
    done

    return 0
}

check_port_in_use() {
    local port="$1"
    if ss -tuln | grep -q ":${port} "; then
        return 0
    else
        return 1
    fi
}

validate_port() {
    local port="$1"
    if [[ ! "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    if [[ "$ip" =~ ^([0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}$ ]]; then
        return 0
    fi
    return 1
}

generate_token() {
    openssl rand -hex 16 2>/dev/null || head -c 16 /dev/urandom | xxd -p
}

get_next_web_port() {
    local start_port=2060
    local used_ports
    used_ports=$(grep -h "web_port" /root/*.toml 2>/dev/null | awk '{print $3}' | sort -n | uniq)

    while true; do
        if ! echo "$used_ports" | grep -qx "$start_port"; then
            echo "$start_port"
            return
        fi
        ((start_port++))
    done
}

# ─────────────────────────────────────────────────────────
# تابع ساخت آرایه ports برای TOML — بدون کاما اضافه
# ─────────────────────────────────────────────────────────
build_ports_lines() {
    local raw_input="$1"
    local valid_ports=()

    IFS=',' read -ra arr <<< "$raw_input"
    for p in "${arr[@]}"; do
        p=$(echo "$p" | xargs)
        if validate_port "$p"; then
            valid_ports+=("$p")
        fi
    done

    local count=${#valid_ports[@]}
    if [[ $count -eq 0 ]]; then
        echo ""
        return 1
    fi

    local result=""
    for (( i=0; i<count; i++ )); do
        if (( i < count - 1 )); then
            result+="\"${valid_ports[$i]}\","$'\n'
        else
            result+="\"${valid_ports[$i]}\""$'\n'     # آخرین عنصر بدون کاما
        fi
    done

    echo "$result"
    return 0
}

list_tunnels() {
    local tunnels=()
    for service in /etc/systemd/system/backhaul-*.service; do
        if [[ -f "$service" ]]; then
            local name
            name=$(basename "$service" .service)
            tunnels+=("$name")
        fi
    done
    echo "${tunnels[@]}"
}

format_bytes() {
    local bytes=$1
    if [[ $bytes -lt 1024 ]]; then
        echo "${bytes}B/s"
    elif [[ $bytes -lt 1048576 ]]; then
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1024}")KB/s"
    else
        echo "$(awk "BEGIN {printf \"%.2f\", $bytes/1048576}")MB/s"
    fi
}

get_tunnel_traffic() {
    local service_name="$1"
    local config_file="/root/${service_name}.toml"

    if [[ ! -f "$config_file" ]]; then
        echo "0|0"
        return
    fi

    local web_port
    web_port=$(grep "^web_port" "$config_file" 2>/dev/null | awk '{print $3}')

    if [[ -z "$web_port" ]]; then
        echo "0|0"
        return
    fi

    local stats
    stats=$(curl -s --max-time 3 "http://127.0.0.1:${web_port}/stats" 2>/dev/null)

    if [[ -z "$stats" ]]; then
        echo "0|0"
        return
    fi

    local rx tx
    rx=$(echo "$stats" | jq -r '.rx_rate // 0' 2>/dev/null || echo "0")
    tx=$(echo "$stats" | jq -r '.tx_rate // 0' 2>/dev/null || echo "0")

    echo "$rx|$tx"
}

check_tunnel_connection() {
    local service_name="$1"

    if ! systemctl is-active --quiet "$service_name"; then
        echo "inactive"
        return
    fi

    local traffic
    traffic=$(get_tunnel_traffic "$service_name")
    local rx tx
    rx=$(echo "$traffic" | cut -d'|' -f1)
    tx=$(echo "$traffic" | cut -d'|' -f2)

    if [[ "$rx" == "0" ]] && [[ "$tx" == "0" ]]; then
        local config_file="/root/${service_name}.toml"
        if grep -q "\[server\]" "$config_file" 2>/dev/null; then
            echo "active"
        else
            local last_log
            last_log=$(journalctl -u "$service_name" -n 5 --no-pager 2>/dev/null | grep -i "connected\|established")
            if [[ -n "$last_log" ]]; then
                echo "connected"
            else
                echo "disconnected"
            fi
        fi
    else
        echo "traffic"
    fi
}

monitor_tunnels() {
    while true; do
        local tunnels
        tunnels=($(list_tunnels))

        for tunnel in "${tunnels[@]}"; do
            if ! systemctl is-active --quiet "$tunnel"; then
                systemctl start "$tunnel" >/dev/null 2>&1
                logger "GOLDIP: Auto-restarted tunnel $tunnel"
            fi
        done

        sleep 30
    done
}

start_monitor() {
    if [[ -f "$MONITOR_PID_FILE" ]] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
        return
    fi

    monitor_tunnels &
    echo $! > "$MONITOR_PID_FILE"
}

stop_monitor() {
    if [[ -f "$MONITOR_PID_FILE" ]]; then
        kill "$(cat "$MONITOR_PID_FILE")" 2>/dev/null
        rm -f "$MONITOR_PID_FILE"
    fi
}

# ─────────────────────────────────────────────────────────
# نمایش اسپینر لودینگ در حین دانلود
# ─────────────────────────────────────────────────────────
show_download_spinner() {
    local pid=$1
    local label="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0
    local elapsed=0

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${COLORS[CYAN]}  %s  %s  %ds${COLORS[RESET]}" \
            "${frames[$i]}" "$label" "$elapsed"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.15
        elapsed=$(( elapsed + 1 ))
    done
    printf "\r%-70s\r" " "   # پاک کردن خط اسپینر
}

# ─────────────────────────────────────────────────────────
# دانلود با timeout — برمی‌گردونه 0 موفق / 1 شکست
# ─────────────────────────────────────────────────────────
download_with_timeout() {
    local url="$1"
    local dest="$2"
    local timeout_sec="${3:-45}"

    rm -f "$dest"
    wget -q --timeout="$timeout_sec" --tries=1 --waitretry=0 \
         "$url" -O "$dest" 2>/dev/null &
    local wget_pid=$!

    # watchdog: اگه wget بعد از timeout_sec+5 ثانیه هنوز زنده بود، kill کن
    ( sleep $(( timeout_sec + 5 )); kill "$wget_pid" 2>/dev/null ) &
    local watchdog_pid=$!

    wait "$wget_pid"
    local status=$?
    kill "$watchdog_pid" 2>/dev/null
    wait "$watchdog_pid" 2>/dev/null

    # فایل باید وجود داشته باشه و بزرگتر از 0 باشه
    if [[ $status -eq 0 ]] && [[ -s "$dest" ]]; then
        return 0
    else
        rm -f "$dest"
        return 1
    fi
}

# ─────────────────────────────────────────────────────────
# install_backhaul — اولویت GitHub، fallback goldip
# ─────────────────────────────────────────────────────────
install_backhaul() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Installing Backhaul v0.6.5"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""

    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_box "BG_YELLOW" "WHITE" "⚠ Backhaul is already installed"
        echo ""
        print_color "BLUE" "Do you want to reinstall? (yes/no)"
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            return
        fi
    fi

    local downloaded=false

    # ── تلاش اول: GitHub ─────────────────────────────────
    clear_screen
    print_logo
    print_color "CYAN" "  Downloading Backhaul..."
    echo ""
    print_color "PINK" "  Source [1/2]: GitHub (primary)"
    echo ""

    download_with_timeout "$BACKHAUL_URL_PRIMARY" "$BACKHAUL_ARCHIVE" 45 &
    local dl_pid=$!
    show_download_spinner "$dl_pid" "Downloading from GitHub"
    wait "$dl_pid"

    if [[ -s "$BACKHAUL_ARCHIVE" ]]; then
        downloaded=true
        print_box "BG_GREEN" "WHITE" "✓ Downloaded from GitHub"
    else
        # ── تلاش دوم: goldip ─────────────────────────────
        echo ""
        print_box "BG_YELLOW" "WHITE" "⚠ GitHub failed — trying goldip.me..."
        echo ""

        download_with_timeout "$BACKHAUL_URL_BACKUP" "$BACKHAUL_ARCHIVE" 45 &
        dl_pid=$!
        show_download_spinner "$dl_pid" "Downloading from goldip.me"
        wait "$dl_pid"

        if [[ -s "$BACKHAUL_ARCHIVE" ]]; then
            downloaded=true
            print_box "BG_GREEN" "WHITE" "✓ Downloaded from goldip.me"
        fi
    fi

    if [[ "$downloaded" == false ]]; then
        clear_screen
        print_logo
        print_box "BG_RED" "WHITE" "✗ Download failed from all sources"
        echo ""
        print_color "YELLOW" "  لطفاً اتصال اینترنت سرور را بررسی کنید"
        press_enter
        return
    fi

    # ── استخراج ──────────────────────────────────────────
    echo ""
    print_color "CYAN" "  → Extracting archive..."
    rm -f "$BACKHAUL_BIN"

    if ! tar -xzf "$BACKHAUL_ARCHIVE" -C /tmp/ 2>/dev/null; then
        print_box "BG_RED" "WHITE" "✗ Extraction failed — archive may be corrupted"
        rm -f "$BACKHAUL_ARCHIVE"
        press_enter
        return
    fi

    if [[ ! -f "/tmp/backhaul" ]]; then
        print_box "BG_RED" "WHITE" "✗ Binary not found after extraction"
        rm -f "$BACKHAUL_ARCHIVE"
        press_enter
        return
    fi

    mv /tmp/backhaul "$BACKHAUL_BIN"
    rm -f "$BACKHAUL_ARCHIVE"
    chmod +x "$BACKHAUL_BIN"

    clear_screen
    print_logo
    print_box "BG_GREEN" "WHITE" "✓ Backhaul installed successfully"

    start_monitor

    press_enter
}

add_tunnel_menu() {
    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Add Tunnel"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Iran Server"
        print_color "CYAN" "[2] Kharej Client"
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "YELLOW" "Select option:"
        read -r choice

        case $choice in
            1) add_tunnel_iran ;;
            2) add_tunnel_kharej ;;
            0) return ;;
            *)
                clear_screen
                print_logo
                print_box "BG_RED" "WHITE" "✗ Invalid option"
                sleep 1
                ;;
        esac
    done
}

add_tunnel_iran() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Add Iran Tunnel Server"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""
    echo ""

    print_color "PINK" "Tunnel name:"
    read -r tunnel_name

    if [[ -z "$tunnel_name" ]]; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ Tunnel name is required"
        sleep 2
        return
    fi

    echo ""
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP"
    print_color "BLUE" "[2] UDP"
    print_color "YELLOW" "[3] WS"
    print_color "PURPLE" "[4] WSS"
    print_color "OLIVE" "[5] GRPC"
    echo ""
    print_color "PINK" "Select protocol (1-5):"
    read -r proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="ws" ;;
        4) protocol="wss" ;;
        5) protocol="grpc" ;;
        *)
            echo ""
            print_box "BG_RED" "WHITE" "✗ Invalid protocol selection"
            sleep 2
            return
            ;;
    esac

    while true; do
        echo ""
        print_color "YELLOW" "Tunnel Port:"
        read -r tunnel_port

        if ! validate_port "$tunnel_port"; then
            echo ""
            print_box "BG_RED" "WHITE" "✗ Invalid port"
            sleep 1
            continue
        fi

        if check_port_in_use "$tunnel_port"; then
            echo ""
            print_box "BG_RED" "WHITE" "✗ Port $tunnel_port is already in use"
            sleep 1
            continue
        fi
        break
    done

    echo ""
    print_color "NEWORANGE" "Token (leave empty for auto-generate):"
    read -r token

    if [[ -z "$token" ]]; then
        token=$(generate_token)
        echo ""
        print_box "BG_GREEN" "WHITE" "✓ Generated token: $token"
        sleep 2
    fi

    echo ""
    print_color "BLUE" "VPN Config Port(s) (comma separated):"
    read -r vpn_ports_input

    local ports_lines
    ports_lines=$(build_ports_lines "$vpn_ports_input")
    if [[ $? -ne 0 ]] || [[ -z "$ports_lines" ]]; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ No valid ports provided"
        sleep 2
        return
    fi

    local conflict_check
    conflict_check=$(check_vpn_port_conflict "$vpn_ports_input" "")
    if [[ $? -eq 1 ]]; then
        local conflict_type conflict_port conflict_info
        conflict_type=$(echo "$conflict_check" | cut -d':' -f1)
        conflict_port=$(echo "$conflict_check" | cut -d':' -f2)
        conflict_info=$(echo "$conflict_check" | cut -d':' -f3)

        echo ""
        print_box "BG_RED" "WHITE" "✗ Port $conflict_port is already in use!"
        echo ""

        if [[ "$conflict_type" == "goldip" ]]; then
            local conflict_tunnel_info conflict_tunnel_name
            conflict_tunnel_info=$(get_tunnel_info "$conflict_info")
            conflict_tunnel_name=$(echo "$conflict_tunnel_info" | jq -r '.name // "Unknown"' 2>/dev/null)

            print_color "YELLOW" "  Used by GOLDIP tunnel:"
            print_color "CYAN" "  → Tunnel Name: $conflict_tunnel_name"
            print_color "CYAN" "  → Service: $conflict_info"
        else
            print_color "YELLOW" "  Used by system service:"
            print_color "CYAN" "  → Process/Service: $conflict_info"
        fi

        echo ""
        print_color "NEWORANGE" "Please choose different VPN port(s)"
        sleep 4
        return
    fi

    local web_port
    web_port=$(get_next_web_port)
    local config_name="backhaul-iran-${tunnel_port}-${protocol}"
    local config_file="/root/${config_name}.toml"

    if [[ "$protocol" == "tcp" ]] || [[ "$protocol" == "udp" ]]; then
        cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:$tunnel_port"
transport = "$protocol"
token = "$token"
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
ports = [
$ports_lines]
EOF
    elif [[ "$protocol" == "ws" ]]; then
        cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:$tunnel_port"
transport = "ws"
token = "$token"
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
ports = [
$ports_lines]

[server.transport_config]
path = "/"
EOF
    elif [[ "$protocol" == "wss" ]]; then
        cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:$tunnel_port"
transport = "wss"
token = "$token"
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
ports = [
$ports_lines]

[server.transport_config]
path = "/"
sni = "speedtest.net"
EOF
    elif [[ "$protocol" == "grpc" ]]; then
        cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:$tunnel_port"
transport = "grpc"
token = "$token"
heartbeat = 40
channel_size = 2048
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
ports = [
$ports_lines]
EOF
    fi

    chmod 755 "$config_file"

    cat > "/etc/systemd/system/${config_name}.service" << EOF
[Unit]
Description=Backhaul Reverse Tunnel Service - ${tunnel_name}
After=network.target

[Service]
Type=simple
ExecStart=$BACKHAUL_BIN -c $config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${config_name}.service" >/dev/null 2>&1
    systemctl start "${config_name}.service"

    save_tunnel_info "$tunnel_name" "$config_name" "$tunnel_port" "0.0.0.0" "$protocol"

    sleep 2

    clear_screen
    print_logo

    if systemctl is-active --quiet "${config_name}.service"; then
        print_box "BG_GREEN" "WHITE" "✓ Tunnel created and started successfully"
        echo ""
        print_color "CYAN" "  Name: ${tunnel_name}"
        print_color "BLUE" "  Protocol: ${protocol}"
        print_color "YELLOW" "  Service: ${config_name}"
        print_color "OLIVE" "  Web Port: ${web_port}"
    else
        print_box "BG_RED" "WHITE" "✗ Failed to start tunnel"
        echo ""
        print_color "YELLOW" "Checking logs..."
        journalctl -u "${config_name}.service" -n 10 --no-pager
    fi

    press_enter
}

add_tunnel_kharej() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Add Kharej Tunnel Client"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""
    echo ""

    print_color "PINK" "Tunnel name:"
    read -r tunnel_name

    if [[ -z "$tunnel_name" ]]; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ Tunnel name is required"
        sleep 2
        return
    fi

    echo ""
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP"
    print_color "BLUE" "[2] UDP"
    print_color "YELLOW" "[3] WS"
    print_color "PURPLE" "[4] WSS"
    print_color "OLIVE" "[5] GRPC"
    echo ""
    print_color "PINK" "Select protocol (1-5):"
    read -r proto_choice

    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="udp" ;;
        3) protocol="ws" ;;
        4) protocol="wss" ;;
        5) protocol="grpc" ;;
        *)
            echo ""
            print_box "BG_RED" "WHITE" "✗ Invalid protocol selection"
            sleep 2
            return
            ;;
    esac

    echo ""
    print_color "YELLOW" "Iran IP:"
    read -r iran_ip

    if ! validate_ip "$iran_ip"; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ Invalid IP address"
        sleep 2
        return
    fi

    echo ""
    print_color "NEWORANGE" "Tunnel Port:"
    read -r tunnel_port

    if ! validate_port "$tunnel_port"; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ Invalid port"
        sleep 2
        return
    fi

    echo ""
    print_color "BLUE" "Token:"
    read -r token

    if [[ -z "$token" ]]; then
        echo ""
        print_box "BG_RED" "WHITE" "✗ Token is required"
        sleep 2
        return
    fi

    local remote_addr="${iran_ip}:${tunnel_port}"
    local web_port
    web_port=$(get_next_web_port)
    local config_name="backhaul-kharej-${tunnel_port}-${protocol}"
    local config_file="/root/${config_name}.toml"

    if [[ "$protocol" == "tcp" ]] || [[ "$protocol" == "udp" ]]; then
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "$protocol"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
EOF
    elif [[ "$protocol" == "ws" ]]; then
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "ws"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"

[client.transport_config]
path = "/"
EOF
    elif [[ "$protocol" == "wss" ]]; then
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "wss"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"

[client.transport_config]
path = "/"
sni = "speedtest.net"
insecure_skip_verify = true
EOF
    elif [[ "$protocol" == "grpc" ]]; then
        cat > "$config_file" << EOF
[client]
remote_addr = "$remote_addr"
transport = "grpc"
token = "$token"
connection_pool = 8
aggressive_pool = false
keepalive_period = 75
dial_timeout = 10
nodelay = true
retry_interval = 3
sniffer = true
web_port = $web_port
sniffer_log = "$SNIFFER_LOG"
log_level = "info"
EOF
    fi

    chmod 755 "$config_file"

    cat > "/etc/systemd/system/${config_name}.service" << EOF
[Unit]
Description=Backhaul Client Service - ${tunnel_name}
After=network.target

[Service]
Type=simple
ExecStart=$BACKHAUL_BIN -c $config_file
Restart=always
RestartSec=3
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${config_name}.service" >/dev/null 2>&1
    systemctl start "${config_name}.service"

    save_tunnel_info "$tunnel_name" "$config_name" "$tunnel_port" "$iran_ip" "$protocol"

    sleep 2

    clear_screen
    print_logo

    if systemctl is-active --quiet "${config_name}.service"; then
        print_box "BG_GREEN" "WHITE" "✓ Tunnel created and started successfully"
        echo ""
        print_color "CYAN" "  Name: ${tunnel_name}"
        print_color "BLUE" "  Protocol: ${protocol}"
        print_color "YELLOW" "  Service: ${config_name}"
        print_color "OLIVE" "  Web Port: ${web_port}"
    else
        print_box "BG_RED" "WHITE" "✗ Failed to start tunnel"
        echo ""
        print_color "YELLOW" "Checking logs..."
        journalctl -u "${config_name}.service" -n 10 --no-pager
    fi

    press_enter
}

manage_tunnel_menu() {
    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Manage Tunnel"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""

        local tunnels
        tunnels=($(list_tunnels))
        if [[ ${#tunnels[@]} -eq 0 ]]; then
            print_box "BG_RED" "WHITE" "✗ No tunnels found"
            press_enter
            return
        fi

        local i=1
        for tunnel in "${tunnels[@]}"; do
            local info name port dest
            info=$(get_tunnel_info "$tunnel")
            name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)

            [[ -z "$name" || "$name" == "null" ]] && name="Unknown"

            if systemctl is-active --quiet "$tunnel"; then
                local status
                status=$(check_tunnel_connection "$tunnel")
                if [[ "$status" == "traffic" ]]; then
                    print_box "BG_GREEN" "WHITE" "[$i] $name | Port: $port | Dest: $dest (Active + Traffic)"
                else
                    print_color "GREEN" "[$i] $name | Port: $port | Dest: $dest (Active)"
                fi
            else
                print_box "BG_RED" "WHITE" "[$i] $name | Port: $port | Dest: $dest (Inactive)"
            fi
            ((i++))
        done

        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "YELLOW" "Select tunnel:"
        read -r choice

        if [[ "$choice" == "0" ]]; then
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#tunnels[@]} ]]; then
            local selected_tunnel="${tunnels[$((choice-1))]}"
            manage_tunnel_actions "$selected_tunnel"
        else
            clear_screen
            print_logo
            print_box "BG_RED" "WHITE" "✗ Invalid selection"
            sleep 1
        fi
    done
}

manage_tunnel_actions() {
    local tunnel="$1"

    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Manage: $tunnel"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Start"
        print_color "CYAN" "[2] Stop"
        print_color "YELLOW" "[3] Restart"
        print_color "NEWORANGE" "[4] Edit Basic Settings"
        print_color "BLUE" "[5] Delete"
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "PINK" "Select action:"
        read -r action

        case $action in
            1)
                systemctl start "$tunnel"
                clear_screen
                print_logo
                if systemctl is-active --quiet "$tunnel"; then
                    print_box "BG_GREEN" "WHITE" "✓ Tunnel started"
                else
                    print_box "BG_RED" "WHITE" "✗ Failed to start"
                fi
                sleep 2
                ;;
            2)
                systemctl stop "$tunnel"
                clear_screen
                print_logo
                print_box "BG_GREEN" "WHITE" "✓ Tunnel stopped"
                sleep 2
                ;;
            3)
                systemctl restart "$tunnel"
                clear_screen
                print_logo
                if systemctl is-active --quiet "$tunnel"; then
                    print_box "BG_GREEN" "WHITE" "✓ Tunnel restarted"
                else
                    print_box "BG_RED" "WHITE" "✗ Failed to restart"
                fi
                sleep 2
                ;;
            4)
                edit_tunnel_basic "$tunnel"
                ;;
            5)
                delete_tunnel "$tunnel"
                return
                ;;
            0)
                return
                ;;
            *)
                clear_screen
                print_logo
                print_box "BG_RED" "WHITE" "✗ Invalid action"
                sleep 1
                ;;
        esac
    done
}

edit_tunnel_basic() {
    local tunnel="$1"
    local config_file="/root/${tunnel}.toml"

    if [[ ! -f "$config_file" ]]; then
        clear_screen
        print_logo
        print_box "BG_RED" "WHITE" "✗ Config file not found"
        press_enter
        return
    fi

    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Edit Basic Settings: $tunnel"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""

    if grep -q "\[server\]" "$config_file"; then
        print_color "PINK" "[1] Token"
        print_color "CYAN" "[2] VPN Config Ports"
        print_color "YELLOW" "[3] Web Port"
        print_color "OLIVE" "[0] Cancel"
        echo ""
        print_color "NEWORANGE" "What to edit:"
        read -r edit_choice

        case $edit_choice in
            1)
                echo ""
                print_color "PINK" "New Token:"
                read -r new_token
                if [[ -n "$new_token" ]]; then
                    sed -i "s/^token = .*/token = \"${new_token}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    echo ""
                    print_box "BG_GREEN" "WHITE" "✓ Token updated"
                    sleep 2
                fi
                ;;
            2)
                echo ""
                print_color "CYAN" "New VPN Config Ports (comma separated):"
                read -r new_ports

                local conflict_check
                conflict_check=$(check_vpn_port_conflict "$new_ports" "$tunnel")
                if [[ $? -eq 1 ]]; then
                    local conflict_type conflict_port conflict_info
                    conflict_type=$(echo "$conflict_check" | cut -d':' -f1)
                    conflict_port=$(echo "$conflict_check" | cut -d':' -f2)
                    conflict_info=$(echo "$conflict_check" | cut -d':' -f3)

                    echo ""
                    print_box "BG_RED" "WHITE" "✗ Port $conflict_port is already in use!"
                    echo ""

                    if [[ "$conflict_type" == "goldip" ]]; then
                        local conflict_tunnel_info conflict_tunnel_name
                        conflict_tunnel_info=$(get_tunnel_info "$conflict_info")
                        conflict_tunnel_name=$(echo "$conflict_tunnel_info" | jq -r '.name // "Unknown"' 2>/dev/null)

                        print_color "YELLOW" "  Used by GOLDIP tunnel:"
                        print_color "CYAN" "  → Tunnel: $conflict_tunnel_name"
                    else
                        print_color "YELLOW" "  Used by system service:"
                        print_color "CYAN" "  → Process: $conflict_info"
                    fi
                    sleep 3
                else
                    local new_ports_lines
                    new_ports_lines=$(build_ports_lines "$new_ports")
                    if [[ -n "$new_ports_lines" ]]; then
                        # ── جایگزینی بلوک ports به‌صورت ایمن ──────────────
                        local tmp
                        tmp=$(mktemp)
                        awk -v newblock="ports = [\n${new_ports_lines}]" '
                            /^ports = \[/ { in_block=1; printf "%s\n", newblock; next }
                            in_block && /^\]/ { in_block=0; next }
                            in_block { next }
                            { print }
                        ' "$config_file" > "$tmp" && mv "$tmp" "$config_file"

                        systemctl restart "$tunnel"
                        echo ""
                        print_box "BG_GREEN" "WHITE" "✓ Ports updated"
                        sleep 2
                    fi
                fi
                ;;
            3)
                echo ""
                print_color "YELLOW" "New Web Port:"
                read -r new_web_port
                if validate_port "$new_web_port"; then
                    sed -i "s/^web_port = .*/web_port = ${new_web_port}/" "$config_file"
                    systemctl restart "$tunnel"
                    echo ""
                    print_box "BG_GREEN" "WHITE" "✓ Web port updated"
                    sleep 2
                fi
                ;;
        esac
    else
        print_color "PINK" "[1] Remote Address"
        print_color "CYAN" "[2] Token"
        print_color "YELLOW" "[3] Web Port"
        print_color "OLIVE" "[0] Cancel"
        echo ""
        print_color "NEWORANGE" "What to edit:"
        read -r edit_choice

        case $edit_choice in
            1)
                echo ""
                print_color "PINK" "New Iran IP:"
                read -r new_ip

                echo ""
                print_color "CYAN" "New Tunnel Port:"
                read -r new_port

                if validate_ip "$new_ip" && validate_port "$new_port"; then
                    local new_remote="${new_ip}:${new_port}"
                    sed -i "s|^remote_addr = .*|remote_addr = \"${new_remote}\"|" "$config_file"
                    systemctl restart "$tunnel"

                    local info name protocol
                    info=$(get_tunnel_info "$tunnel")
                    name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
                    protocol=$(echo "$info" | jq -r '.protocol // "tcp"' 2>/dev/null)
                    save_tunnel_info "$name" "$tunnel" "$new_port" "$new_ip" "$protocol"

                    echo ""
                    print_box "BG_GREEN" "WHITE" "✓ Remote address updated"
                    sleep 2
                fi
                ;;
            2)
                echo ""
                print_color "CYAN" "New Token:"
                read -r new_token
                if [[ -n "$new_token" ]]; then
                    sed -i "s/^token = .*/token = \"${new_token}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    echo ""
                    print_box "BG_GREEN" "WHITE" "✓ Token updated"
                    sleep 2
                fi
                ;;
            3)
                echo ""
                print_color "YELLOW" "New Web Port:"
                read -r new_web_port
                if validate_port "$new_web_port"; then
                    sed -i "s/^web_port = .*/web_port = ${new_web_port}/" "$config_file"
                    systemctl restart "$tunnel"
                    echo ""
                    print_box "BG_GREEN" "WHITE" "✓ Web port updated"
                    sleep 2
                fi
                ;;
        esac
    fi

    press_enter
}

delete_tunnel() {
    local tunnel="$1"

    clear_screen
    print_logo
    print_box "BG_RED" "WHITE" "⚠ Are you sure you want to delete $tunnel? (yes/no)"
    echo ""
    read -r confirm

    if [[ "$confirm" == "yes" ]]; then
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
        delete_tunnel_info "$tunnel"
        systemctl daemon-reload

        clear_screen
        print_logo
        print_box "BG_GREEN" "WHITE" "✓ Tunnel deleted successfully"
    else
        clear_screen
        print_logo
        print_box "BG_YELLOW" "WHITE" "⚠ Deletion cancelled"
    fi

    press_enter
}

advanced_options_menu() {
    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "PURPLE" "  ⚡ Advanced Options"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""

        local tunnels
        tunnels=($(list_tunnels))
        if [[ ${#tunnels[@]} -eq 0 ]]; then
            print_box "BG_RED" "WHITE" "✗ No tunnels found"
            press_enter
            return
        fi

        local i=1
        for tunnel in "${tunnels[@]}"; do
            local info name
            info=$(get_tunnel_info "$tunnel")
            name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            [[ -z "$name" || "$name" == "null" ]] && name="Unknown"
            print_color "PURPLE" "[$i] $name ($tunnel)"
            ((i++))
        done

        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "YELLOW" "Select tunnel to configure:"
        read -r choice

        if [[ "$choice" == "0" ]]; then
            return
        fi

        if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#tunnels[@]} ]]; then
            local selected_tunnel="${tunnels[$((choice-1))]}"
            advanced_tunnel_settings "$selected_tunnel"
        else
            clear_screen
            print_logo
            print_box "BG_RED" "WHITE" "✗ Invalid selection"
            sleep 1
        fi
    done
}

advanced_tunnel_settings() {
    local tunnel="$1"
    local config_file="/root/${tunnel}.toml"

    if [[ ! -f "$config_file" ]]; then
        clear_screen
        print_logo
        print_box "BG_RED" "WHITE" "✗ Config file not found"
        press_enter
        return
    fi

    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "PURPLE" "  ⚡ Advanced Settings: $tunnel"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""

        if grep -q "\[server\]" "$config_file"; then
            local heartbeat channel loglevel sniff
            heartbeat=$(grep "^heartbeat" "$config_file" 2>/dev/null | awk '{print $3}')
            channel=$(grep "^channel_size" "$config_file" 2>/dev/null | awk '{print $3}')
            loglevel=$(grep "^log_level" "$config_file" 2>/dev/null | cut -d'"' -f2)
            sniff=$(grep "^sniffer" "$config_file" 2>/dev/null | awk '{print $3}')

            print_color "PINK" "[1] Heartbeat (Current: ${heartbeat:-40})"
            print_color "CYAN" "[2] Channel Size (Current: ${channel:-2048})"
            print_color "YELLOW" "[3] Log Level (Current: ${loglevel:-info})"
            print_color "NEWORANGE" "[4] Sniffer (Current: ${sniff:-true})"
        else
            local pool aggr keep dial retry node loglevel
            pool=$(grep "^connection_pool" "$config_file" 2>/dev/null | awk '{print $3}')
            aggr=$(grep "^aggressive_pool" "$config_file" 2>/dev/null | awk '{print $3}')
            keep=$(grep "^keepalive_period" "$config_file" 2>/dev/null | awk '{print $3}')
            dial=$(grep "^dial_timeout" "$config_file" 2>/dev/null | awk '{print $3}')
            retry=$(grep "^retry_interval" "$config_file" 2>/dev/null | awk '{print $3}')
            node=$(grep "^nodelay" "$config_file" 2>/dev/null | awk '{print $3}')
            loglevel=$(grep "^log_level" "$config_file" 2>/dev/null | cut -d'"' -f2)

            print_color "PINK" "[1] Connection Pool (Current: ${pool:-8})"
            print_color "CYAN" "[2] Aggressive Pool (Current: ${aggr:-false})"
            print_color "YELLOW" "[3] Keepalive Period (Current: ${keep:-75})"
            print_color "NEWORANGE" "[4] Dial Timeout (Current: ${dial:-10})"
            print_color "BLUE" "[5] Retry Interval (Current: ${retry:-3})"
            print_color "OLIVE" "[6] Nodelay (Current: ${node:-true})"
            print_color "PURPLE" "[7] Log Level (Current: ${loglevel:-info})"
        fi

        print_color "RED" "[0] Back"
        echo ""
        print_color "PURPLE" "Select parameter to change:"
        read -r param_choice

        if [[ "$param_choice" == "0" ]]; then
            return
        fi

        if grep -q "\[server\]" "$config_file"; then
            case $param_choice in
                1)
                    echo ""
                    print_color "PINK" "New Heartbeat value (seconds, default: 40):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^heartbeat = .*/heartbeat = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Heartbeat updated"
                        sleep 2
                    fi
                    ;;
                2)
                    echo ""
                    print_color "CYAN" "New Channel Size (default: 2048):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^channel_size = .*/channel_size = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Channel Size updated"
                        sleep 2
                    fi
                    ;;
                3)
                    echo ""
                    print_color "YELLOW" "Log Level (trace/debug/info/warn/error):"
                    read -r new_value
                    sed -i "s/^log_level = .*/log_level = \"${new_value}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    print_box "BG_GREEN" "WHITE" "✓ Log Level updated"
                    sleep 2
                    ;;
                4)
                    echo ""
                    print_color "NEWORANGE" "Enable Sniffer? (true/false):"
                    read -r new_value
                    sed -i "s/^sniffer = .*/sniffer = ${new_value}/" "$config_file"
                    systemctl restart "$tunnel"
                    print_box "BG_GREEN" "WHITE" "✓ Sniffer updated"
                    sleep 2
                    ;;
            esac
        else
            case $param_choice in
                1)
                    echo ""
                    print_color "PINK" "New Connection Pool (default: 8):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^connection_pool = .*/connection_pool = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Connection Pool updated"
                        sleep 2
                    fi
                    ;;
                2)
                    echo ""
                    print_color "CYAN" "Aggressive Pool (true/false, default: false):"
                    read -r new_value
                    sed -i "s/^aggressive_pool = .*/aggressive_pool = ${new_value}/" "$config_file"
                    systemctl restart "$tunnel"
                    print_box "BG_GREEN" "WHITE" "✓ Aggressive Pool updated"
                    sleep 2
                    ;;
                3)
                    echo ""
                    print_color "YELLOW" "New Keepalive Period (seconds, default: 75):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^keepalive_period = .*/keepalive_period = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Keepalive Period updated"
                        sleep 2
                    fi
                    ;;
                4)
                    echo ""
                    print_color "NEWORANGE" "New Dial Timeout (seconds, default: 10):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^dial_timeout = .*/dial_timeout = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Dial Timeout updated"
                        sleep 2
                    fi
                    ;;
                5)
                    echo ""
                    print_color "BLUE" "New Retry Interval (seconds, default: 3):"
                    read -r new_value
                    if [[ "$new_value" =~ ^[0-9]+$ ]]; then
                        sed -i "s/^retry_interval = .*/retry_interval = ${new_value}/" "$config_file"
                        systemctl restart "$tunnel"
                        print_box "BG_GREEN" "WHITE" "✓ Retry Interval updated"
                        sleep 2
                    fi
                    ;;
                6)
                    echo ""
                    print_color "OLIVE" "Nodelay (true/false, default: true):"
                    read -r new_value
                    sed -i "s/^nodelay = .*/nodelay = ${new_value}/" "$config_file"
                    systemctl restart "$tunnel"
                    print_box "BG_GREEN" "WHITE" "✓ Nodelay updated"
                    sleep 2
                    ;;
                7)
                    echo ""
                    print_color "PURPLE" "Log Level (trace/debug/info/warn/error):"
                    read -r new_value
                    sed -i "s/^log_level = .*/log_level = \"${new_value}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    print_box "BG_GREEN" "WHITE" "✓ Log Level updated"
                    sleep 2
                    ;;
            esac
        fi
    done
}

show_logs() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Tunnel Logs"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""

    local tunnels
    tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_box "BG_RED" "WHITE" "✗ No tunnels found"
        press_enter
        return
    fi

    local i=1
    for tunnel in "${tunnels[@]}"; do
        local info name
        info=$(get_tunnel_info "$tunnel")
        name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
        [[ -z "$name" || "$name" == "null" ]] && name="Unknown"
        print_color "PINK" "[$i] $name ($tunnel)"
        ((i++))
    done

    print_color "OLIVE" "[0] Back"
    echo ""
    print_color "YELLOW" "Select tunnel:"
    read -r choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#tunnels[@]} ]]; then
        local selected_tunnel="${tunnels[$((choice-1))]}"

        clear_screen
        print_color "CYAN" "═══════════════════════════════════════════════════"
        print_color "YELLOW" "  Logs: $selected_tunnel (Last 50 lines)"
        print_color "CYAN" "═══════════════════════════════════════════════════"
        echo ""

        local log_output
        log_output=$(journalctl -u "$selected_tunnel" -n 50 --no-pager 2>/dev/null)
        if [[ -z "$log_output" ]]; then
            print_box "BG_RED" "WHITE" "✗ No logs available"
        else
            echo "$log_output" | while IFS= read -r line; do
                if echo "$line" | grep -qi "error\|fail\|fatal"; then
                    print_color "RED" "$line"
                elif echo "$line" | grep -qi "warn\|warning"; then
                    print_color "YELLOW" "$line"
                elif echo "$line" | grep -qi "success\|connected\|established\|running"; then
                    print_color "GREEN" "$line"
                else
                    echo "$line"
                fi
            done
        fi

        press_enter
    else
        clear_screen
        print_logo
        print_box "BG_RED" "WHITE" "✗ Invalid selection"
        sleep 1
    fi
}

show_status() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Tunnel Status & Traffic"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""

    local tunnels
    tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_box "BG_RED" "WHITE" "✗ No tunnels found"
    else
        for tunnel in "${tunnels[@]}"; do
            local info name port dest
            info=$(get_tunnel_info "$tunnel")
            name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
            [[ -z "$name" || "$name" == "null" ]] && name="Unknown"

            if systemctl is-active --quiet "$tunnel"; then
                local status traffic rx tx
                status=$(check_tunnel_connection "$tunnel")
                traffic=$(get_tunnel_traffic "$tunnel")
                rx=$(echo "$traffic" | cut -d'|' -f1)
                tx=$(echo "$traffic" | cut -d'|' -f2)

                if [[ "$status" == "traffic" ]]; then
                    local rx_formatted tx_formatted
                    rx_formatted=$(format_bytes "$rx")
                    tx_formatted=$(format_bytes "$tx")
                    print_box "BG_GREEN" "WHITE" "✓ $name | Port: $port | Dest: $dest"
                    print_box "BG_CYAN" "WHITE" "  ↓ Download: $rx_formatted  ↑ Upload: $tx_formatted"
                else
                    print_color "GREEN" "✓ $name | Port: $port | Dest: $dest (Connected)"
                fi
            else
                print_box "BG_RED" "WHITE" "✗ $name | Port: $port | Dest: $dest (Inactive)"
            fi
            echo ""
        done
    fi

    press_enter
}

uninstall_backhaul() {
    clear_screen
    print_logo
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Uninstall Backhaul"
    print_color "NEWORANGE" "═══════════════════════════════════════════════════"
    echo ""

    print_box "BG_RED" "WHITE" "⚠ This will remove all tunnels and Backhaul installation"
    echo ""
    print_color "YELLOW" "Are you sure? (yes/no)"
    read -r confirm

    if [[ "$confirm" != "yes" ]]; then
        clear_screen
        print_logo
        print_box "BG_BLUE" "WHITE" "Uninstall cancelled"
        press_enter
        return
    fi

    stop_monitor

    clear_screen
    print_logo
    print_color "PINK" "→ Stopping and removing all tunnels..."
    sleep 1

    local tunnels
    tunnels=($(list_tunnels))
    for tunnel in "${tunnels[@]}"; do
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
    done

    clear_screen
    print_logo
    print_color "CYAN" "→ Removing Backhaul binary..."
    sleep 1

    rm -f "$BACKHAUL_BIN"
    rm -f /tmp/backhaul
    rm -f /root/backhaul

    clear_screen
    print_logo
    print_color "YELLOW" "→ Removing configuration files..."
    sleep 1

    rm -f "$SNIFFER_LOG"
    rm -f "$TUNNEL_DB"
    find /root -type f -name "backhaul-*.toml" -exec rm -f {} \;

    clear_screen
    print_logo
    print_color "NEWORANGE" "→ Reloading systemd..."
    sleep 1

    systemctl daemon-reload

    clear_screen
    print_logo
    print_box "BG_GREEN" "WHITE" "✓ Backhaul uninstalled successfully"
    press_enter
}

main_menu() {
    if ! command -v jq &> /dev/null; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y jq >/dev/null 2>&1
    fi

    init_tunnel_db
    start_monitor

    while true; do
        clear_screen
        print_logo
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Main Menu"
        print_color "NEWORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Install Backhaul"
        print_color "CYAN" "[2] Add Tunnel"
        print_color "YELLOW" "[3] Manage Tunnel"
        print_color "NEWORANGE" "[4] Logs"
        print_color "BLUE" "[5] Tunnel Status"
        print_color "PURPLE" "[6] Advanced Options"
        print_color "OLIVE" "[7] Uninstall"
        print_color "RED" "[8] Exit"
        echo ""
        print_color "CYAN" "Select option:"
        read -r choice

        case $choice in
            1)
                install_backhaul
                ;;
            2)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_box "BG_RED" "WHITE" "✗ Please install Backhaul first"
                    sleep 2
                else
                    add_tunnel_menu
                fi
                ;;
            3)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_box "BG_RED" "WHITE" "✗ Please install Backhaul first"
                    sleep 2
                else
                    manage_tunnel_menu
                fi
                ;;
            4)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_box "BG_RED" "WHITE" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_logs
                fi
                ;;
            5)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_box "BG_RED" "WHITE" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_status
                fi
                ;;
            6)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    clear_screen
                    print_logo
                    print_box "BG_RED" "WHITE" "✗ Please install Backhaul first"
                    sleep 2
                else
                    advanced_options_menu
                fi
                ;;
            7)
                uninstall_backhaul
                ;;
            8)
                stop_monitor
                clear_screen
                print_color "CYAN" "Thank you for using GOLDIP!"
                print_color "YELLOW" "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                clear_screen
                print_logo
                print_box "BG_RED" "WHITE" "✗ Invalid option"
                sleep 1
                ;;
        esac
    done
}

check_root
main_menu
