#!/bin/bash

BACKHAUL_BIN="/usr/local/bin/backhaul"
BACKHAUL_ARCHIVE="/tmp/backhaul_linux_amd64.tar.gz"
BACKHAUL_URL="https://github.com/Musixal/Backhaul/releases/download/v0.6.5/backhaul_linux_amd64.tar.gz"
SNIFFER_LOG="/root/backhaul.json"
TUNNEL_DB="/root/.goldip_tunnels.json"

declare -A COLORS=(
    [RESET]='\033[0m'
    [RED]='\033[38;5;196m'
    [GREEN]='\033[38;5;46m'
    [PINK]='\033[38;5;213m'
    [CYAN]='\033[38;5;51m'
    [YELLOW]='\033[38;5;226m'
    [ORANGE]='\033[38;5;208m'
    [BLUE]='\033[38;5;33m'
    [OLIVE]='\033[38;5;142m'
)

print_color() {
    local color="$1"
    local text="$2"
    echo -e "${COLORS[$color]}${text}${COLORS[RESET]}"
}

clear_screen() {
    printf "\033c"
}

print_header() {
    clear_screen
    echo ""
    echo -e "${COLORS[PINK]}   ██████╗ ${COLORS[CYAN]} ██████╗ ${COLORS[YELLOW]}██╗     ${COLORS[ORANGE]}██████╗ ${COLORS[BLUE]}██╗${COLORS[OLIVE]}██████╗ ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██╔════╝ ${COLORS[CYAN]}██╔═══██╗${COLORS[YELLOW]}██║     ${COLORS[ORANGE]}██╔══██╗${COLORS[BLUE]}██║${COLORS[OLIVE]}██╔══██╗${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██║  ███╗${COLORS[CYAN]}██║   ██║${COLORS[YELLOW]}██║     ${COLORS[ORANGE]}██║  ██║${COLORS[BLUE]}██║${COLORS[OLIVE]}██████╔╝${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ██║   ██║${COLORS[CYAN]}██║   ██║${COLORS[YELLOW]}██║     ${COLORS[ORANGE]}██║  ██║${COLORS[BLUE]}██║${COLORS[OLIVE]}██╔═══╝ ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}  ╚██████╔╝${COLORS[CYAN]}╚██████╔╝${COLORS[YELLOW]}███████╗${COLORS[ORANGE]}██████╔╝${COLORS[BLUE]}██║${COLORS[OLIVE]}██║     ${COLORS[RESET]}"
    echo -e "${COLORS[PINK]}   ╚═════╝ ${COLORS[CYAN]} ╚═════╝ ${COLORS[YELLOW]}╚══════╝${COLORS[ORANGE]}╚═════╝ ${COLORS[BLUE]}╚═╝${COLORS[OLIVE]}╚═╝     ${COLORS[RESET]}"
    echo ""
    print_color "CYAN" "  B A C K H A U L   T U N N E L   M A N A G E R"
    print_color "ORANGE" "  ═══════════════════════════════════════════════"
    echo ""
    
    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_color "GREEN" "  ✓ Backhaul Installed"
    else
        print_color "RED" "  ✗ Backhaul Not Installed"
    fi
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_color "RED" "✗ This script must be run as root"
        exit 1
    fi
}

press_enter() {
    echo ""
    print_color "ORANGE" "Press Enter to continue..."
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
    
    local temp_file=$(mktemp)
    jq --arg name "$name" \
       --arg service "$service_name" \
       --arg port "$port" \
       --arg dest "$dest_ip" \
       --arg proto "$protocol" \
       '.[$service] = {name: $name, port: $port, destination: $dest, protocol: $proto}' \
       "$TUNNEL_DB" > "$temp_file" 2>/dev/null || echo "{\"$service_name\": {\"name\": \"$name\", \"port\": \"$port\", \"destination\": \"$dest_ip\", \"protocol\": \"$protocol\"}}" > "$temp_file"
    
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
    
    local temp_file=$(mktemp)
    jq --arg service "$service_name" 'del(.[$service])' "$TUNNEL_DB" > "$temp_file" 2>/dev/null
    mv "$temp_file" "$TUNNEL_DB"
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
    while check_port_in_use "$start_port"; do
        ((start_port++))
    done
    echo "$start_port"
}

list_tunnels() {
    local tunnels=()
    for service in /etc/systemd/system/backhaul-*.service; do
        if [[ -f "$service" ]]; then
            local name=$(basename "$service" .service)
            tunnels+=("$name")
        fi
    done
    echo "${tunnels[@]}"
}

install_backhaul() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Installing Backhaul v0.6.5"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    if [[ -f "$BACKHAUL_BIN" ]]; then
        print_color "YELLOW" "⚠ Backhaul is already installed"
        print_color "BLUE" "Do you want to reinstall? (yes/no)"
        read -r confirm
        if [[ "$confirm" != "yes" ]]; then
            return
        fi
    fi
    
    print_header
    print_color "PINK" "→ Downloading Backhaul..."
    if ! wget -q --show-progress "$BACKHAUL_URL" -O "$BACKHAUL_ARCHIVE"; then
        print_header
        print_color "RED" "✗ Download failed"
        press_enter
        return
    fi
    
    print_header
    print_color "CYAN" "→ Extracting archive..."
    rm -f "$BACKHAUL_BIN"
    if ! tar -xzf "$BACKHAUL_ARCHIVE" -C /tmp/; then
        print_color "RED" "✗ Extraction failed"
        rm -f "$BACKHAUL_ARCHIVE"
        press_enter
        return
    fi
    
    mv /tmp/backhaul "$BACKHAUL_BIN" 2>/dev/null
    rm -f "$BACKHAUL_ARCHIVE"
    chmod +x "$BACKHAUL_BIN"
    
    print_header
    print_color "GREEN" "✓ Backhaul installed successfully"
    press_enter
}

add_tunnel_menu() {
    while true; do
        print_header
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Add Tunnel"
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Iran (Server)"
        print_color "CYAN" "[2] Kharej (Client)"
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "YELLOW" "Select option:"
        read -r choice
        
        case $choice in
            1) add_tunnel_iran ;;
            2) add_tunnel_kharej ;;
            0) return ;;
            *) 
                print_header
                print_color "RED" "✗ Invalid option"
                sleep 1
                ;;
        esac
    done
}

add_tunnel_iran() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Add Iran Tunnel (Server)"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    print_color "PINK" "Tunnel name:"
    read -r tunnel_name
    
    if [[ -z "$tunnel_name" ]]; then
        print_header
        print_color "RED" "✗ Tunnel name is required"
        press_enter
        return
    fi
    
    print_header
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP"
    print_color "CYAN" "[2] TCPMUX"
    print_color "YELLOW" "[3] WS"
    print_color "ORANGE" "[4] WSS"
    print_color "BLUE" "[5] GRPC"
    print_color "OLIVE" "[6] UDP"
    echo ""
    print_color "PINK" "Select protocol (1-6):"
    read -r proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="tcpmux" ;;
        3) protocol="ws" ;;
        4) protocol="wss" ;;
        5) protocol="grpc" ;;
        6) protocol="udp" ;;
        *)
            print_header
            print_color "RED" "✗ Invalid protocol selection"
            press_enter
            return
            ;;
    esac
    
    while true; do
        print_header
        print_color "YELLOW" "Tunnel Port:"
        read -r tunnel_port
        
        if ! validate_port "$tunnel_port"; then
            print_header
            print_color "RED" "✗ Invalid port"
            sleep 1
            continue
        fi
        
        if check_port_in_use "$tunnel_port"; then
            print_header
            print_color "RED" "✗ Port $tunnel_port is already in use"
            sleep 1
            continue
        fi
        break
    done
    
    print_header
    print_color "ORANGE" "Token (leave empty for auto-generate):"
    read -r token
    
    if [[ -z "$token" ]]; then
        token=$(generate_token)
        print_header
        print_color "GREEN" "✓ Generated token: $token"
        sleep 2
    fi
    
    print_header
    print_color "BLUE" "VPN Config Port(s) (comma separated):"
    read -r vpn_ports_input
    
    IFS=',' read -ra vpn_ports_array <<< "$vpn_ports_input"
    local ports_string=""
    for port in "${vpn_ports_array[@]}"; do
        port=$(echo "$port" | xargs)
        if validate_port "$port"; then
            if [[ -n "$ports_string" ]]; then
                ports_string="$ports_string, \"$port\""
            else
                ports_string="\"$port\""
            fi
        fi
    done
    
    if [[ -z "$ports_string" ]]; then
        print_header
        print_color "RED" "✗ No valid ports provided"
        press_enter
        return
    fi
    
    local web_port=$(get_next_web_port)
    local config_name="backhaul-iran-${tunnel_port}"
    local config_file="/root/${config_name}.toml"
    
    # Optimized Iran server configuration for high traffic and NAT
    cat > "$config_file" << EOF
[server]
bind_addr = "0.0.0.0:${tunnel_port}"
transport = "${protocol}"
token = "${token}"
heartbeat = 20
channel_size = 8192
sniffer = true
web_port = ${web_port}
sniffer_log = "${SNIFFER_LOG}"
log_level = "info"
ports = [${ports_string}]
mux_session = 16
nodelay = true
keepalive = 75
timeout = 180
retries = 5
EOF
    
    # Add protocol-specific optimizations
    if [[ "$protocol" == "ws" || "$protocol" == "wss" ]]; then
        echo 'ws_path = "/tunnel"' >> "$config_file"
    fi
    
    if [[ "$protocol" == "wss" ]]; then
        echo 'tls_cert = ""' >> "$config_file"
        echo 'tls_key = ""' >> "$config_file"
    fi
    
    cat > "/etc/systemd/system/${config_name}.service" << EOF
[Unit]
Description=Backhaul Tunnel - ${tunnel_name}
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=${BACKHAUL_BIN} -c ${config_file}
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=512
LimitCORE=infinity
TasksMax=infinity
Nice=-10

[Install]
WantedBy=multi-user.target
EOF
    
    # Apply system optimizations for high traffic
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    
    systemctl daemon-reload
    systemctl enable "${config_name}.service" >/dev/null 2>&1
    systemctl start "${config_name}.service"
    
    save_tunnel_info "$tunnel_name" "$config_name" "$tunnel_port" "0.0.0.0" "$protocol"
    
    print_header
    
    if systemctl is-active --quiet "${config_name}.service"; then
        print_color "GREEN" "✓ Tunnel created and started successfully"
        print_color "CYAN" "  Name: ${tunnel_name}"
        print_color "BLUE" "  Protocol: ${protocol}"
        print_color "YELLOW" "  Service: ${config_name}"
        print_color "OLIVE" "  Web Port: ${web_port}"
    else
        print_color "RED" "✗ Failed to start tunnel"
    fi
    
    press_enter
}

add_tunnel_kharej() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Add Kharej Tunnel (Client)"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    print_color "PINK" "Tunnel name:"
    read -r tunnel_name
    
    if [[ -z "$tunnel_name" ]]; then
        print_header
        print_color "RED" "✗ Tunnel name is required"
        press_enter
        return
    fi
    
    print_header
    print_color "CYAN" "Select Protocol:"
    echo ""
    print_color "PINK" "[1] TCP"
    print_color "CYAN" "[2] TCPMUX"
    print_color "YELLOW" "[3] WS"
    print_color "ORANGE" "[4] WSS"
    print_color "BLUE" "[5] GRPC"
    print_color "OLIVE" "[6] UDP"
    echo ""
    print_color "PINK" "Select protocol (1-6):"
    read -r proto_choice
    
    case $proto_choice in
        1) protocol="tcp" ;;
        2) protocol="tcpmux" ;;
        3) protocol="ws" ;;
        4) protocol="wss" ;;
        5) protocol="grpc" ;;
        6) protocol="udp" ;;
        *)
            print_header
            print_color "RED" "✗ Invalid protocol selection"
            press_enter
            return
            ;;
    esac
    
    print_header
    print_color "YELLOW" "Iran IP:"
    read -r iran_ip
    
    if ! validate_ip "$iran_ip"; then
        print_header
        print_color "RED" "✗ Invalid IP address"
        press_enter
        return
    fi
    
    print_header
    print_color "ORANGE" "Tunnel Port:"
    read -r tunnel_port
    
    if ! validate_port "$tunnel_port"; then
        print_header
        print_color "RED" "✗ Invalid port"
        press_enter
        return
    fi
    
    print_header
    print_color "BLUE" "Token:"
    read -r token
    
    if [[ -z "$token" ]]; then
        print_header
        print_color "RED" "✗ Token is required"
        press_enter
        return
    fi
    
    local remote_addr
    if [[ "$iran_ip" =~ : ]]; then
        remote_addr="[${iran_ip}]:${tunnel_port}"
    else
        remote_addr="${iran_ip}:${tunnel_port}"
    fi
    
    local web_port=$(get_next_web_port)
    local config_name="backhaul-kharej-${tunnel_port}"
    local config_file="/root/${config_name}.toml"
    
    # Optimized Kharej client configuration for maximum speed and stability
    cat > "$config_file" << EOF
[client]
remote_addr = "${remote_addr}"
transport = "${protocol}"
token = "${token}"
connection_pool = 32
aggressive_pool = true
keepalive_period = 15
dial_timeout = 10
retry_interval = 2
sniffer = true
web_port = ${web_port}
sniffer_log = "${SNIFFER_LOG}"
log_level = "info"
mux_session = 16
nodelay = true
channel_size = 8192
fastopen = true
EOF
    
    # Add protocol-specific optimizations
    if [[ "$protocol" == "ws" || "$protocol" == "wss" ]]; then
        echo 'ws_path = "/tunnel"' >> "$config_file"
    fi
    
    if [[ "$protocol" == "wss" ]]; then
        echo 'tls_verify = false' >> "$config_file"
    fi
    
    cat > "/etc/systemd/system/${config_name}.service" << EOF
[Unit]
Description=Backhaul Tunnel - ${tunnel_name}
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=${BACKHAUL_BIN} -c ${config_file}
Restart=always
RestartSec=5
LimitNOFILE=1048576
LimitNPROC=512
LimitCORE=infinity
TasksMax=infinity
Nice=-10

[Install]
WantedBy=multi-user.target
EOF
    
    # Apply system optimizations for high traffic
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_no_metrics_save=1 >/dev/null 2>&1
    
    systemctl daemon-reload
    systemctl enable "${config_name}.service" >/dev/null 2>&1
    systemctl start "${config_name}.service"
    
    save_tunnel_info "$tunnel_name" "$config_name" "$tunnel_port" "$iran_ip" "$protocol"
    
    print_header
    
    if systemctl is-active --quiet "${config_name}.service"; then
        print_color "GREEN" "✓ Tunnel created and started successfully"
        print_color "CYAN" "  Name: ${tunnel_name}"
        print_color "BLUE" "  Protocol: ${protocol}"
        print_color "YELLOW" "  Service: ${config_name}"
        print_color "OLIVE" "  Web Port: ${web_port}"
    else
        print_color "RED" "✗ Failed to start tunnel"
    fi
    
    press_enter
}

manage_tunnel_menu() {
    while true; do
        print_header
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Manage Tunnel"
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        echo ""
        
        local tunnels=($(list_tunnels))
        if [[ ${#tunnels[@]} -eq 0 ]]; then
            print_color "RED" "✗ No tunnels found"
            press_enter
            return
        fi
        
        local i=1
        for tunnel in "${tunnels[@]}"; do
            local info=$(get_tunnel_info "$tunnel")
            local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            local port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            local dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
            
            if [[ -z "$name" || "$name" == "null" ]]; then
                name="Unknown"
            fi
            
            if systemctl is-active --quiet "$tunnel"; then
                print_color "GREEN" "[$i] $name | Port: $port | Dest: $dest (Active)"
            else
                print_color "RED" "[$i] $name | Port: $port | Dest: $dest (Inactive)"
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
            print_header
            print_color "RED" "✗ Invalid selection"
            sleep 1
        fi
    done
}

manage_tunnel_actions() {
    local tunnel="$1"
    
    while true; do
        print_header
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Manage: $tunnel"
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Start"
        print_color "CYAN" "[2] Stop"
        print_color "YELLOW" "[3] Restart"
        print_color "ORANGE" "[4] Edit"
        print_color "BLUE" "[5] Delete"
        print_color "OLIVE" "[0] Back"
        echo ""
        print_color "PINK" "Select action:"
        read -r action
        
        case $action in
            1)
                systemctl start "$tunnel"
                print_header
                if systemctl is-active --quiet "$tunnel"; then
                    print_color "GREEN" "✓ Tunnel started"
                else
                    print_color "RED" "✗ Failed to start"
                fi
                sleep 2
                ;;
            2)
                systemctl stop "$tunnel"
                print_header
                print_color "GREEN" "✓ Tunnel stopped"
                sleep 2
                ;;
            3)
                systemctl restart "$tunnel"
                print_header
                if systemctl is-active --quiet "$tunnel"; then
                    print_color "GREEN" "✓ Tunnel restarted"
                else
                    print_color "RED" "✗ Failed to restart"
                fi
                sleep 2
                ;;
            4)
                edit_tunnel "$tunnel"
                ;;
            5)
                delete_tunnel "$tunnel"
                return
                ;;
            0)
                return
                ;;
            *)
                print_header
                print_color "RED" "✗ Invalid action"
                sleep 1
                ;;
        esac
    done
}

edit_tunnel() {
    local tunnel="$1"
    local config_file="/root/${tunnel}.toml"
    
    if [[ ! -f "$config_file" ]]; then
        print_header
        print_color "RED" "✗ Config file not found"
        press_enter
        return
    fi
    
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Edit: $tunnel"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    if [[ "$tunnel" == *"iran"* ]]; then
        print_color "PINK" "[1] Token"
        print_color "CYAN" "[2] VPN Config Ports"
        print_color "YELLOW" "[3] Web Port"
        print_color "OLIVE" "[0] Cancel"
        echo ""
        print_color "ORANGE" "What to edit:"
        read -r edit_choice
        
        case $edit_choice in
            1)
                print_header
                print_color "PINK" "New Token:"
                read -r new_token
                if [[ -n "$new_token" ]]; then
                    sed -i "s/^token = .*/token = \"${new_token}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    print_header
                    print_color "GREEN" "✓ Token updated"
                fi
                ;;
            2)
                print_header
                print_color "CYAN" "New VPN Config Ports (comma separated):"
                read -r new_ports
                IFS=',' read -ra ports_array <<< "$new_ports"
                local ports_string=""
                for port in "${ports_array[@]}"; do
                    port=$(echo "$port" | xargs)
                    if validate_port "$port"; then
                        if [[ -n "$ports_string" ]]; then
                            ports_string="$ports_string, \"$port\""
                        else
                            ports_string="\"$port\""
                        fi
                    fi
                done
                if [[ -n "$ports_string" ]]; then
                    sed -i "s/^ports = .*/ports = [${ports_string}]/" "$config_file"
                    systemctl restart "$tunnel"
                    print_header
                    print_color "GREEN" "✓ Ports updated"
                fi
                ;;
            3)
                print_header
                print_color "YELLOW" "New Web Port:"
                read -r new_web_port
                if validate_port "$new_web_port"; then
                    sed -i "s/^web_port = .*/web_port = ${new_web_port}/" "$config_file"
                    systemctl restart "$tunnel"
                    print_header
                    print_color "GREEN" "✓ Web port updated"
                fi
                ;;
        esac
    else
        print_color "PINK" "[1] Remote Address"
        print_color "CYAN" "[2] Token"
        print_color "YELLOW" "[3] Web Port"
        print_color "OLIVE" "[0] Cancel"
        echo ""
        print_color "ORANGE" "What to edit:"
        read -r edit_choice
        
        case $edit_choice in
            1)
                print_header
                print_color "PINK" "New Iran IP:"
                read -r new_ip
                
                print_header
                print_color "CYAN" "New Tunnel Port:"
                read -r new_port
                
                if validate_ip "$new_ip" && validate_port "$new_port"; then
                    local new_remote
                    if [[ "$new_ip" =~ : ]]; then
                        new_remote="[${new_ip}]:${new_port}"
                    else
                        new_remote="${new_ip}:${new_port}"
                    fi
                    sed -i "s|^remote_addr = .*|remote_addr = \"${new_remote}\"|" "$config_file"
                    systemctl restart "$tunnel"
                    
                    # Update tunnel info
                    local info=$(get_tunnel_info "$tunnel")
                    local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
                    local protocol=$(echo "$info" | jq -r '.protocol // "tcp"' 2>/dev/null)
                    save_tunnel_info "$name" "$tunnel" "$new_port" "$new_ip" "$protocol"
                    
                    print_header
                    print_color "GREEN" "✓ Remote address updated"
                fi
                ;;
            2)
                print_header
                print_color "CYAN" "New Token:"
                read -r new_token
                if [[ -n "$new_token" ]]; then
                    sed -i "s/^token = .*/token = \"${new_token}\"/" "$config_file"
                    systemctl restart "$tunnel"
                    print_header
                    print_color "GREEN" "✓ Token updated"
                fi
                ;;
            3)
                print_header
                print_color "YELLOW" "New Web Port:"
                read -r new_web_port
                if validate_port "$new_web_port"; then
                    sed -i "s/^web_port = .*/web_port = ${new_web_port}/" "$config_file"
                    systemctl restart "$tunnel"
                    print_header
                    print_color "GREEN" "✓ Web port updated"
                fi
                ;;
        esac
    fi
    
    press_enter
}

delete_tunnel() {
    local tunnel="$1"
    
    print_header
    print_color "RED" "⚠ Are you sure you want to delete $tunnel? (yes/no)"
    read -r confirm
    
    if [[ "$confirm" == "yes" ]]; then
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
        delete_tunnel_info "$tunnel"
        systemctl daemon-reload
        
        print_header
        print_color "GREEN" "✓ Tunnel deleted successfully"
    else
        print_header
        print_color "YELLOW" "Deletion cancelled"
    fi
    
    press_enter
}

show_logs() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Tunnel Logs"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    local tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_color "RED" "✗ No tunnels found"
        press_enter
        return
    fi
    
    local i=1
    for tunnel in "${tunnels[@]}"; do
        local info=$(get_tunnel_info "$tunnel")
        local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
        
        if [[ -z "$name" || "$name" == "null" ]]; then
            name="Unknown"
        fi
        
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
        
        local log_output=$(journalctl -u "$selected_tunnel" -n 50 --no-pager 2>/dev/null)
        if [[ -z "$log_output" ]]; then
            print_color "RED" "✗ No logs available"
        else
            echo "$log_output"
        fi
        
        press_enter
    else
        print_header
        print_color "RED" "✗ Invalid selection"
        sleep 1
    fi
}

show_status() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Tunnel Status"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    local tunnels=($(list_tunnels))
    if [[ ${#tunnels[@]} -eq 0 ]]; then
        print_color "RED" "✗ No tunnels found"
    else
        for tunnel in "${tunnels[@]}"; do
            local info=$(get_tunnel_info "$tunnel")
            local name=$(echo "$info" | jq -r '.name // "Unknown"' 2>/dev/null)
            local port=$(echo "$info" | jq -r '.port // "N/A"' 2>/dev/null)
            local dest=$(echo "$info" | jq -r '.destination // "N/A"' 2>/dev/null)
            
            if [[ -z "$name" || "$name" == "null" ]]; then
                name="Unknown"
            fi
            
            if systemctl is-active --quiet "$tunnel"; then
                print_color "GREEN" "✓ $name | Port: $port | Dest: $dest"
            else
                print_color "RED" "✗ $name | Port: $port | Dest: $dest"
            fi
        done
    fi
    
    press_enter
}

uninstall_backhaul() {
    print_header
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    print_color "CYAN" "  Uninstall Backhaul"
    print_color "ORANGE" "═══════════════════════════════════════════════════"
    echo ""
    
    print_color "RED" "⚠ This will remove all tunnels and Backhaul installation"
    print_color "YELLOW" "Are you sure? (yes/no)"
    read -r confirm
    
    if [[ "$confirm" != "yes" ]]; then
        print_header
        print_color "BLUE" "Uninstall cancelled"
        press_enter
        return
    fi
    
    print_header
    print_color "PINK" "→ Stopping and removing all tunnels..."
    local tunnels=($(list_tunnels))
    for tunnel in "${tunnels[@]}"; do
        systemctl stop "$tunnel" 2>/dev/null
        systemctl disable "$tunnel" 2>/dev/null
        rm -f "/etc/systemd/system/${tunnel}.service"
        rm -f "/root/${tunnel}.toml"
    done
    
    print_header
    print_color "CYAN" "→ Removing Backhaul binary..."
    rm -f "$BACKHAUL_BIN"
    rm -f /tmp/backhaul
    
    print_header
    print_color "YELLOW" "→ Removing configuration files..."
    rm -f "$SNIFFER_LOG"
    rm -f "$TUNNEL_DB"
    
    print_header
    print_color "ORANGE" "→ Reloading systemd..."
    systemctl daemon-reload
    
    print_header
    print_color "GREEN" "✓ Backhaul uninstalled successfully"
    press_enter
}

main_menu() {
    # Install jq if not present
    if ! command -v jq &> /dev/null; then
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y jq >/dev/null 2>&1
    fi
    
    init_tunnel_db
    
    while true; do
        print_header
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        print_color "CYAN" "  Main Menu"
        print_color "ORANGE" "═══════════════════════════════════════════════════"
        echo ""
        print_color "PINK" "[1] Install Backhaul"
        print_color "CYAN" "[2] Add Tunnel"
        print_color "YELLOW" "[3] Manage Tunnel"
        print_color "ORANGE" "[4] Logs"
        print_color "BLUE" "[5] Tunnel Status"
        print_color "OLIVE" "[6] Uninstall"
        print_color "RED" "[7] Exit"
        echo ""
        print_color "CYAN" "Select option:"
        read -r choice
        
        case $choice in
            1)
                install_backhaul
                ;;
            2)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    print_header
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    add_tunnel_menu
                fi
                ;;
            3)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    print_header
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    manage_tunnel_menu
                fi
                ;;
            4)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    print_header
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_logs
                fi
                ;;
            5)
                if [[ ! -f "$BACKHAUL_BIN" ]]; then
                    print_header
                    print_color "RED" "✗ Please install Backhaul first"
                    sleep 2
                else
                    show_status
                fi
                ;;
            6)
                uninstall_backhaul
                ;;
            7)
                clear_screen
                print_color "CYAN" "Thank you for using GOLDIP!"
                print_color "YELLOW" "Goodbye!"
                echo ""
                exit 0
                ;;
            *)
                print_header
                print_color "RED" "✗ Invalid option"
                sleep 1
                ;;
        esac
    done
}

check_root
main_menu
