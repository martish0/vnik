#!/bin/bash

################################################################################
# ULTIMATE SYSTEM DEEP SCAN SCRIPT
# Безопасный скрипт полной диагностики системы
# Собирает ВСЮ информацию: железо, логи, ПО, проблемы, конфигурации
# НЕ вносит изменений в систему (только чтение)
################################################################################

set -o pipefail

# Цвета для вывода в терминал
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Проверка на запуск от root (некоторые команды требуют sudo для полного отчета)
if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Внимание: Для полного сбора данных рекомендуется запускать через sudo.${NC}"
    echo -e "${YELLOW}Некоторые разделы могут быть неполными без прав суперпользователя.${NC}"
    echo ""
fi

# 1. Определение пути к Рабочему столу
get_desktop_path() {
    if [ -f "$HOME/.config/user-dirs.dirs" ]; then
        source "$HOME/.config/user-dirs.dirs" 2>/dev/null
        if [ -n "$XDG_DESKTOP_DIR" ] && [ -d "$XDG_DESKTOP_DIR" ]; then
            echo "$XDG_DESKTOP_DIR"
            return
        fi
    fi
    
    # Пробуем стандартные пути
    for path in "$HOME/Desktop" "$HOME/Рабочий стол" "$HOME"; do
        if [ -d "$path" ]; then
            echo "$path"
            return
        fi
    done
    
    echo "$HOME"
}

DESKTOP_PATH=$(get_desktop_path)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="${DESKTOP_PATH}/ULTIMATE_DEEP_SCAN_${TIMESTAMP}.log"
TEMP_DIR=$(mktemp -d)

# Функция для безопасного выполнения команд
safe_cmd() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${CYAN}→ ${description}...${NC}"
    eval "$cmd" 2>&1 || echo "[Ошибка выполнения: $cmd]"
}

# Функция для выполнения команд с sudo (если доступно)
safe_sudo_cmd() {
    local cmd="$1"
    local description="$2"
    
    echo -e "${CYAN}→ ${description}...${NC}"
    if [ "$EUID" -eq 0 ]; then
        eval "$cmd" 2>&1 || echo "[Ошибка выполнения: $cmd]"
    elif command -v sudo >/dev/null 2>&1; then
        sudo $cmd 2>&1 || echo "[Требуется sudo: $cmd]"
    else
        echo "[Требуется sudo: $cmd]"
    fi
}

echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}   ЗАПУСК ГЛУБОКОЙ ДИАГНОСТИКИ СИСТЕМЫ${NC}"
echo -e "${GREEN}   Ultimate Deep System Scan v2.0${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""
echo -e "${BLUE}Это может занять несколько минут. Отчет сохраняется в:${NC}"
echo -e "${YELLOW}$OUTPUT_FILE${NC}"
echo ""
echo -e "${CYAN}Сканирование всех подсистем: железо, логи, ПО, безопасность...${NC}"
echo ""

# Создаем отчет
{

echo "========================================================================="
echo "       ULTIMATE DEEP SYSTEM SCAN REPORT"
echo "       Дата генерации: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "      Hostname: $(hostname)"
echo "       Пользователь: $USER"
echo "       Запущено от: $([ "$EUID" -eq 0 ] && echo 'root' || echo 'user')"
echo "========================================================================="

###############################################################################
# РАЗДЕЛ 1: ОБЩАЯ ИНФОРМАЦИЯ О СИСТЕМЕ
###############################################################################
echo ""
echo "========================================================================="
echo "[РАЗДЕЛ 1] ОБЩАЯ ИНФОРМАЦИЯ О СИСТЕМЕ"
echo "========================================================================="

echo ""
echo "--- Ядро и версия системы ---"
uname -a
echo ""
echo "Версия ядра: $(uname -r)"
echo "Архитектура: $(uname -m)"
echo ""

echo "--- Информация о дистрибутиве ---"
if [ -f /etc/os-release ]; then
    cat /etc/os-release
elif command -v lsb_release >/dev/null 2>&1; then
    lsb_release -a 2>/dev/null
else
    cat /etc/*release 2>/dev/null | head -20
fi
echo ""

echo "--- Время работы системы ---"
uptime -p 2>/dev/null || uptime
echo "Загрузка системы: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

echo "--- Пользователи и группы ---"
echo "Текущий пользователь: $USER (UID: $(id -u), GID: $(id -g))"
echo "Все пользователи системы:"
cut -d: -f1 /etc/passwd | sort
echo ""
echo "Группы текущего пользователя:"
groups $USER 2>/dev/null || id -Gn
echo ""

echo "--- Переменные окружения ---"
echo "SHELL: $SHELL"
echo "HOME: $HOME"
echo "PATH: $PATH"
echo "LANG: $LANG"
echo ""

###############################################################################
# РАЗДЕЛ 2: ПОДРОБНАЯ ИНФОРМАЦИЯ О ЖЕЛЕЗЕ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 2] ДЕТАЛЬНАЯ ИНФОРМАЦИЯ О ЖЕЛЕЗЕ (HARDWARE)"
echo "========================================================================="

echo ""
echo "--- ПРОЦЕССОР (CPU) ---"
echo "Количество ядер: $(nproc)"
echo "Физические ядра: $(grep -c '^processor' /proc/cpuinfo)"
echo ""
if [ -f /proc/cpuinfo ]; then
    echo "Модель процессора:"
    grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | xargs
    echo ""
    echo "Подробная информация:"
    lscpu 2>/dev/null || cat /proc/cpuinfo | grep -E "model name|cpu MHz|cache size|cores|siblings" | head -20
fi
echo ""

echo "--- ОПЕРАТИВНАЯ ПАМЯТЬ (RAM) ---"
echo "Общая информация:"
free -h
echo ""
echo "Детали модулей памяти:"
if command -v dmidecode >/dev/null 2>&1; then
    safe_sudo_cmd "dmidecode -t memory" "Чтение информации о памяти из DMI"
elif [ -f /proc/meminfo ]; then
    cat /proc/meminfo | head -20
fi
echo ""

echo "--- МАТЕРИНСКАЯ ПЛАТА И BIOS ---"
echo "Информация о материнской плате:"
if command -v dmidecode >/dev/null 2>&1; then
    safe_sudo_cmd "dmidecode -t baseboard" "Чтение информации о материнской плате"
    echo ""
    echo "Информация о BIOS:"
    safe_sudo_cmd "dmidecode -t bios" "Чтение информации о BIOS"
else
    echo "dmidecode недоступен. Попробуйте установить: sudo apt install dmidecode"
fi
echo ""

echo "--- ВИДЕОКАРТЫ (GPU) ---"
echo "PCI устройства видеокарт:"
lspci -nn | grep -iE "(vga|3d|display)" 2>/dev/null || echo "Нет дискретных GPU"
echo ""
echo "Драйверы видеокарт:"
lspci -k | grep -A 3 -iE "(vga|3d|display)" 2>/dev/null || echo "Информация недоступна"
echo ""

# NVIDIA
if command -v nvidia-smi >/dev/null 2>&1; then
    echo "NVIDIA GPU Info:"
    nvidia-smi -L 2>/dev/null || nvidia-smi 2>/dev/null | head -30
    echo ""
fi

# AMD
if command -v rocm-smi >/dev/null 2>&1; then
    echo "AMD ROCm Info:"
    rocm-smi 2>/dev/null | head -20
    echo ""
fi

# Intel
if [ -d /sys/class/drm ]; then
    echo "Intel/DRM устройства:"
    ls -la /sys/class/drm/ 2>/dev/null | head -20
    echo ""
fi

echo "--- НАКОПИТЕЛИ (STORAGE) ---"
echo "Блочные устройства:"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,SERIAL,MODEL 2>/dev/null || lsblk
echo ""

echo "Информация о дисках (fdisk):"
safe_sudo_cmd "fdisk -l" "Чтение таблицы разделов" 2>/dev/null | head -50
echo ""

echo "SMART информация о дисках:"
if command -v smartctl >/dev/null 2>&1; then
    for drive in $(lsblk -dn -o NAME 2>/dev/null | grep -E "^sd|^nvme|^hd"); do
        echo "=== Устройство: /dev/$drive ==="
        safe_sudo_cmd "smartctl -i /dev/$drive" "SMART info для /dev/$drive" 2>/dev/null | head -30
        echo ""
        echo "Здоровье диска:"
        safe_sudo_cmd "smartctl -H /dev/$drive" "SMART health для /dev/$drive" 2>/dev/null
        echo ""
    done
else
    echo "smartctl не найден. Установите: sudo apt install smartmontools"
fi
echo ""

echo "--- PCI УСТРОЙСТВА ---"
echo "Все PCI устройства:"
lspci -vvv 2>/dev/null | head -100
echo ""

echo "--- USB УСТРОЙСТВА ---"
echo "Все USB устройства:"
lsusb -v 2>/dev/null | head -100 || lsusb
echo ""

echo "--- ЗВУКОВЫЕ УСТРОЙСТВА ---"
echo "Звуковые карты:"
aplay -l 2>/dev/null || echo "Команда aplay недоступна"
echo ""
if command -v pactl >/dev/null 2>&1; then
    echo "PulseAudio устройства:"
    pactl list short sinks 2>/dev/null
    pactl list short sources 2>/dev/null
    echo ""
fi

echo "--- СЕТЕВЫЕ ИНТЕРФЕЙСЫ ---"
echo "Физические интерфейсы:"
ip -br link 2>/dev/null || ip link
echo ""
echo "IP адреса:"
ip -br addr 2>/dev/null || ip addr
echo ""
echo "Таблица маршрутизации:"
ip route 2>/dev/null || route -n
echo ""

echo "--- ДАТЧИКИ И ТЕМПЕРАТУРЫ ---"
if command -v sensors >/dev/null 2>&1; then
    echo "Показания датчиков:"
    sensors 2>/dev/null || echo "sensors не доступен (установите lm-sensors)"
else
    echo "Утилита sensors не найдена. Установите: sudo apt install lm-sensors"
fi
echo ""

echo "Температуры из sysfs:"
for sensor in /sys/class/hwmon/hwmon*/temp*_input; do
    if [ -f "$sensor" ]; then
        name=$(cat $(dirname $sensor)/name 2>/dev/null)
        temp=$(cat $sensor 2>/dev/null)
        if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
            echo "$name: $((temp / 1000))°C"
        fi
    fi
done 2>/dev/null
echo ""

###############################################################################
# РАЗДЕЛ 3: УСТАНОВЛЕННОЕ ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 3] УСТАНОВЛЕННОЕ ПРОГРАММНОЕ ОБЕСПЕЧЕНИЕ"
echo "========================================================================="

echo ""
echo "--- ПАКЕТЫ APT/DPKG ---"
if command -v dpkg >/dev/null 2>&1; then
    total_packages=$(dpkg --get-selections 2>/dev/null | wc -l)
    installed_packages=$(dpkg --get-selections 2>/dev/null | grep -v deinstall | wc -l)
    echo "Всего пакетов в базе: $total_packages"
    echo "Установлено пакетов: $installed_packages"
    echo ""
    
    echo "Последние установленные пакеты (50):"
    if [ -f /var/log/dpkg.log ]; then
        grep " install " /var/log/dpkg.log 2>/dev/null | tail -50
    fi
    if [ -f /var/log/dpkg.log.1 ]; then
        grep " install " /var/log/dpkg.log.1 2>/dev/null | tail -20
    fi
    echo ""
    
    echo "Пакеты с проблемами установки:"
    dpkg --audit 2>/dev/null || echo "Проблем не обнаружено"
    echo ""
fi

echo "--- РЕПОЗИТОРИИ ---"
echo "Основные репозитории:"
if [ -f /etc/apt/sources.list ]; then
    cat /etc/apt/sources.list 2>/dev/null
fi
echo ""
echo "Дополнительные репозитории (PPA):"
if [ -d /etc/apt/sources.list.d ]; then
    for repo in /etc/apt/sources.list.d/*.list; do
        if [ -f "$repo" ]; then
            echo "=== $repo ==="
            cat "$repo" 2>/dev/null
        fi
    done
fi
echo ""

echo "--- SNAP ПАКЕТЫ ---"
if command -v snap >/dev/null 2>&1; then
    echo "Установленные Snap пакеты:"
    snap list 2>/dev/null || echo "Snap не доступен"
    echo ""
    echo "Версия snapd:"
    snap version 2>/dev/null
else
    echo "Snap не установлен"
fi
echo ""

echo "--- FLATPAK ПАКЕТЫ ---"
if command -v flatpak >/dev/null 2>&1; then
    echo "Установленные Flatpak пакеты:"
    flatpak list --columns=application,version,origin 2>/dev/null || echo "Нет установленных пакетов"
    echo ""
    echo "Flatpak remotes:"
    flatpak remotes 2>/dev/null
else
    echo "Flatpak не установлен"
fi
echo ""

echo "--- APPIMAGE И ПОРТАТИВНЫЕ ПРИЛОЖЕНИЯ ---"
echo "Поиск AppImage файлов в домашних директориях:"
find $HOME -name "*.AppImage" -type f 2>/dev/null | head -20 || echo "Не найдено"
echo ""

echo "--- PYTHON ПАКЕТЫ ---"
if command -v pip3 >/dev/null 2>&1; then
    echo "Global Python packages:"
    pip3 list 2>/dev/null | head -50 || echo "pip3 недоступен"
    echo ""
fi

if command -v pip >/dev/null 2>&1; then
    echo "User Python packages:"
    pip list --user 2>/dev/null | head -30 || echo "Нет пользовательских пакетов"
    echo ""
fi

echo "--- NODE.JS ПАКЕТЫ ---"
if command -v npm >/dev/null 2>&1; then
    echo "Global NPM packages:"
    npm list -g --depth=0 2>/dev/null | head -30 || echo "npm глобальные пакеты недоступны"
    echo ""
fi

echo "--- RUST/CARGO ПАКЕТЫ ---"
if command -v cargo >/dev/null 2>&1; then
    echo "Установленные Cargo crates:"
    cargo install --list 2>/dev/null | head -30 || echo "Нет установленных crates"
    echo ""
fi

echo "--- JAVA Версии ---"
if command -v java >/dev/null 2>&1; then
    java -version 2>&1
    echo ""
fi
if command -v javac >/dev/null 2>&1; then
    javac -version 2>&1
    echo ""
fi

echo "--- ДОСТУПНЫЕ КОМПИЛЯТОРЫ ---"
echo "GCC версии:"
gcc --version 2>/dev/null | head -2 || echo "GCC не установлен"
echo ""
echo "G++ версии:"
g++ --version 2>/dev/null | head -2 || echo "G++ не установлен"
echo ""
echo "Clang версии:"
clang --version 2>/dev/null | head -2 || echo "Clang не установлен"
echo ""

echo "--- СИСТЕМНЫЕ УТИЛИТЫ И ВЕРСИИ ---"
echo "Bash: $(bash --version | head -1)"
echo "Coreutils: $(ls --version | head -1)"
echo "Systemd: $(systemctl --version | head -1)"
echo ""

###############################################################################
# РАЗДЕЛ 4: СИСТЕМНЫЕ СЛУЖБЫ И ПРОЦЕССЫ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 4] СИСТЕМНЫЕ СЛУЖБЫ И ПРОЦЕССЫ"
echo "========================================================================="

echo ""
echo "--- SYSTEMD ЮНИТЫ ---"
echo "Активные службы:"
systemctl list-units --type=service --state=running --no-pager 2>/dev/null | head -50
echo ""

echo "Неактивные службы:"
systemctl list-units --type=service --state=exited --no-pager 2>/dev/null | head -30
echo ""

echo "Отключенные службы:"
systemctl list-unit-files --type=service --state=disabled --no-pager 2>/dev/null | head -30
echo ""

echo "Замаскированные службы:"
systemctl list-unit-files --type=service --state=masked --no-pager 2>/dev/null | head -20
echo ""

echo "--- ТАЙМЕРЫ SYSTEMD ---"
systemctl list-timers --all --no-pager 2>/dev/null | head -30
echo ""

echo "--- СОКЕТЫ SYSTEMD ---"
systemctl list-sockets --all --no-pager 2>/dev/null | head -20
echo ""

echo "--- ТОП ПРОЦЕССОВ ПО CPU ---"
echo "Топ 20 процессов по использованию CPU:"
ps aux --sort=-%cpu | head -21
echo ""

echo "--- ТОП ПРОЦЕССОВ ПО ПАМЯТИ ---"
echo "Топ 20 процессов по использованию памяти:"
ps aux --sort=-%mem | head -21
echo ""

echo "--- ПРОЦЕССЫ В ZOMBIE STATE ---"
zombie_procs=$(ps aux | awk '$8 ~ /Z/ {print}')
if [ -n "$zombie_procs" ]; then
    echo "Найдены процессы-зомби:"
    echo "$zombie_procs"
else
    echo "Процессы-зомби не обнаружены"
fi
echo ""

echo "--- ПРОЦЕССЫ ОТ ROOT ---"
echo "Процессы запущенные от root:"
ps -U root -u root u | head -30
echo ""

###############################################################################
# РАЗДЕЛ 5: АНАЛИЗ ЛОГОВ И ПОИСК ПРОБЛЕМ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 5] АНАЛИЗ ЛОГОВ И ПОИСК ПРОБЛЕМ"
echo "========================================================================="

echo ""
echo "--- FAILED SYSTEMD UNITS ---"
failed_units=$(systemctl list-units --state=failed --no-pager 2>/dev/null)
if [ -n "$failed_units" ]; then
    echo "⚠️ ОБНАРУЖЕНЫ ПАВШИЕ СЛУЖБЫ:"
    echo "$failed_units"
    echo ""
    echo "Детали ошибок:"
    systemctl list-units --state=failed --no-pager --full 2>/dev/null
else
    echo "✓ Все службы работают нормально"
fi
echo ""

echo "--- КРИТИЧЕСКИЕ ОШИБКИ В JOURNALCTL (приоритет 0-3) ---"
echo "Emergency, Alert, Critical, Error сообщения:"
safe_sudo_cmd "journalctl -p 3 -xb --no-pager --no-hostname" "Чтение критических ошибок из журнала" 2>/dev/null | tail -100
echo ""

echo "--- ПРЕДУПРЕЖДЕНИЯ В JOURNALCTL (приоритет 4) ---"
echo "Warning сообщения за текущую загрузку:"
safe_sudo_cmd "journalctl -p 4 -xb --no-pager --no-hostname" "Чтение предупреждений из журнала" 2>/dev/null | tail -50
echo ""

echo "--- АНАЛИЗ DMSG (ЯДРО) ---"
echo "Последние сообщения ядра:"
dmesg --level=err,crit,alert,emerg 2>/dev/null | tail -50 || dmesg | grep -iE "error|fail|critical" | tail -50
echo ""

echo "Сообщения ядра о проблемах с оборудованием:"
dmesg 2>/dev/null | grep -iE "hardware error|mce|edac|pci error" | tail -30 || echo "Явных ошибок оборудования не найдено"
echo ""

echo "--- ОШИБКИ СЕГМЕНТАЦИИ (SEGFAULT) ---"
echo "Последние segfault:"
dmesg 2>/dev/null | grep -i "segfault" | tail -20 || journalctl -xb 2>/dev/null | grep -i "segfault" | tail -20
if [ $? -ne 0 ]; then
    echo "Ошибок сегментации не найдено"
fi
echo ""

echo "--- ПРОБЛЕМЫ С ПАМЯТЬЮ (OOM KILLER) ---"
echo "Сообщения OOM Killer:"
dmesg 2>/dev/null | grep -i "out of memory\|oom-killer\|killed process" | tail -30 || echo "OOM событий не найдено"
journalctl -xb 2>/dev/null | grep -i "oom" | tail -20
echo ""

echo "--- ПРОБЛЕМЫ С ДИСКАМИ ---"
echo "Ошибки ввода-вывода:"
dmesg 2>/dev/null | grep -iE "i/o error|read error|write error|sector" | tail -30 || echo "Ошибок диска не найдено"
echo ""

echo "--- ПРОБЛЕМЫ С ПЕРЕГРЕВОМ ---"
echo "Термальные события:"
dmesg 2>/dev/null | grep -iE "thermal|throttling|critical temperature|overheat" | tail -30 || echo "Термальных проблем не найдено"
echo ""

echo "--- ПРОБЛЕМЫ С ПИТАНИЕМ ---"
echo "ACPI ошибки:"
dmesg 2>/dev/null | grep -i "acpi" | grep -iE "error|fail" | tail -20 || echo "ACPI ошибок не найдено"
echo ""

echo "--- NETWORK ERRORS ---"
echo "Ошибки сети:"
dmesg 2>/dev/null | grep -iE "network|eth|wlan|wifi" | grep -iE "error|fail|disconnect" | tail -30 || echo "Ошибок сети не найдено"
echo ""

echo "--- ANALYZING LOG FILES ---"
echo "Размеры лог-файлов:"
if [ -d /var/log ]; then
    du -sh /var/log/* 2>/dev/null | sort -hr | head -20
fi
echo ""

echo "Последние ошибки в syslog:"
if [ -f /var/log/syslog ]; then
    echo "=== /var/log/syslog (последние 50 строк с ошибками) ==="
    grep -iE "error|fail|critical" /var/log/syslog 2>/dev/null | tail -50
fi
echo ""

echo "Ошибки в kern.log:"
if [ -f /var/log/kern.log ]; then
    grep -iE "error|fail|critical" /var/log/kern.log 2>/dev/null | tail -50
fi
echo ""

echo "Ошибки в Xorg.log:"
for logfile in /var/log/Xorg*.log ~/.local/share/xorg/Xorg.*.log; do
    if [ -f "$logfile" ]; then
        echo "=== $logfile ==="
        grep -iE "error|fail|ww" "$logfile" 2>/dev/null | tail -30
    fi
done
echo ""

echo "Auth.log ошибки аутентификации:"
if [ -f /var/log/auth.log ]; then
    echo "Неудачные попытки входа:"
    grep -i "failed\|failure\|invalid" /var/log/auth.log 2>/dev/null | tail -30
fi
echo ""

echo "Boot log ошибки:"
if [ -f /var/log/boot.log ]; then
    grep -i "fail" /var/log/boot.log 2>/dev/null | tail -20
fi
echo ""

echo "--- АНАЛИЗ CORE DUMPS ---"
echo "Последние core dump файлы:"
if [ -d /var/crash ]; then
    ls -lht /var/crash/ 2>/dev/null | head -10 || echo "Нет core dump файлов"
fi
if [ -d /var/lib/systemd/coredump ]; then
    ls -lht /var/lib/systemd/coredump/ 2>/dev/null | head -10
fi
echo ""

###############################################################################
# РАЗДЕЛ 6: ХРАНИЛИЩА И ФАЙЛОВЫЕ СИСТЕМЫ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 6] ХРАНИЛИЩА И ФАЙЛОВЫЕ СИСТЕМЫ"
echo "========================================================================="

echo ""
echo "--- ИСПОЛЬЗОВАНИЕ ДИСКОВОГО ПРОСТРАНСТВА ---"
df -hT --total 2>/dev/null
echo ""

echo "Использование по точкам монтирования:"
df -h 2>/dev/null | grep -E "^/dev|^Filesystem"
echo ""

echo "--- INODE USAGE ---"
df -i 2>/dev/null | grep -E "^/dev|^Filesystem"
echo ""

echo "--- LVM ИНФОРМАЦИЯ ---"
if command -v lvdisplay >/dev/null 2>&1; then
    safe_sudo_cmd "lvdisplay" "LVM Logical Volumes" 2>/dev/null | head -50
    safe_sudo_cmd "vgdisplay" "LVM Volume Groups" 2>/dev/null | head -30
    safe_sudo_cmd "pvdisplay" "LVM Physical Volumes" 2>/dev/null | head -30
else
    echo "LVM инструменты не установлены"
fi
echo ""

echo "--- RAID ИНФОРМАЦИЯ ---"
if [ -f /proc/mdstat ]; then
    echo "Статус MD RAID:"
    cat /proc/mdstat
fi
echo ""

echo "--- МОНТИРОВАННЫЕ ФАЙЛОВЫЕ СИСТЕМЫ ---"
echo "Active mounts:"
mount | grep -E "^/dev"
echo ""

echo "/etc/fstab entries:"
if [ -f /etc/fstab ]; then
    cat /etc/fstab
fi
echo ""

echo "--- SWAP ---"
echo "Swap устройства:"
swapon --show 2>/dev/null || swapon -s
echo ""
echo "Swap usage:"
free -h | grep -i swap
echo ""

###############################################################################
# РАЗДЕЛ 7: СЕТЬ И БЕЗОПАСНОСТЬ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 7] СЕТЬ И БЕЗОПАСНОСТЬ"
echo "========================================================================="

echo ""
echo "--- СЕТЕВЫЕ ИНТЕРФЕЙСЫ (ДЕТАЛЬНО) ---"
ip -d addr 2>/dev/null
echo ""

echo "--- ARP TABLE ---"
ip neigh 2>/dev/null || arp -a
echo ""

echo "--- LISTENING PORTS ---"
echo "TCP порты в состоянии LISTEN:"
ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null
echo ""

echo "UDP порты:"
ss -ulnp 2>/dev/null || netstat -ulnp 2>/dev/null
echo ""

echo "Все слушающие сокеты с процессами:"
safe_sudo_cmd "ss -tulpn" "Полный список слушающих портов" 2>/dev/null
echo ""

echo "--- ACTIVE CONNECTIONS ---"
echo "Установленные соединения:"
ss -tn state established 2>/dev/null | head -30
echo ""

echo "--- ROUTING TABLE ---"
ip route show table all 2>/dev/null | head -50
echo ""

echo "--- DNS CONFIGURATION ---"
echo "DNS серверы:"
cat /etc/resolv.conf 2>/dev/null
echo ""
if command -v systemd-resolve >/dev/null 2>&1; then
    systemd-resolve --status 2>/dev/null | head -30
fi
echo ""

echo "--- FIREWALL STATUS ---"
echo "UFW статус:"
if command -v ufw >/dev/null 2>&1; then
    safe_sudo_cmd "ufw status verbose" "Статус UFW firewall"
else
    echo "UFW не установлен"
fi
echo ""

echo "iptables правила:"
if command -v iptables >/dev/null 2>&1; then
    safe_sudo_cmd "iptables -L -n -v" "iptables правила" 2>/dev/null | head -50
fi
echo ""

echo "nftables правила:"
if command -v nft >/dev/null 2>&1; then
    safe_sudo_cmd "nft list ruleset" "nftables правила" 2>/dev/null | head -50
fi
echo ""

echo "--- SELINUX/AppArmor ---"
echo "AppArmor статус:"
if command -v aa-status >/dev/null 2>&1; then
    safe_sudo_cmd "aa-status" "AppArmor статус" 2>/dev/null
else
    echo "AppArmor инструменты не установлены"
fi
echo ""

if [ -f /sys/kernel/security/apparmor/status ]; then
    cat /sys/kernel/security/apparmor/status 2>/dev/null | head -20
fi
echo ""

echo "--- SSH CONFIGURATION ---"
echo "SSH сервис статус:"
systemctl status sshd 2>/dev/null | head -15 || systemctl status ssh 2>/dev/null | head -15 || echo "SSH сервис не найден"
echo ""

echo "SSH конфигурация:"
if [ -f /etc/ssh/sshd_config ]; then
    grep -v "^#" /etc/ssh/sshd_config 2>/dev/null | grep -v "^$" | head -30
fi
echo ""

echo "--- ПОСЛЕДНИЕ ВХОДЫ В СИСТЕМУ ---"
echo "Последние успешные входы:"
last 2>/dev/null | head -20
echo ""

echo "Последние неудачные попытки входа:"
lastb 2>/dev/null | head -20 || echo "Требуется sudo для просмотра lastb"
echo ""

echo "--- SUDO LOGS ---"
if [ -f /var/log/auth.log ]; then
    echo "Последние использования sudo:"
    grep "sudo:" /var/log/auth.log 2>/dev/null | tail -20
fi
echo ""

###############################################################################
# РАЗДЕЛ 8: КОНФИГУРАЦИОННЫЕ ФАЙЛЫ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 8] ВАЖНЫЕ КОНФИГУРАЦИОННЫЕ ФАЙЛЫ"
echo "========================================================================="

echo ""
echo "--- GRUB CONFIGURATION ---"
if [ -f /etc/default/grub ]; then
    echo "GRUB настройки:"
    cat /etc/default/grub
fi
echo ""

echo "--- MODULES BLACKLIST ---"
for blacklist in /etc/modprobe.d/*.conf; do
    if [ -f "$blacklist" ]; then
        echo "=== $blacklist ==="
        grep -v "^#" "$blacklist" 2>/dev/null | grep -v "^$"
    fi
done
echo ""

echo "--- SYSCTL SETTINGS ---"
if [ -f /etc/sysctl.conf ]; then
    echo "Custom sysctl settings:"
    grep -v "^#" /etc/sysctl.conf 2>/dev/null | grep -v "^$" | head -30
fi
echo ""

echo "Current sysctl values (security related):"
sysctl -a 2>/dev/null | grep -E "net.ipv4.tcp_syncookies|kernel.randomize_va_space|kernel.exec-shield" | head -20
echo ""

echo "--- LIMITS CONFIGURATION ---"
if [ -f /etc/security/limits.conf ]; then
    echo "User limits:"
    grep -v "^#" /etc/security/limits.conf 2>/dev/null | grep -v "^$" | head -20
fi
echo ""

echo "--- PAM CONFIGURATION ---"
echo "PAM modules:"
ls -la /etc/pam.d/ 2>/dev/null
echo ""

###############################################################################
# РАЗДЕЛ 9: ПОЛЬЗОВАТЕЛЬСКИЕ ДАННЫЕ И ПРАВА
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 9] ПОЛЬЗОВАТЕЛЬСКИЕ ДАННЫЕ И ПРАВА ДОСТУПА"
echo "========================================================================="

echo ""
echo "--- HOME DIRECTORY USAGE ---"
echo "Размер домашней директории:"
du -sh $HOME 2>/dev/null
echo ""

echo "Топ 20 самых больших директорий в home:"
du -Ah $HOME 2>/dev/null | sort -hr | head -20
echo ""

echo "Топ 20 самых больших файлов в home:"
find $HOME -type f -exec du -h {} + 2>/dev/null | sort -hr | head -20
echo ""

echo "--- SUID/SGID FILES ---"
echo "Файлы с SUID битом (потенциальная уязвимость):"
find / -perm -4000 -type f 2>/dev/null | head -30
echo ""

echo "Файлы с SGID битом:"
find / -perm -2000 -type f 2>/dev/null | head -30
echo ""

echo "--- WORLD-WRITABLE FILES ---"
echo "Файлы доступные для записи всем (кроме /proc, /sys, /dev):"
find / -type f -perm -0002 ! -path "/proc/*" ! -path "/sys/*" ! -path "/dev/*" 2>/dev/null | head -50
echo ""

echo "--- CRON JOBS ---"
echo "Системные cron задачи:"
if [ -d /etc/cron.d ]; then
    ls -la /etc/cron.d/ 2>/dev/null
fi
echo ""

echo "Crontab текущего пользователя:"
crontab -l 2>/dev/null || echo "Нет задач в crontab"
echo ""

echo "Системный crontab:"
if [ -f /etc/crontab ]; then
    cat /etc/crontab
fi
echo ""

echo "--- STARTUP APPLICATIONS ---"
echo "Автозагрузка пользователя:"
ls -la ~/.config/autostart/ 2>/dev/null || echo "Нет автозагрузки"
echo ""

echo "Systemd user services:"
systemctl --user list-units --type=service 2>/dev/null | head -20
echo ""

###############################################################################
# РАЗДЕЛ 10: СПЕЦИФИЧНОЕ ОБОРУДОВАНИЕ (ASUS ROG И ДРУГИЕ)
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 10] СПЕЦИФИЧЕСКОЕ ОБОРУДОВАНИЕ И ВЕНДОРСКИЕ УТИЛИТЫ"
echo "========================================================================="

echo ""
echo "--- ASUS ROG СПЕЦИФИКА ---"
if [ -d /sys/class/leds/asus::kbd_backlight ]; then
    echo "✓ Клавиатура ASUS с подсветкой обнаружена"
    echo "Максимальная яркость:"
    cat /sys/class/leds/asus::kbd_backlight/max_brightness 2>/dev/null
    echo "Текущая яркость:"
    cat /sys/class/leds/asus::kbd_backlight/brightness 2>/dev/null
fi
echo ""

if command -v asusctl >/dev/null 2>&1; then
    echo "ASUS Control Center (asusctl):"
    asusctl -i 2>/dev/null || asusctl profile 2>/dev/null
fi
echo ""

if command -v supergfxctl >/dev/null 2>&1; then
    echo "SuperGFXCtl (GPU переключение):"
    supergfxctl -g 2>/dev/null
fi
echo ""

echo "--- LAPTOP BATTERY INFO ---"
if [ -d /sys/class/power_supply ]; then
    echo "Устройства питания:"
    ls /sys/class/power_supply/
    echo ""
    
    for battery in /sys/class/power_supply/BAT*; do
        if [ -d "$battery" ]; then
            echo "=== Battery Info ==="
            echo "Manufacturer: $(cat $battery/manufacturer 2>/dev/null)"
            echo "Model: $(cat $battery/model_name 2>/dev/null)"
            echo "Capacity: $(cat $battery/capacity 2>/dev/null)%"
            echo "Status: $(cat $battery/status 2>/dev/null)"
            echo "Energy Full: $(cat $battery/energy_full 2>/dev/null) μWh"
            echo "Energy Now: $(cat $battery/energy_now 2>/dev/null) μWh"
            echo ""
        fi
    done
fi

echo "--- AC ADAPTER ---"
for adapter in /sys/class/power_supply/AC* /sys/class/power_supply/ADP*; do
    if [ -d "$adapter" ]; then
        echo "AC Status: $(cat $adapter/online 2>/dev/null)"
    fi
done
echo ""

###############################################################################
# РАЗДЕЛ 11: ДОПОЛНИТЕЛЬНЫЙ АНАЛИЗ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 11] ДОПОЛНИТЕЛЬНЫЙ АНАЛИЗ И СТАТИСТИКА"
echo "========================================================================="

echo ""
echo "--- FILESYSTEM STATISTICS ---"
echo "Статистика ФС для корневой директории:"
tune2fs -l /dev/$(lsblk -o NAME,MOUNTPOINT | grep " / " | awk '{print $1}') 2>/dev/null | head -30 || echo "Не удалось получить статистику ext FS"
echo ""

echo "--- KERNEL PARAMETERS ---"
echo "Количество загруженных модулей ядра:"
lsmod | wc -l
echo ""
echo "Загруженные модули ядра:"
lsmod | head -50
echo ""

echo "--- CONTAINERS ---"
echo "Docker контейнеры:"
if command -v docker >/dev/null 2>&1; then
    docker ps -a 2>/dev/null | head -20 || echo "Docker не запущен или нет доступа"
    echo ""
    echo "Docker images:"
    docker images 2>/dev/null | head -20
else
    echo "Docker не установлен"
fi
echo ""

echo "Podman контейнеры:"
if command -v podman >/dev/null 2>&1; then
    podman ps -a 2>/dev/null | head -20 || echo "Нет контейнеров или podman не запущен"
else
    echo "Podman не установлен"
fi
echo ""

echo "--- VIRTUALIZATION ---"
echo "Проверка виртуализации:"
if command -v virt-what >/dev/null 2>&1; then
    safe_sudo_cmd "virt-what" "Определение типа виртуализации"
else
    echo "Утилита virt-what не установлена"
    # Альтернативная проверка
    if [ -f /sys/class/dmi/id/product_name ]; then
        product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
        echo "Product Name: $product"
        case "$product" in
            *"VirtualBox"*|*"VMware"*|*"QEMU"*|*"KVM"*|*"Hyper-V"*|*"Amazon EC2"*|*"Google Compute Engine"*)
                echo "⚠ Обнаружена виртуальная машина"
                ;;
            *)
                echo "✓ Похоже на физическую машину"
                ;;
        esac
    fi
fi
echo ""

echo "--- HARDWARE RANDOM NUMBER GENERATOR ---"
if [ -d /dev/hwrng ]; then
    echo "HRNG доступен"
else
    echo "HRNG не обнаружен"
fi
echo ""

###############################################################################
# РАЗДЕЛ 12: СВОДКА ПРОБЛЕМ
###############################################################################
echo "========================================================================="
echo "[РАЗДЕЛ 12] СВОДКА ВЫЯВЛЕННЫХ ПРОБЛЕМ"
echo "========================================================================="

echo ""
problem_count=0

echo "🔴 КРИТИЧЕСКИЕ ПРОБЛЕМЫ:"
echo "------------------------"

# Проверка failed служб
failed_count=$(systemctl list-units --state=failed --no-pager 2>/dev/null | grep -c "loaded" || echo 0)
if [ "$failed_count" -gt 0 ]; then
    echo "❌ $failed_count упавших системных служб"
    ((problem_count++))
fi

# Проверка места на диске
disk_usage=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%')
if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 90 ]; then
    echo "❌ Критически мало места на диске: ${disk_usage}% занято"
    ((problem_count++))
fi

# Проверка OOM
oom_count=$(dmesg 2>/dev/null | grep -c "oom-killer" 2>/dev/null || echo 0)
oom_count=${oom_count:-0}
if [ "$oom_count" -gt 0 ] 2>/dev/null; then
    echo "❌ Обнаружено $oom_count событий OOM Killer"
    ((problem_count++))
fi

# Проверка segfault
segfault_count=$(dmesg 2>/dev/null | grep -c "segfault" 2>/dev/null || echo 0)
segfault_count=${segfault_count:-0}
if [ "$segfault_count" -gt 0 ] 2>/dev/null; then
    echo "❌ Обнаружено $segfault_count ошибок сегментации"
    ((problem_count++))
fi

# Проверка SMART
if command -v smartctl >/dev/null 2>&1; then
    for drive in $(lsblk -dn -o NAME 2>/dev/null | grep -E "^sd|^nvme"); do
        health=$(smartctl -H /dev/$drive 2>/dev/null | grep -i "test result")
        if echo "$health" | grep -qi "failed"; then
            echo "❌ Проблема с здоровьем диска /dev/$drive"
            ((problem_count++))
        fi
    done
fi

echo ""
echo "🟡 ПРЕДУПРЕЖДЕНИЯ:"
echo "------------------"

# Предупреждение о месте на диске
if [ -n "$disk_usage" ] && [ "$disk_usage" -gt 75 ] && [ "$disk_usage" -le 90 ]; then
    echo "⚠ Место на диске заканчивается: ${disk_usage}% занято"
    ((problem_count++))
fi

# Проверка обновлений
if command -v apt >/dev/null 2>&1; then
    update_count=$(apt list --upgradable 2>/dev/null | grep -c "/" || echo 0)
    if [ "$update_count" -gt 50 ]; then
        echo "⚠ Доступно много обновлений: $update_count пакетов"
    fi
fi

# Проверка старых ядер
old_kernels=$(dpkg --list 2>/dev/null | grep -c "linux-image-[0-9]" || echo 0)
if [ "$old_kernels" -gt 3 ]; then
    echo "⚠ Установлено много версий ядра: $old_kernels (рекомендуется очистить)"
fi

echo ""
if [ "$problem_count" -eq 0 ]; then
    echo "✅ Критических проблем не обнаружено!"
else
    echo "📊 Всего выявлено проблем/предупреждений: $problem_count"
fi
echo ""

###############################################################################
# ЗАВЕРШЕНИЕ
###############################################################################
echo "========================================================================="
echo "КОНЕЦ ОТЧЕТА"
echo "========================================================================="
echo "Дата завершения: $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Время сканирования: $(($(date +%s) - $start_time)) секунд"
echo "========================================================================="

} > "$OUTPUT_FILE" 2>&1

# Вычисляем время выполнения
end_time=$(date +%s)
duration=$((end_time - start_time))

# Возвращаем права пользователю
current_user=$(logname 2>/dev/null || echo $USER)
chown $current_user:$current_user "$OUTPUT_FILE" 2>/dev/null

# Вывод результатов в терминал
echo ""
echo -e "${GREEN}=========================================================${NC}"
echo -e "${GREEN}   ✅ ГЛУБОКИЙ АНАЛИЗ СИСТЕМЫ ЗАВЕРШЕН!${NC}"
echo -e "${GREEN}=========================================================${NC}"
echo ""
echo -e "${BLUE}📁 Полный отчет сохранен в:${NC}"
echo -e "${YELLOW}$OUTPUT_FILE${NC}"
echo ""
echo -e "${BLUE}⏱ Время выполнения: ${duration} сек.${NC}"
echo -e "${BLUE}📊 Размер отчета: $(du -h "$OUTPUT_FILE" | cut -f1)${NC}"
echo ""
echo -e "${CYAN}Рекомендации:${NC}"
echo "  • Откройте файл в текстовом редакторе для детального изучения"
echo "  • Используйте поиск (Ctrl+F) для нахождения конкретных проблем"
echo "  • Раздел 12 содержит сводку всех выявленных проблем"
echo ""
echo -e "${YELLOW}⚠ Важно: Этот скрипт только собирает информацию и не вносит изменений в систему.${NC}"
echo ""
