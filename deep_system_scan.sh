#!/bin/bash
################################################################################
# ГЛУБОКИЙ СКРИПТ ДИАГНОСТИКИ СИСТЕМЫ v3.0
# Безопасный скрипт полной диагностики системы (READ-ONLY)
# Собирает информацию: железо, логи, ПО, проблемы, конфигурации, безопасность
# НЕ вносит изменений в систему - только чтение данных
################################################################################

set -o pipefail

# Обработка прерывания
trap 'echo "⚠ Сканирование прервано пользователем."; exit 1' INT TERM

################################################################################
# КОНСТАНТЫ И НАСТРОЙКИ
################################################################################

# Цвета для терминала (не используются в файле отчёта)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Уровни сканирования
SCAN_MINIMAL=1
SCAN_MEDIUM=2
SCAN_TOTAL=3

# Глобальные переменные
SCAN_LEVEL=$SCAN_MINIMAL
OUTPUT_FILE=""
TEMP_DIR=""
START_TIME=$(date +%s)
HOSTNAME_SHORT=$(hostname 2>/dev/null || echo "unknown")
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Счётчики проблем для AI_SUMMARY
declare -a CRITICAL_ISSUES=()
declare -a WARNING_ISSUES=()
declare -a INFO_ISSUES=()

################################################################################
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
################################################################################

# Проверка наличия команды
cmd_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Безопасное выполнение команды с таймаутом
safe_cmd() {
    local cmd="$1"
    local timeout_sec="${2:-10}"
    timeout "$timeout_sec" bash -c "$cmd" 2>&1 || echo "[COMMAND_FAILED or TIMEOUT: $cmd]"
}

# Безопасное выполнение с sudo (если доступно)
safe_sudo_cmd() {
    local cmd="$1"
    local timeout_sec="${2:-10}"
    
    if [ "$EUID" -eq 0 ]; then
        timeout "$timeout_sec" bash -c "$cmd" 2>&1 || echo "[COMMAND_FAILED: $cmd]"
    elif cmd_exists sudo; then
        timeout "$timeout_sec" sudo bash -c "$cmd" 2>&1 || echo "[NEEDS_ROOT: $cmd]"
    else
        echo "[NEEDS_ROOT: $cmd]"
    fi
}

# Определение пути к рабочему столу
get_desktop_path() {
    local desktop_path=""
    
    # Пробуем XDG_CONFIG
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        # shellcheck disable=SC1091
        source "$HOME/.config/user-dirs.dirs" 2>/dev/null
        if [ -n "$XDG_DESKTOP_DIR" ] && [ -d "$XDG_DESKTOP_DIR" ]; then
            desktop_path="$XDG_DESKTOP_DIR"
        fi
    fi
    
    # Если не найдено, пробуем стандартные пути
    if [ -z "$desktop_path" ]; then
        if [ -d "$HOME/Desktop" ]; then
            desktop_path="$HOME/Desktop"
        elif [ -d "$HOME/Рабочий_стол" ]; then
            desktop_path="$HOME/Рабочий_стол"
        elif [ -d "$HOME/Рабочий стол" ]; then
            desktop_path="$HOME/Рабочий стол"
        fi
    fi
    
    # Если ничего не найдено, используем $HOME
    if [ -z "$desktop_path" ]; then
        desktop_path="$HOME"
    fi
    
    echo "$desktop_path"
}

# Подготовка директории для отчёта
prepare_output_dir() {
    local desktop_path
    desktop_path=$(get_desktop_path)
    
    # Проверяем существование и создаём если нужно
    if [ ! -d "$desktop_path" ]; then
        mkdir -p "$desktop_path" 2>/dev/null || {
            echo "[WARNING] Не удалось создать директорию $desktop_path, используем /tmp"
            desktop_path="/tmp"
        }
    fi
    
    OUTPUT_FILE="${desktop_path}/DEEP_SCAN_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
    
    # Проверка возможности записи
    if ! touch "$OUTPUT_FILE" 2>/dev/null; then
        echo "[CRITICAL] Не удалось создать файл отчёта. Используем /tmp"
        OUTPUT_FILE="/tmp/DEEP_SCAN_${HOSTNAME_SHORT}_${TIMESTAMP}.log"
    fi
}

# Функция вывода секции в формате для ИИ
print_section_header() {
    local section_name="$1"
    echo ""
    echo "## [$section_name]"
    echo ""
}

# Функция вывода подсекции
print_subsection_header() {
    local subsection_name="$1"
    echo "### [$subsection_name]"
}

# Функция вывода статуса
print_status() {
    local status="$1"
    echo "• STATUS: $status"
}

# Функция вывода данных
print_data() {
    local data="$1"
    echo "• DATA: $data"
}

# Функция вывода проблем
print_issues() {
    local issues="$1"
    if [ -n "$issues" ]; then
        echo "• ISSUES_FOUND: $issues"
    else
        echo "• ISSUES_FOUND: None"
    fi
}

# Добавление проблемы в список для AI_SUMMARY
add_critical() {
    local desc="$1"
    local location="$2"
    local recommendation="$3"
    CRITICAL_ISSUES+=("[CRITICAL] $desc | $location | $recommendation")
}

add_warning() {
    local desc="$1"
    local location="$2"
    local recommendation="$3"
    WARNING_ISSUES+=("[WARNING] $desc | $location | $recommendation")
}

add_info() {
    local desc="$1"
    local location="$2"
    local context="$3"
    INFO_ISSUES+=("[INFO] $desc | $location | $context")
}

################################################################################
# МЕНЮ ВЫБОРА УРОВНЯ СКАНИРОВАНИЯ
################################################################################

show_scan_menu() {
    echo -e "${GREEN}=========================================================${NC}"
    echo -e "${GREEN}   ГЛУБОКАЯ ДИАГНОСТИКА СИСТЕМЫ v3.0${NC}"
    echo -e "${GREEN}=========================================================${NC}"
    echo ""
    echo -e "${CYAN}Выберите уровень сканирования:${NC}"
    echo ""
    echo -e "${YELLOW}[1] Минимальный${NC}"
    echo "    • Ядро, CPU/RAM, базовые логи"
    echo "    • Свободное место, uptime, основные интерфейсы"
    echo "    • Время выполнения: ~30 секунд"
    echo ""
    echo -e "${YELLOW}[2] Средний${NC}"
    echo "    • Всё из Минимального +"
    echo "    • Службы systemd, пакеты (apt/snap/flatpak)"
    echo "    • Сеть, конфиги, SMART, пользователи, cron"
    echo "    • Базовый анализ журналов"
    echo "    • Время выполнения: ~2-3 минуты"
    echo ""
    echo -e "${YELLOW}[3] Тотальный${NC}"
    echo "    • Всё выше +"
    echo "    • Глубокий валидатор конфигов (синтаксис, битые ссылки)"
    echo "    • Orphaned packages, systemd unit validation"
    echo "    • Полный разбор dmesg/journalctl по категориям"
    echo "    • Безопасность (порты, firewall, SUID/SGID, world-writable)"
    echo "    • Контейнеры, виртуализация, детальный анализ"
    echo "    • Время выполнения: ~5-10 минут"
    echo ""
    echo -ne "${CYAN}Ваш выбор [1-3]: ${NC}"
}

get_scan_level() {
    local choice
    read -r choice
    
    case "$choice" in
        1)
            SCAN_LEVEL=$SCAN_MINIMAL
            echo -e "${GREEN}Выбран режим: МИНИМАЛЬНЫЙ${NC}"
            ;;
        2)
            SCAN_LEVEL=$SCAN_MEDIUM
            echo -e "${GREEN}Выбран режим: СРЕДНИЙ${NC}"
            ;;
        3)
            SCAN_LEVEL=$SCAN_TOTAL
            echo -e "${GREEN}Выбран режим: ТОТАЛЬНЫЙ${NC}"
            ;;
        *)
            echo -e "${YELLOW}Неверный выбор, используется режим по умолчанию: МИНИМАЛЬНЫЙ${NC}"
            SCAN_LEVEL=$SCAN_MINIMAL
            ;;
    esac
}

################################################################################
# СЕКЦИЯ 1: ОБЩАЯ ИНФОРМАЦИЯ (все уровни)
################################################################################

scan_general_info() {
    print_section_header "GENERAL_INFO"
    
    print_subsection_header "KERNEL_AND_OS"
    local kernel_info
    kernel_info=$(uname -a 2>/dev/null | head -1)
    print_status "OK"
    print_data "Kernel: $(uname -r 2>/dev/null), Arch: $(uname -m 2>/dev/null), Hostname: $HOSTNAME_SHORT"
    
    local os_info=""
    if [ -f /etc/os-release ]; then
        os_info=$(grep "^PRETTY_NAME=" /etc/os-release 2>/dev/null | cut -d'"' -f2)
    fi
    echo "• DATA: OS: ${os_info:-Unknown}"
    print_issues "None"
    echo ""
    
    print_subsection_header "UPTIME_AND_LOAD"
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')
    local load_avg
    load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}')
    print_status "OK"
    print_data "Uptime: ${uptime_info:-Unknown}, Load Average: ${load_avg:-Unknown}"
    print_issues "None"
    echo ""
    
    print_subsection_header "CPU_INFO"
    local cpu_model
    cpu_model=$(grep -m1 "model name" /proc/cpuinfo 2>/dev/null | cut -d: -f2 | xargs)
    local cpu_cores
    cpu_cores=$(nproc 2>/dev/null || grep -c "^processor" /proc/cpuinfo 2>/dev/null)
    print_status "OK"
    print_data "Model: ${cpu_model:-Unknown}, Cores: ${cpu_cores:-Unknown}"
    print_issues "None"
    echo ""
    
    print_subsection_header "MEMORY_INFO"
    local mem_total
    mem_total=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
    local mem_used
    mem_used=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
    local mem_avail
    mem_avail=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
    print_status "OK"
    print_data "Total: ${mem_total:-Unknown}, Used: ${mem_used:-Unknown}, Available: ${mem_avail:-Unknown}"
    
    # Проверка на высокое использование памяти
    local mem_percent
    mem_percent=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [ -n "$mem_percent" ] && [ "$mem_percent" -gt 90 ]; then
        print_issues "High memory usage: ${mem_percent}%"
        add_warning "High memory usage (${mem_percent}%)" "RAM" "Check processes with: ps aux --sort=-%mem"
    else
        print_issues "None"
    fi
    echo ""
}

################################################################################
# СЕКЦИЯ 2: ДИСКОВОЕ ПРОСТРАНСТВО (все уровни)
################################################################################

scan_disk_space() {
    print_section_header "DISK_SPACE"
    
    print_subsection_header "ROOT_FILESYSTEM"
    local df_output
    df_output=$(df -h / 2>/dev/null | tail -1)
    local total_size
    total_size=$(echo "$df_output" | awk '{print $2}')
    local used_size
    used_size=$(echo "$df_output" | awk '{print $3}')
    local avail_size
    avail_size=$(echo "$df_output" | awk '{print $4}')
    local use_percent
    use_percent=$(echo "$df_output" | awk '{print $5}' | tr -d '%')
    
    print_status "OK"
    print_data "Total: ${total_size:-N/A}, Used: ${used_size:-N/A}, Available: ${avail_size:-N/A}, Usage: ${use_percent:-0}%"
    
    # Проверка критического заполнения
    if [ -n "$use_percent" ]; then
        if [ "$use_percent" -gt 90 ]; then
            print_issues "CRITICAL: Disk usage above 90%"
            add_critical "Disk space critically low (${use_percent}%)" "/" "Clean up with: du -sh /* | sort -hr | head -20"
        elif [ "$use_percent" -gt 75 ]; then
            print_issues "WARNING: Disk usage above 75%"
            add_warning "Disk space running low (${use_percent}%)" "/" "Consider cleaning up old files and logs"
        else
            print_issues "None"
        fi
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -ge $SCAN_MEDIUM ]; then
        print_subsection_header "ALL_MOUNT_POINTS"
        local mount_data
        mount_data=$(df -hT 2>/dev/null | grep -E "^/dev|^Filesystem" | head -20)
        print_status "OK"
        echo "• DATA:"
        echo "$mount_data" | while read -r line; do
            echo "    $line"
        done
        print_issues "None"
        echo ""
        
        print_subsection_header "INODE_USAGE"
        local inode_info
        inode_info=$(df -i / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
        print_status "OK"
        print_data "Root inode usage: ${inode_info:-Unknown}%"
        if [ -n "$inode_info" ] && [ "$inode_info" -gt 80 ]; then
            print_issues "High inode usage detected"
            add_warning "High inode usage (${inode_info}%)" "/ filesystem" "Find large directories: find / -xdev -type f | cut -d '/' -f 2-3 | sort | uniq -c | sort -rn | head -20"
        else
            print_issues "None"
        fi
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 3: СЕТЕВЫЕ ИНТЕРФЕЙСЫ (Минимальный - базовые, Средний+ - подробно)
################################################################################

scan_network() {
    print_section_header "NETWORK"
    
    print_subsection_header "INTERFACES"
    local interfaces
    if cmd_exists ip; then
        interfaces=$(ip -br link 2>/dev/null | head -10)
    else
        interfaces="[TOOL_MISSING: ip command]"
    fi
    
    if [ -n "$interfaces" ]; then
        print_status "OK"
        echo "• DATA:"
        echo "$interfaces" | while read -r line; do
            echo "    $line"
        done
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "No interface information available"
        print_issues "Network tools may be missing"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -ge $SCAN_MEDIUM ]; then
        print_subsection_header "IP_ADDRESSES"
        local ip_addrs
        if cmd_exists ip; then
            ip_addrs=$(ip -br addr 2>/dev/null | head -10)
        else
            ip_addrs="[TOOL_MISSING: ip command]"
        fi
        print_status "OK"
        echo "• DATA:"
        echo "$ip_addrs" | while read -r line; do
            echo "    $line"
        done
        print_issues "None"
        echo ""
        
        print_subsection_header "DEFAULT_ROUTE"
        local route_info
        route_info=$(ip route 2>/dev/null | grep "^default" | head -1)
        print_status "OK"
        print_data "${route_info:-No default route}"
        print_issues "None"
        echo ""
        
        print_subsection_header "DNS_CONFIGURATION"
        local dns_servers
        dns_servers=$(grep "^nameserver" /etc/resolv.conf 2>/dev/null | awk '{print $2}' | tr '\n' ' ')
        print_status "OK"
        print_data "DNS Servers: ${dns_servers:-Not configured}"
        print_issues "None"
        echo ""
    fi
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        print_subsection_header "LISTENING_PORTS"
        local listening_ports
        if cmd_exists ss; then
            listening_ports=$(ss -tlnp 2>/dev/null | head -20)
        elif cmd_exists netstat; then
            listening_ports=$(netstat -tlnp 2>/dev/null | head -20)
        else
            listening_ports="[TOOL_MISSING: ss/netstat]"
        fi
        print_status "OK"
        echo "• DATA:"
        echo "$listening_ports" | while read -r line; do
            echo "    $line"
        done
        
        # Проверка на подозрительные порты
        local suspicious_ports=""
        if echo "$listening_ports" | grep -q ":23 "; then
            suspicious_ports="${suspicious_ports}Telnet(23) "
        fi
        if [ -n "$suspicious_ports" ]; then
            print_issues "Potentially insecure ports: $suspicious_ports"
            add_warning "Insecure service ports detected" "Network services" "Review necessity of Telnet/FTP services"
        else
            print_issues "None"
        fi
        echo ""
        
        print_subsection_header "FIREWALL_STATUS"
        local fw_status="No firewall detected"
        local fw_active="UNKNOWN"
        
        if cmd_exists ufw; then
            local ufw_out
            ufw_out=$(sudo ufw status 2>/dev/null | head -3)
            if echo "$ufw_out" | grep -q "Status: active"; then
                fw_status="UFW Active"
                fw_active="ACTIVE"
            elif echo "$ufw_out" | grep -q "Status: inactive"; then
                fw_status="UFW Inactive"
                fw_active="INACTIVE"
            fi
        elif cmd_exists iptables; then
            local ipt_count
            ipt_count=$(sudo iptables -L 2>/dev/null | wc -l)
            if [ "$ipt_count" -gt 10 ]; then
                fw_status="iptables rules present ($ipt_count lines)"
                fw_active="ACTIVE"
            fi
        elif cmd_exists nft; then
            local nft_out
            nft_out=$(sudo nft list ruleset 2>/dev/null | head -5)
            if [ -n "$nft_out" ]; then
                fw_status="nftables configured"
                fw_active="ACTIVE"
            fi
        fi
        
        print_status "OK"
        print_data "$fw_status"
        if [ "$fw_active" = "INACTIVE" ] || [ "$fw_status" = "No firewall detected" ]; then
            print_issues "No active firewall detected"
            add_warning "No active firewall" "System security" "Consider enabling UFW or configuring iptables/nftables"
        else
            print_issues "None"
        fi
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 4: SYSTEMD СЛУЖБЫ (Средний+)
################################################################################

scan_systemd_services() {
    if [ "$SCAN_LEVEL" -lt $SCAN_MEDIUM ]; then
        return
    fi
    
    print_section_header "SYSTEMD_SERVICES"
    
    print_subsection_header "RUNNING_SERVICES"
    local running_count
    running_count=$(systemctl list-units --type=service --state=running --no-pager 2>/dev/null | grep -c "running" || echo "0")
    print_status "OK"
    print_data "Running services: $running_count"
    print_issues "None"
    echo ""
    
    print_subsection_header "FAILED_SERVICES"
    local failed_units
    failed_units=$(systemctl list-units --type=service --state=failed --no-pager 2>/dev/null | grep -v "^$" | grep -v "loaded")
    local failed_count
    failed_count=$(systemctl list-units --type=service --state=failed --no-pager 2>/dev/null | grep -c "failed" 2>/dev/null || echo "0")
    failed_count=${failed_count:-0}
    # Убираем возможные лишние символы
    failed_count=$(echo "$failed_count" | tr -d '[:space:]' | head -c 10)
    
    if [ "$failed_count" -gt 0 ] 2>/dev/null && [ "$failed_count" != "0" ]; then
        print_status "CRITICAL"
        print_data "Failed services count: $failed_count"
        echo "• ISSUES_FOUND:"
        systemctl list-units --type=service --state=failed --no-pager 2>/dev/null | grep "failed" | while read -r line; do
            local svc_name
            svc_name=$(echo "$line" | awk '{print $1}')
            echo "    - $svc_name"
            add_critical "Service failed" "$svc_name" "Check status: systemctl status $svc_name"
        done
    else
        print_status "OK"
        print_data "No failed services"
        print_issues "None"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        print_subsection_header "DISABLED_SERVICES"
        local disabled_count
        disabled_count=$(systemctl list-unit-files --type=service --state=disabled --no-pager 2>/dev/null | grep -c "disabled" || echo "0")
        print_status "OK"
        print_data "Disabled services: $disabled_count"
        print_issues "None"
        echo ""
        
        print_subsection_header "MASKED_SERVICES"
        local masked_count
        masked_count=$(systemctl list-unit-files --type=service --state=masked --no-pager 2>/dev/null | grep -c "masked" || echo "0")
        print_status "OK"
        print_data "Masked services: $masked_count"
        print_issues "None"
        echo ""
        
        print_subsection_header "SYSTEMD_TIMERS"
        local timer_count
        timer_count=$(systemctl list-timers --all --no-pager 2>/dev/null | grep -c "timers listed" || echo "0")
        print_status "OK"
        print_data "Active timers: $timer_count"
        print_issues "None"
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 5: ПАКЕТЫ И ПО (Средний+)
################################################################################

scan_packages() {
    if [ "$SCAN_LEVEL" -lt $SCAN_MEDIUM ]; then
        return
    fi
    
    print_section_header "PACKAGES_AND_SOFTWARE"
    
    # APT/DPKG
    print_subsection_header "APT_PACKAGES"
    if cmd_exists dpkg; then
        local total_pkgs
        total_pkgs=$(dpkg --get-selections 2>/dev/null | wc -l)
        local installed_pkgs
        installed_pkgs=$(dpkg --get-selections 2>/dev/null | grep -v "deinstall" | wc -l)
        print_status "OK"
        print_data "Total in database: $total_pkgs, Installed: $installed_pkgs"
        
        # Проверка на битые пакеты
        local broken_pkgs
        broken_pkgs=$(dpkg --audit 2>/dev/null | head -5)
        if [ -n "$broken_pkgs" ]; then
            print_issues "Broken packages detected"
            add_warning "Broken/incomplete packages" "dpkg database" "Run: sudo apt --fix-broken install"
        else
            print_issues "None"
        fi
    else
        print_status "SKIPPED"
        print_data "dpkg not available (not Debian-based)"
        print_issues "None"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        print_subsection_header "ORPHANED_PACKAGES"
        if cmd_exists deborphan; then
            local orphan_count
            orphan_count=$(deborphan 2>/dev/null | wc -l)
            print_status "OK"
            print_data "Orphaned packages: $orphan_count"
            if [ "$orphan_count" -gt 10 ]; then
                print_issues "Many orphaned packages"
                add_info "Orphaned packages found ($orphan_count)" "apt" "Review with: deborphan | xargs sudo apt-get remove"
            else
                print_issues "None"
            fi
        else
            print_status "SKIPPED"
            print_data "[TOOL_MISSING: deborphan]"
            print_issues "None"
        fi
        echo ""
        
        print_subsection_header "OBSOLETE_KERNELS"
        if cmd_exists dpkg; then
            local kernel_count
            kernel_count=$(dpkg --list 2>/dev/null | grep -c "linux-image-[0-9]" 2>/dev/null || echo "0")
            kernel_count=$(echo "$kernel_count" | tr -d '[:space:]' | head -c 10)
            kernel_count=${kernel_count:-0}
            print_status "OK"
            print_data "Installed kernel versions: $kernel_count"
            if [ "$kernel_count" -gt 3 ] 2>/dev/null; then
                print_issues "Multiple old kernels installed"
                add_info "Old kernel versions ($kernel_count total)" "linux-image packages" "Remove old kernels to free space"
            else
                print_issues "None"
            fi
        else
            print_status "SKIPPED"
            print_data "Not Debian-based"
            print_issues "None"
        fi
        echo ""
    fi
    
    # Snap
    print_subsection_header "SNAP_PACKAGES"
    if cmd_exists snap; then
        local snap_count
        snap_count=$(snap list 2>/dev/null | grep -v "Name" | wc -l)
        print_status "OK"
        print_data "Installed snap packages: $snap_count"
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "Snap not installed"
        print_issues "None"
    fi
    echo ""
    
    # Flatpak
    print_subsection_header "FLATPAK_PACKAGES"
    if cmd_exists flatpak; then
        local flatpak_count
        flatpak_count=$(flatpak list --columns=application 2>/dev/null | wc -l)
        print_status "OK"
        print_data "Installed flatpak packages: $flatpak_count"
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "Flatpak not installed"
        print_issues "None"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        # Python packages
        print_subsection_header "PYTHON_PACKAGES"
        if cmd_exists pip3; then
            local pip_count
            pip_count=$(pip3 list 2>/dev/null | grep -v "Package" | wc -l)
            print_status "OK"
            print_data "Global pip3 packages: $pip_count"
            print_issues "None"
        else
            print_status "SKIPPED"
            print_data "pip3 not available"
            print_issues "None"
        fi
        echo ""
        
        # NPM packages
        print_subsection_header "NODEJS_PACKAGES"
        if cmd_exists npm; then
            local npm_global
            npm_global=$(npm list -g --depth=0 2>/dev/null | grep -v "empty" | wc -l)
            print_status "OK"
            print_data "Global npm packages: $npm_global"
            print_issues "None"
        else
            print_status "SKIPPED"
            print_data "npm not available"
            print_issues "None"
        fi
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 6: ХРАНИЛИЩА И SMART (Средний+)
################################################################################

scan_storage() {
    if [ "$SCAN_LEVEL" -lt $SCAN_MEDIUM ]; then
        return
    fi
    
    print_section_header "STORAGE_DEVICES"
    
    print_subsection_header "BLOCK_DEVICES"
    if cmd_exists lsblk; then
        local blk_info
        blk_info=$(lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>/dev/null | head -20)
        print_status "OK"
        echo "• DATA:"
        echo "$blk_info" | while read -r line; do
            echo "    $line"
        done
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "[TOOL_MISSING: lsblk]"
        print_issues "None"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -ge $SCAN_MEDIUM ]; then
        print_subsection_header "SMART_HEALTH"
        if cmd_exists smartctl; then
            local drives
            drives=$(lsblk -dn -o NAME 2>/dev/null | grep -E "^sd|^nvme|^hd" | head -5)
            local smart_issues=""
            
            for drive in $drives; do
                local health
                health=$(timeout 10 smartctl -H "/dev/$drive" 2>/dev/null | grep -i "test result")
                if echo "$health" | grep -qi "failed"; then
                    smart_issues="${smart_issues}/dev/$drive FAILED "
                    add_critical "SMART health check failed" "/dev/$drive" "Backup data immediately and replace drive"
                elif echo "$health" | grep -qi "passed"; then
                    : # OK
                else
                    smart_issues="${smart_issues}/dev/$drive UNKNOWN "
                fi
            done
            
            if [ -n "$smart_issues" ]; then
                print_status "WARNING"
                print_data "SMART Status: $smart_issues"
                print_issues "Some drives have issues"
            else
                print_status "OK"
                print_data "All checked drives passed SMART"
                print_issues "None"
            fi
        else
            print_status "SKIPPED"
            print_data "[TOOL_MISSING: smartctl]"
            print_issues "None"
        fi
        echo ""
    fi
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        print_subsection_header "PARTITION_TABLE"
        if cmd_exists fdisk; then
            local part_info
            part_info=$(sudo fdisk -l 2>/dev/null | grep -E "^Disk /dev|^/dev" | head -30)
            print_status "OK"
            echo "• DATA:"
            echo "$part_info" | while read -r line; do
                echo "    $line"
            done
            print_issues "None"
        else
            print_status "SKIPPED"
            print_data "[TOOL_MISSING: fdisk]"
            print_issues "None"
        fi
        echo ""
        
        print_subsection_header "SWAP_USAGE"
        local swap_info
        swap_info=$(free -h 2>/dev/null | grep -i swap)
        print_status "OK"
        print_data "$swap_info"
        print_issues "None"
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 7: ПОЛЬЗОВАТЕЛИ И БЕЗОПАСНОСТЬ (Тотальный)
################################################################################

scan_security() {
    if [ "$SCAN_LEVEL" -lt $SCAN_TOTAL ]; then
        return
    fi
    
    print_section_header "SECURITY"
    
    print_subsection_header "USERS_AND_GROUPS"
    local user_count
    user_count=$(cut -d: -f1 /etc/passwd 2>/dev/null | wc -l)
    local sudo_users
    sudo_users=$(grep "^sudo:" /etc/group 2>/dev/null | cut -d: -f4)
    print_status "OK"
    print_data "Total users: $user_count, Sudo group: ${sudo_users:-None}"
    print_issues "None"
    echo ""
    
    print_subsection_header "SUID_FILES"
    local suid_files
    suid_files=$(find / -perm -4000 -type f 2>/dev/null | head -20)
    local suid_count
    suid_count=$(find / -perm -4000 -type f 2>/dev/null | wc -l)
    print_status "OK"
    print_data "SUID files found: $suid_count"
    if [ "$suid_count" -gt 50 ]; then
        print_issues "Unusually high number of SUID files"
        add_warning "High SUID file count ($suid_count)" "File permissions" "Review: find / -perm -4000 -type f"
    else
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "SGID_FILES"
    local sgid_count
    sgid_count=$(find / -perm -2000 -type f 2>/dev/null | wc -l)
    print_status "OK"
    print_data "SGID files found: $sgid_count"
    print_issues "None"
    echo ""
    
    print_subsection_header "WORLD_WRITABLE_FILES"
    local ww_files
    ww_files=$(find / -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -20)
    local ww_count
    ww_count=$(find / -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | wc -l)
    print_status "OK"
    print_data "World-writable files: $ww_count"
    if [ "$ww_count" -gt 10 ]; then
        print_issues "Many world-writable files found"
        add_warning "World-writable files ($ww_count)" "File permissions" "Review: find / -type f -perm -0002"
    else
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "RECENT_LOGINS"
    local last_logins
    last_logins=$(last 2>/dev/null | head -10)
    print_status "OK"
    echo "• DATA:"
    echo "$last_logins" | while read -r line; do
        echo "    $line"
    done
    print_issues "None"
    echo ""
    
    print_subsection_header "FAILED_LOGINS"
    local failed_logins
    if [ -f /var/log/auth.log ]; then
        failed_logins=$(grep -i "failed\|failure" /var/log/auth.log 2>/dev/null | tail -10)
    elif [ -f /var/log/secure ]; then
        failed_logins=$(grep -i "failed\|failure" /var/log/secure 2>/dev/null | tail -10)
    fi
    
    if [ -n "$failed_logins" ]; then
        local fail_count
        fail_count=$(echo "$failed_logins" | wc -l)
        print_status "WARNING"
        print_data "Recent failed login attempts: $fail_count"
        print_issues "Failed login attempts detected"
        add_info "Failed login attempts ($fail_count)" "Auth logs" "Review: grep -i failed /var/log/auth.log"
    else
        print_status "OK"
        print_data "No recent failed logins found"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "SELINUX_APPARMOR"
    local mac_status="None"
    if cmd_exists aa-status; then
        local aa_out
        aa_out=$(sudo aa-status 2>/dev/null | head -5)
        if echo "$aa_out" | grep -q "profiles are in enforce mode"; then
            mac_status="AppArmor Active"
        elif echo "$aa_out" | grep -q "profiles are in complain mode"; then
            mac_status="AppArmor Complain Mode"
        else
            mac_status="AppArmor Installed"
        fi
    elif [ -f /sys/fs/selinux/enforce ]; then
        local selinux_val
        selinux_val=$(cat /sys/fs/selinux/enforce 2>/dev/null)
        if [ "$selinux_val" = "1" ]; then
            mac_status="SELinux Enforcing"
        else
            mac_status="SELinux Permissive"
        fi
    fi
    print_status "OK"
    print_data "MAC System: $mac_status"
    print_issues "None"
    echo ""
}

################################################################################
# СЕКЦИЯ 8: АНАЛИЗ ЛОГОВ (Минимальный - базовый, Тотальный - полный)
################################################################################

scan_logs() {
    print_section_header "SYSTEM_LOGS"
    
    print_subsection_header "KERNEL_ERRORS"
    local kern_errors
    kern_errors=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -20)
    local err_count
    err_count=$(dmesg --level=err,crit,alert,emerg 2>/dev/null | wc -l)
    
    if [ "$err_count" -gt 0 ]; then
        print_status "WARNING"
        print_data "Kernel errors found: $err_count"
        echo "• RAW_LOGS (last 10):"
        echo "$kern_errors" | tail -10 | while read -r line; do
            echo "    $line"
        done
        
        # Категоризация ошибок
        if echo "$kern_errors" | grep -qi "oom\|out of memory"; then
            add_warning "OOM events detected" "Kernel logs" "Check memory usage and limits"
        fi
        if echo "$kern_errors" | grep -qi "segfault"; then
            add_warning "Segmentation faults detected" "Kernel logs" "Check application stability"
        fi
        if echo "$kern_errors" | grep -qi "i/o error"; then
            add_critical "I/O errors detected" "Storage devices" "Check disk health immediately"
        fi
        print_issues "See RAW_LOGS for details"
    else
        print_status "OK"
        print_data "No critical kernel errors"
        print_issues "None"
    fi
    echo ""
    
    if [ "$SCAN_LEVEL" -ge $SCAN_MEDIUM ]; then
        print_subsection_header "JOURNALCTL_ERRORS"
        local journal_err
        journal_err=$(journalctl -p 3 -xb --no-pager --no-hostname 2>/dev/null | tail -20)
        local jerr_count
        jerr_count=$(journalctl -p 3 -xb --no-pager --no-hostname 2>/dev/null | wc -l)
        
        if [ "$jerr_count" -gt 0 ]; then
            print_status "WARNING"
            print_data "Journal errors (priority 0-3): $jerr_count"
            echo "• RAW_LOGS (last 10):"
            echo "$journal_err" | tail -10 | while read -r line; do
                echo "    $line"
            done
            print_issues "See RAW_LOGS for details"
        else
            print_status "OK"
            print_data "No journal errors found"
            print_issues "None"
        fi
        echo ""
    fi
    
    if [ "$SCAN_LEVEL" -eq $SCAN_TOTAL ]; then
        print_subsection_header "DMESG_CATEGORIES"
        echo "• DATA:"
        
        local oom_count
        oom_count=$(dmesg 2>/dev/null | grep -ci "oom\|out of memory" 2>/dev/null || echo "0")
        oom_count=$(echo "$oom_count" | tr -d '[:space:]' | head -c 10)
        oom_count=${oom_count:-0}
        echo "    OOM Events: $oom_count"
        if [ "$oom_count" -gt 0 ] 2>/dev/null; then
            add_warning "OOM killer activated ($oom_count times)" "Kernel memory management" "Review memory-intensive processes"
        fi
        
        local segfault_count
        segfault_count=$(dmesg 2>/dev/null | grep -ci "segfault" 2>/dev/null || echo "0")
        segfault_count=$(echo "$segfault_count" | tr -d '[:space:]' | head -c 10)
        segfault_count=${segfault_count:-0}
        echo "    Segfaults: $segfault_count"
        if [ "$segfault_count" -gt 0 ] 2>/dev/null; then
            add_warning "Segmentation faults ($segfault_count)" "Application stability" "Check core dumps in /var/crash"
        fi
        
        local io_err_count
        io_err_count=$(dmesg 2>/dev/null | grep -ci "i/o error" 2>/dev/null || echo "0")
        io_err_count=$(echo "$io_err_count" | tr -d '[:space:]' | head -c 10)
        io_err_count=${io_err_count:-0}
        echo "    I/O Errors: $io_err_count"
        if [ "$io_err_count" -gt 0 ] 2>/dev/null; then
            add_critical "Storage I/O errors ($io_err_count)" "Disk subsystem" "Check SMART and cable connections"
        fi
        
        local thermal_count
        thermal_count=$(dmesg 2>/dev/null | grep -ci "thermal\|throttl" 2>/dev/null || echo "0")
        thermal_count=$(echo "$thermal_count" | tr -d '[:space:]' | head -c 10)
        thermal_count=${thermal_count:-0}
        echo "    Thermal Events: $thermal_count"
        if [ "$thermal_count" -gt 0 ] 2>/dev/null; then
            add_warning "Thermal throttling detected ($thermal_count)" "Cooling system" "Clean fans and check thermal paste"
        fi
        
        local acpi_err_count
        acpi_err_count=$(dmesg 2>/dev/null | grep -ci "acpi.*error\|acpi.*fail" 2>/dev/null || echo "0")
        acpi_err_count=$(echo "$acpi_err_count" | tr -d '[:space:]' | head -c 10)
        acpi_err_count=${acpi_err_count:-0}
        echo "    ACPI Errors: $acpi_err_count"
        
        print_status "OK"
        print_issues "Categorized counts above"
        echo ""
        
        print_subsection_header "CORE_DUMPS"
        local core_count=0
        if [ -d /var/crash ]; then
            core_count=$(find /var/crash -type f 2>/dev/null | wc -l)
        fi
        if [ -d /var/lib/systemd/coredump ]; then
            local coredump_count
            coredump_count=$(find /var/lib/systemd/coredump -type f 2>/dev/null | wc -l)
            core_count=$((core_count + coredump_count))
        fi
        print_status "OK"
        print_data "Core dump files: $core_count"
        if [ "$core_count" -gt 0 ]; then
            print_issues "Core dumps present - review for crashes"
            add_info "Core dump files exist ($core_count)" "/var/crash, /var/lib/systemd/coredump" "Analyze with: coredumpctl list"
        else
            print_issues "None"
        fi
        echo ""
    fi
}

################################################################################
# СЕКЦИЯ 9: ВАЛИДАЦИЯ КОНФИГОВ (Тотальный)
################################################################################

scan_config_validation() {
    if [ "$SCAN_LEVEL" -lt $SCAN_TOTAL ]; then
        return
    fi
    
    print_section_header "CONFIG_VALIDATION"
    
    print_subsection_header "FSTAB_VALIDATION"
    if [ -f /etc/fstab ]; then
        local fstab_status="OK"
        local fstab_issues=""
        
        # Проверка синтаксиса (без монтирования)
        if cmd_exists findmnt; then
            local fstab_check
            fstab_check=$(findmnt --verify --fstab 2>&1)
            if echo "$fstab_check" | grep -qi "error\|failed"; then
                fstab_status="ERROR"
                fstab_issues="$fstab_check"
                add_critical "fstab configuration errors" "/etc/fstab" "Run: sudo findmnt --verify --fstab"
            fi
        fi
        
        # Проверка на дубликаты UUID
        local uuid_count
        uuid_count=$(grep -v "^#" /etc/fstab 2>/dev/null | grep -v "^$" | wc -l)
        local unique_uuid
        unique_uuid=$(grep -v "^#" /etc/fstab 2>/dev/null | grep -v "^$" | awk '{print $1}' | sort -u | wc -l)
        
        if [ "$uuid_count" -ne "$unique_uuid" ]; then
            fstab_status="WARNING"
            fstab_issues="${fstab_issues} Possible duplicate entries"
            add_warning "Possible duplicate fstab entries" "/etc/fstab" "Review fstab for duplicates"
        fi
        
        print_status "$fstab_status"
        print_data "Entries: $uuid_count, Status: $fstab_status"
        if [ -n "$fstab_issues" ]; then
            print_issues "$fstab_issues"
        else
            print_issues "None"
        fi
    else
        print_status "SKIPPED"
        print_data "/etc/fstab not found"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "SSHD_CONFIG"
    if [ -f /etc/ssh/sshd_config ]; then
        local sshd_status="OK"
        local sshd_issues=""
        
        if cmd_exists sshd; then
            local sshd_test
            sshd_test=$(sudo sshd -t 2>&1)
            if [ -n "$sshd_test" ]; then
                sshd_status="ERROR"
                sshd_issues="$sshd_test"
                add_critical "SSH config syntax errors" "/etc/ssh/sshd_config" "Run: sudo sshd -t"
            fi
        fi
        
        # Проверка опасных настроек
        if grep -q "^PermitRootLogin yes" /etc/ssh/sshd_config 2>/dev/null; then
            sshd_status="WARNING"
            sshd_issues="${sshd_issues} Root login enabled"
            add_warning "SSH root login enabled" "/etc/ssh/sshd_config" "Set PermitRootLogin to prohibit-password or no"
        fi
        
        if grep -q "^PasswordAuthentication yes" /etc/ssh/sshd_config 2>/dev/null; then
            sshd_issues="${sshdd_issues} Password auth enabled"
            add_info "SSH password authentication enabled" "/etc/ssh/sshd_config" "Consider key-based auth only"
        fi
        
        print_status "$sshd_status"
        print_data "Config exists, Validation: $sshd_status"
        if [ -n "$sshd_issues" ]; then
            print_issues "$sshd_issues"
        else
            print_issues "None"
        fi
    else
        print_status "SKIPPED"
        print_data "SSH server not installed"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "SYSTEMD_UNIT_VALIDATION"
    local unit_errors=""
    local unit_count=0
    
    if cmd_exists systemd-analyze; then
        local verify_out
        verify_out=$(systemd-analyze verify --no-pager 2>&1 | head -30)
        if [ -n "$verify_out" ]; then
            unit_errors="$verify_out"
            unit_count=$(echo "$verify_out" | wc -l)
        fi
    fi
    
    if [ -n "$unit_errors" ]; then
        print_status "WARNING"
        print_data "Unit validation warnings: $unit_count"
        echo "• RAW_LOGS (first 10):"
        echo "$unit_errors" | head -10 | while read -r line; do
            echo "    $line"
        done
        print_issues "See RAW_LOGS for details"
        add_info "Systemd unit warnings ($unit_count)" "systemd units" "Run: systemd-analyze verify"
    else
        print_status "OK"
        print_data "No unit validation errors"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "BROKEN_SYMLINKS"
    local broken_links
    broken_links=$(find /etc /usr -xtype l 2>/dev/null | head -20)
    local broken_count
    broken_count=$(find /etc /usr -xtype l 2>/dev/null | wc -l)
    
    if [ "$broken_count" -gt 0 ]; then
        print_status "WARNING"
        print_data "Broken symlinks found: $broken_count"
        echo "• DATA (first 10):"
        echo "$broken_links" | head -10 | while read -r line; do
            echo "    $line"
        done
        print_issues "Broken symlinks need attention"
        add_warning "Broken symbolic links ($broken_count)" "/etc, /usr" "Review and fix or remove broken links"
    else
        print_status "OK"
        print_data "No broken symlinks in /etc, /usr"
        print_issues "None"
    fi
    echo ""
}

################################################################################
# СЕКЦИЯ 10: КОНТЕЙНЕРЫ И ВИРТУАЛИЗАЦИЯ (Тотальный)
################################################################################

scan_containers_virt() {
    if [ "$SCAN_LEVEL" -lt $SCAN_TOTAL ]; then
        return
    fi
    
    print_section_header "CONTAINERS_VIRTUALIZATION"
    
    print_subsection_header "DOCKER_STATUS"
    if cmd_exists docker; then
        local docker_running="false"
        if systemctl is-active docker >/dev/null 2>&1; then
            docker_running="true"
        fi
        
        local container_count
        container_count=$(docker ps -a 2>/dev/null | grep -v "CONTAINER" | wc -l)
        local image_count
        image_count=$(docker images 2>/dev/null | grep -v "REPOSITORY" | wc -l)
        
        print_status "OK"
        print_data "Docker: ${docker_running:+Running}${docker_running:-Stopped}, Containers: $container_count, Images: $image_count"
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "Docker not installed"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "PODMAN_STATUS"
    if cmd_exists podman; then
        local podman_containers
        podman_containers=$(podman ps -a 2>/dev/null | grep -v "CONTAINER" | wc -l)
        print_status "OK"
        print_data "Podman containers: $podman_containers"
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "Podman not installed"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "VIRTUALIZATION_TYPE"
    local virt_type="Physical Machine"
    
    if cmd_exists virt-what; then
        local virt_info
        virt_info=$(sudo virt-what 2>/dev/null)
        if [ -n "$virt_info" ]; then
            virt_type="$virt_info"
        fi
    else
        # Альтернативная проверка
        if [ -f /sys/class/dmi/id/product_name ]; then
            local product_name
            product_name=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
            case "$product_name" in
                *"VirtualBox"*|*"VMware"*|*"QEMU"*|*"KVM"*|*"Hyper-V"*|*"Amazon EC2"*|*"Google Compute Engine"*)
                    virt_type="Virtual Machine ($product_name)"
                    ;;
            esac
        fi
    fi
    
    print_status "OK"
    print_data "Type: $virt_type"
    print_issues "None"
    echo ""
}

################################################################################
# СЕКЦИЯ 11: СПЕЦИФИЧЕСКОЕ ОБОРУДОВАНИЕ (Тотальный)
################################################################################

scan_hardware_specific() {
    if [ "$SCAN_LEVEL" -lt $SCAN_TOTAL ]; then
        return
    fi
    
    print_section_header "HARDWARE_SPECIFIC"
    
    print_subsection_header "GPU_DETAILS"
    local gpu_info
    gpu_info=$(lspci -nn 2>/dev/null | grep -iE "(vga|3d|display)" | head -5)
    print_status "OK"
    echo "• DATA:"
    echo "$gpu_info" | while read -r line; do
        echo "    $line"
    done
    
    # NVIDIA
    if cmd_exists nvidia-smi; then
        local nvidia_gpus
        nvidia_gpus=$(nvidia-smi -L 2>/dev/null | wc -l)
        echo "    NVIDIA GPUs: $nvidia_gpus"
    fi
    
    print_issues "None"
    echo ""
    
    print_subsection_header "BATTERY_INFO"
    if [ -d /sys/class/power_supply ]; then
        local batteries
        batteries=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null)
        
        if [ -n "$batteries" ]; then
            for bat in $batteries; do
                if [ -d "$bat" ]; then
                    local capacity
                    capacity=$(cat "$bat/capacity" 2>/dev/null || echo "N/A")
                    local status
                    status=$(cat "$bat/status" 2>/dev/null || echo "N/A")
                    local model
                    model=$(cat "$bat/model_name" 2>/dev/null || echo "N/A")
                    
                    print_status "OK"
                    print_data "Battery: $model, Capacity: ${capacity}%, Status: $status"
                    
                    if [ "$capacity" != "N/A" ] && [ "$capacity" -lt 50 ]; then
                        print_issues "Low battery capacity"
                        add_info "Battery capacity below 50% ($capacity%)" "$(basename "$bat")" "Consider battery calibration or replacement"
                    else
                        print_issues "None"
                    fi
                fi
            done
        else
            print_status "SKIPPED"
            print_data "No battery found (desktop?)"
            print_issues "None"
        fi
    else
        print_status "SKIPPED"
        print_data "Power supply info unavailable"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "THERMAL_SENSORS"
    if cmd_exists sensors; then
        local sensor_out
        sensor_out=$(sensors 2>/dev/null | head -30)
        print_status "OK"
        echo "• DATA:"
        echo "$sensor_out" | while read -r line; do
            echo "    $line"
        done
        
        # Проверка на высокие температуры
        if echo "$sensor_out" | grep -qE "Core.*\+[89][0-9]°C|Package.*\+[89][0-9]°C|edge.*\+[89][0-9]°C"; then
            print_issues "High temperatures detected"
            add_warning "CPU/GPU temperature above 80°C" "Thermal sensors" "Check cooling system and airflow"
        else
            print_issues "None"
        fi
    else
        print_status "SKIPPED"
        print_data "[TOOL_MISSING: lm-sensors]"
        print_issues "None"
    fi
    echo ""
    
    print_subsection_header "PCI_DEVICES"
    local pci_count
    pci_count=$(lspci 2>/dev/null | wc -l)
    print_status "OK"
    print_data "PCI devices: $pci_count"
    print_issues "None"
    echo ""
    
    print_subsection_header "USB_DEVICES"
    if cmd_exists lsusb; then
        local usb_count
        usb_count=$(lsusb 2>/dev/null | wc -l)
        print_status "OK"
        print_data "USB devices: $usb_count"
        print_issues "None"
    else
        print_status "SKIPPED"
        print_data "[TOOL_MISSING: lsusb]"
        print_issues "None"
    fi
    echo ""
}

################################################################################
# AI_SUMMARYReady - ИТОГОВАЯ СВОДКА ДЛЯ ИИ
################################################################################

generate_ai_summary() {
    print_section_header "AI_SUMMARY_READY"
    
    echo "### [PROBLEMS_LIST]"
    echo ""
    
    local has_issues="false"
    
    # Критические проблемы
    if [ ${#CRITICAL_ISSUES[@]} -gt 0 ]; then
        has_issues="true"
        echo "#### CRITICAL_ISSUES"
        for issue in "${CRITICAL_ISSUES[@]}"; do
            echo "$issue"
        done
        echo ""
    fi
    
    # Предупреждения
    if [ ${#WARNING_ISSUES[@]} -gt 0 ]; then
        has_issues="true"
        echo "#### WARNING_ISSUES"
        for issue in "${WARNING_ISSUES[@]}"; do
            echo "$issue"
        done
        echo ""
    fi
    
    # Информация
    if [ ${#INFO_ISSUES[@]} -gt 0 ]; then
        has_issues="true"
        echo "#### INFO_ISSUES"
        for issue in "${INFO_ISSUES[@]}"; do
            echo "$issue"
        done
        echo ""
    fi
    
    if [ "$has_issues" = "false" ]; then
        echo "✅ SYSTEM_HEALTHY: No critical issues detected."
        echo ""
    fi
    
    echo "### [SCAN_METADATA]"
    echo "• SCAN_LEVEL: $SCAN_LEVEL"
    echo "• HOSTNAME: $HOSTNAME_SHORT"
    echo "• TIMESTAMP: $TIMESTAMP"
    echo "• TOTAL_CRITICAL: ${#CRITICAL_ISSUES[@]}"
    echo "• TOTAL_WARNING: ${#WARNING_ISSUES[@]}"
    echo "• TOTAL_INFO: ${#INFO_ISSUES[@]}"
    echo ""
}

################################################################################
# ОСНОВНАЯ ФУНКЦИЯ
################################################################################

main() {
    # Показываем меню и получаем уровень сканирования
    show_scan_menu
    get_scan_level
    
    # Подготавливаем вывод
    prepare_output_dir
    
    echo ""
    echo -e "${BLUE}📁 Отчёт будет сохранён в:${NC}"
    echo -e "${YELLOW}$OUTPUT_FILE${NC}"
    echo ""
    echo -e "${CYAN}Запуск сканирования...${NC}"
    echo ""
    
    # Создаём отчёт
    {
        echo "========================================================================="
        echo "       DEEP SYSTEM SCAN REPORT"
        echo "       Generated: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "       Hostname: $HOSTNAME_SHORT"
        echo "       User: $USER"
        echo "       Scan Level: $SCAN_LEVEL ($([ "$SCAN_LEVEL" -eq 1 ] && echo "Minimal" || ([ "$SCAN_LEVEL" -eq 2 ] && echo "Medium" || echo "Total")))"
        echo "       Running as: $([ "$EUID" -eq 0 ] && echo 'root' || echo 'user')"
        echo "========================================================================="
        
        # Выполняем сканирование по уровням
        scan_general_info          # Уровень 1+
        scan_disk_space            # Уровень 1+
        scan_network               # Уровень 1+ (база), 2+ (подробно), 3 (полная безопасность)
        
        if [ "$SCAN_LEVEL" -ge $SCAN_MEDIUM ]; then
            scan_systemd_services  # Уровень 2+
            scan_packages          # Уровень 2+
            scan_storage           # Уровень 2+
        fi
        
        if [ "$SCAN_LEVEL" -ge $SCAN_TOTAL ]; then
            scan_security          # Уровень 3
            scan_config_validation # Уровень 3
            scan_containers_virt   # Уровень 3
            scan_hardware_specific # Уровень 3
        fi
        
        scan_logs                  # Уровень 1+ (база), 3 (полный)
        
        # Итоговая сводка для ИИ
        generate_ai_summary
        
        echo "========================================================================="
        echo "END OF REPORT"
        echo "Completed: $(date '+%Y-%m-%d %H:%M:%S %Z')"
        echo "========================================================================="
        
    } > "$OUTPUT_FILE" 2>&1
    
    # Вычисляем время выполнения
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    
    # Попытка вернуть права пользователю
    if [ -n "$SUDO_USER" ]; then
        chown "$SUDO_USER:$SUDO_USER" "$OUTPUT_FILE" 2>/dev/null || true
    fi
    
    # Проверка существования файла
    if [ -f "$OUTPUT_FILE" ]; then
        local file_size
        file_size=$(du -h "$OUTPUT_FILE" | cut -f1)
        
        echo ""
        echo -e "${GREEN}=========================================================${NC}"
        echo -e "${GREEN}   ✅ СКАНИРОВАНИЕ ЗАВЕРШЕНО!${NC}"
        echo -e "${GREEN}=========================================================${NC}"
        echo ""
        echo -e "${BLUE}📁 Абсолютный путь к отчёту:${NC}"
        echo -e "${YELLOW}$(realpath "$OUTPUT_FILE")${NC}"
        echo ""
        echo -e "${BLUE}⏱ Время выполнения: ${duration} сек.${NC}"
        echo -e "${BLUE}📊 Размер отчёта: ${file_size}${NC}"
        echo ""
        
        # Краткая сводка в терминал
        local crit_count=${#CRITICAL_ISSUES[@]}
        local warn_count=${#WARNING_ISSUES[@]}
        
        if [ "$crit_count" -gt 0 ]; then
            echo -e "${RED}⚠ Найдено критических проблем: $crit_count${NC}"
        fi
        if [ "$warn_count" -gt 0 ]; then
            echo -e "${YELLOW}⚠ Найдено предупреждений: $warn_count${NC}"
        fi
        if [ "$crit_count" -eq 0 ] && [ "$warn_count" -eq 0 ]; then
            echo -e "${GREEN}✅ Критических проблем не обнаружено${NC}"
        fi
        echo ""
        echo -e "${CYAN}Откройте файл для детального изучения.${NC}"
    else
        echo -e "${RED}❌ ОШИБКА: Файл отчёта не был создан!${NC}"
        exit 1
    fi
}

# Запуск
main
