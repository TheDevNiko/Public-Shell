#!/usr/bin/env bash
# 设置严格模式
set -euo pipefail
IFS=$'\n\t'  # 添加IFS设置，使数组处理更安全

# 定义颜色输出
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# 脚本路径和名称定义
readonly SCRIPT_PATH="/usr/local/bin"
readonly SCRIPT_NAME="timesync.sh"
readonly FULL_SCRIPT_PATH="${SCRIPT_PATH}/${SCRIPT_NAME}"
readonly LOG_FILE="/var/log/timesync.log"
readonly CONFIG_FILE="/etc/timesync.conf"
readonly LOG_DAYS=7  # 日志保留天数

# 默认配置
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
declare -a DEFAULT_SERVERS=(
    "ntp.aliyun.com"
    "time1.cloud.tencent.com"
    "cn.pool.ntp.org"
    "ntp.ntsc.ac.cn"
)

# 声明全局变量
declare TIMEZONE
declare -a NTP_SERVERS

# 记录脚本内容
log_script_content() {
    local timezone=${1:-$DEFAULT_TIMEZONE}
    # 替换时区中的斜杠为连字符
    local formatted_timezone=${timezone//\//-}
    local content_file="${SCRIPT_PATH}/Synctime-${formatted_timezone}.sh"
    
    log "记录脚本内容到 $content_file"
    cat > "$content_file" << 'EOF'
#!/usr/bin/env bash
# 设置严格模式
set -euo pipefail
IFS=$'\n\t'  # 添加IFS设置，使数组处理更安全

# 定义颜色输出
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# 脚本路径和名称定义
readonly SCRIPT_PATH="/usr/local/bin"
readonly SCRIPT_NAME="timesync.sh"
readonly FULL_SCRIPT_PATH="${SCRIPT_PATH}/${SCRIPT_NAME}"
readonly LOG_FILE="/var/log/timesync.log"
readonly CONFIG_FILE="/etc/timesync.conf"
readonly LOG_DAYS=7  # 日志保留天数

# 默认配置
readonly DEFAULT_TIMEZONE="Asia/Shanghai"
declare -a DEFAULT_SERVERS=(
    "ntp.aliyun.com"
    "time1.cloud.tencent.com"
    "cn.pool.ntp.org"
    "ntp.ntsc.ac.cn"
)

# 声明全局变量
declare TIMEZONE
declare -a NTP_SERVERS

# 日志函数
log() {
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] 错误: $1${NC}" >&2 | tee -a "$LOG_FILE"
    exit 1
}

# 清理旧日志
cleanup_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        log "清理超过 ${LOG_DAYS} 天的旧日志..."
        local temp_file="${LOG_FILE}.tmp"
        touch -d "-${LOG_DAYS} days" "$temp_file"
        
        if [[ "$LOG_FILE" -ot "$temp_file" ]]; then
            log "删除旧日志文件"
            > "$LOG_FILE"  # 清空日志文件而不是删除它，以保持文件权限
        fi
        rm -f "$temp_file"
    fi
}

# 检查依赖命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1 || error "未找到命令: $1，请先安装"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要root权限运行"
    fi
}

# 创建必要的目录
create_directories() {
    local dirs=("$(dirname "$LOG_FILE")" "$(dirname "$CONFIG_FILE")" "$SCRIPT_PATH")
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || mkdir -p "$dir" || error "无法创建目录: $dir"
    done
}

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log "加载配置文件: $CONFIG_FILE"
    else
        log "未找到配置文件，使用默认配置"
        TIMEZONE="$DEFAULT_TIMEZONE"
        NTP_SERVERS=("${DEFAULT_SERVERS[@]}")
        save_config
    fi
}

# 保存配置文件
save_config() {
    log "保存配置到 $CONFIG_FILE"
    {
        echo "TIMEZONE=\"$TIMEZONE\""
        echo "NTP_SERVERS=("
        printf '    "%s"\n' "${NTP_SERVERS[@]}"
        echo ")"
    } > "$CONFIG_FILE"
}

# 安装必要的包
install_packages() {
    log "检查并安装必要的软件包..."
    
    # 检查是否已安装htpdate
    if ! command -v htpdate &>/dev/null; then
        log "正在安装htpdate..."
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get update -y || error "更新软件包失败"
            DEBIAN_FRONTEND=noninteractive apt-get install -y htpdate || error "安装 htpdate 失败"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y htpdate || error "安装 htpdate 失败"
        else
            error "不支持的包管理器"
        fi
    else
        log "htpdate 已安装"
    fi
    
    # 检查其他必要命令
    check_command timedatectl
    check_command hwclock
}

# 同步时间
sync_time() {
    log "设置时区为 $TIMEZONE..."
    if ! timedatectl set-timezone "$TIMEZONE"; then
        error "时区设置失败"
    fi

    local sync_successful=false
    local sync_errors=()

    for server in "${NTP_SERVERS[@]}"; do
        log "尝试从 $server 同步时间..."
        if timeout 30 htpdate -s "$server" 2>/dev/null; then
            sync_successful=true
            log "成功从 $server 同步时间"
            break
        else
            local error_msg="从 $server 同步失败"
            log "$error_msg"
            sync_errors+=("$error_msg")
        fi
    done

    if ! $sync_successful; then
        error "所有服务器时间同步失败：${sync_errors[*]}"
    fi

    if ! hwclock -w; then
        error "硬件时钟更新失败"
    fi
    log "时间同步完成！当前时间: $(date)"
}

# 安装定时任务
install_cron() {
    log "设置每天凌晨4点运行的定时任务..."
    
    local cron_file="/etc/cron.d/timesync"
    printf "0 4 * * * root %s >> %s 2>&1\n" "$FULL_SCRIPT_PATH" "$LOG_FILE" > "$cron_file" || error "无法创建定时任务文件"
    chmod 644 "$cron_file" || error "无法设置定时任务文件权限"

    # 重启 cron 服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart cron.service || systemctl restart crond.service || error "无法重启 cron 服务"
    else
        service cron restart || service crond restart || error "无法重启 cron 服务"
    fi
    log "定时任务已安装"
}

# 清理函数
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "脚本执行失败，退出码: $exit_code"
    fi
    cleanup_logs
}

# 主函数
main() {
    trap cleanup EXIT
    
    check_root
    create_directories
    install_packages
    load_config
    sync_time
    install_cron
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
EOF

    chmod +x "$content_file"
    log "脚本内容已写入到: $content_file"
}

# 日志函数
log() {
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${GREEN}[${timestamp}] $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${RED}[${timestamp}] 错误: $1${NC}" >&2 | tee -a "$LOG_FILE"
    exit 1
}

# 清理旧日志
cleanup_logs() {
    if [[ -f "$LOG_FILE" ]]; then
        log "清理超过 ${LOG_DAYS} 天的旧日志..."
        local temp_file="${LOG_FILE}.tmp"
        touch -d "-${LOG_DAYS} days" "$temp_file"
        
        if [[ "$LOG_FILE" -ot "$temp_file" ]]; then
            log "删除旧日志文件"
            > "$LOG_FILE"  # 清空日志文件而不是删除它，以保持文件权限
        fi
        rm -f "$temp_file"
    fi
}

# 检查依赖命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1 || error "未找到命令: $1，请先安装"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error "此脚本需要root权限运行"
    fi
}

# 创建必要的目录
create_directories() {
    local dirs=("$(dirname "$LOG_FILE")" "$(dirname "$CONFIG_FILE")" "$SCRIPT_PATH")
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || mkdir -p "$dir" || error "无法创建目录: $dir"
    done
}

# 加载配置文件
load_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        # shellcheck source=/dev/null
        source "$CONFIG_FILE"
        log "加载配置文件: $CONFIG_FILE"
    else
        log "未找到配置文件，使用默认配置"
        TIMEZONE="$DEFAULT_TIMEZONE"
        NTP_SERVERS=("${DEFAULT_SERVERS[@]}")
        save_config
    fi
    # 记录脚本内容
    log_script_content "$TIMEZONE"
}

# 保存配置文件
save_config() {
    log "保存配置到 $CONFIG_FILE"
    {
        echo "TIMEZONE=\"$TIMEZONE\""
        echo "NTP_SERVERS=("
        printf '    "%s"\n' "${NTP_SERVERS[@]}"
        echo ")"
    } > "$CONFIG_FILE"
}

# 安装必要的包
install_packages() {
    log "检查并安装必要的软件包..."
    
    # 检查是否已安装htpdate
    if ! command -v htpdate &>/dev/null; then
        log "正在安装htpdate..."
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get update -y || error "更新软件包失败"
            DEBIAN_FRONTEND=noninteractive apt-get install -y htpdate || error "安装 htpdate 失败"
        elif command -v yum >/dev/null 2>&1; then
            yum install -y htpdate || error "安装 htpdate 失败"
        else
            error "不支持的包管理器"
        fi
    else
        log "htpdate 已安装"
    fi
    
    # 检查其他必要命令
    check_command timedatectl
    check_command hwclock
}

# 同步时间
sync_time() {
    log "设置时区为 $TIMEZONE..."
    if ! timedatectl set-timezone "$TIMEZONE"; then
        error "时区设置失败"
    fi

    local sync_successful=false
    local sync_errors=()

    for server in "${NTP_SERVERS[@]}"; do
        log "尝试从 $server 同步时间..."
        if timeout 30 htpdate -s "$server" 2>/dev/null; then
            sync_successful=true
            log "成功从 $server 同步时间"
            break
        else
            local error_msg="从 $server 同步失败"
            log "$error_msg"
            sync_errors+=("$error_msg")
        fi
    done

    if ! $sync_successful; then
        error "所有服务器时间同步失败：${sync_errors[*]}"
    fi

    if ! hwclock -w; then
        error "硬件时钟更新失败"
    fi
    log "时间同步完成！当前时间: $(date)"
}

# 安装定时任务
install_cron() {
    log "设置每天凌晨4点运行的定时任务..."
    
    local cron_file="/etc/cron.d/timesync"
    printf "0 4 * * * root %s >> %s 2>&1\n" "$FULL_SCRIPT_PATH" "$LOG_FILE" > "$cron_file" || error "无法创建定时任务文件"
    chmod 644 "$cron_file" || error "无法设置定时任务文件权限"

    # 重启 cron 服务
    if command -v systemctl >/dev/null 2>&1; then
        systemctl restart cron.service || systemctl restart crond.service || error "无法重启 cron 服务"
    else
        service cron restart || service crond restart || error "无法重启 cron 服务"
    fi
    log "定时任务已安装"
}

# 清理函数
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "脚本执行失败，退出码: $exit_code"
    fi
    cleanup_logs
}

# 主函数
main() {
    trap cleanup EXIT
    
    check_root
    create_directories
    install_packages
    load_config
    sync_time
    install_cron
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi