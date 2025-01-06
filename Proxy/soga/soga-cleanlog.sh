#!/usr/bin/env bash

# 启用严格模式
set -euo pipefail

# 定义颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 日志函数
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] 错误: $1${NC}" >&2
    exit 1
}

warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] 警告: $1${NC}"
}

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    error "此脚本需要root权限运行"
fi

# 脚本路径和名称定义
SCRIPT_PATH="/home/cleanlog"
SCRIPT_NAME="cleanlog.sh"
FULL_SCRIPT_PATH="${SCRIPT_PATH}/${SCRIPT_NAME}"
LOG_FILE="${SCRIPT_PATH}/clean.log"

# 创建脚本目录
create_script_directory() {
    if [[ ! -d "$SCRIPT_PATH" ]]; then
        log "创建脚本目录..."
        mkdir -p "$SCRIPT_PATH" || error "创建目录失败: $SCRIPT_PATH"
    fi
}

# 清理日志的主函数
clean_logs() {
    local log_path="/etc/soga/access_log"
    local current_date
    current_date="$(date +'%Y_%m_%d')"
    local current_file="access_log_${current_date}.csv"
    
    if [[ ! -d "$log_path" ]]; then
        warning "日志目录不存在: $log_path"
        return 0
    fi
    
    log "开始清理过期日志..."
    
    # 计数器
    local deleted_count=0
    local failed_count=0
    
    # 查找并删除旧日志
    while IFS= read -r file; do
        if [[ -f "$file" ]]; then
            if rm -f "$file"; then
                ((deleted_count++))
            else
                ((failed_count++))
                warning "删除失败: $file"
            fi
        fi
    done < <(find "$log_path" -type f -name "*.csv" ! -name "$current_file")
    
    # 记录结果
    log "清理完成: 成功删除 $deleted_count 个文件，失败 $failed_count 个"
    echo "$(date +'%Y-%m-%d %H:%M:%S') - 已清理 $deleted_count 个文件，失败 $failed_count 个" >> "$LOG_FILE"
}

# 安装定时任务
install_cron() {
    log "配置定时任务..."
    
    # 确保脚本可执行
    chmod +x "$FULL_SCRIPT_PATH"
    
    # 创建新的定时任务
    local cron_job="0 6 * * * root $FULL_SCRIPT_PATH >> $LOG_FILE 2>&1"
    
    # 检查是否已存在相同的定时任务
    if ! crontab -l 2>/dev/null | grep -Fq "$FULL_SCRIPT_PATH"; then
        # 添加到系统定时任务
        echo "$cron_job" > "/etc/cron.d/log-cleaner"
        chmod 644 "/etc/cron.d/log-cleaner"
        
        # 重启 crond 服务
        if command -v systemctl >/dev/null 2>&1; then
            systemctl restart crond.service || systemctl restart cron.service
        else
            service cron restart || service crond restart
        fi
        
        log "定时任务已添加: 每天早上 6:00 执行"
    else
        warning "定时任务已存在，跳过添加"
    fi
}

# 设置日志轮转
setup_logrotate() {
    log "配置日志轮转..."
    
    cat > "/etc/logrotate.d/log-cleaner" << EOF
$LOG_FILE {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 644 root root
}
EOF
}

# 主函数
main() {
    log "开始安装日志清理服务..."
    
    # 创建必要的目录
    create_script_directory
    
    # 将当前脚本复制到指定位置
    cp -f "$0" "$FULL_SCRIPT_PATH"
    chmod +x "$FULL_SCRIPT_PATH"
    
    # 配置定时任务
    install_cron
    
    # 设置日志轮转
    setup_logrotate
    
    # 立即执行一次清理
    clean_logs
    
    log "安装完成！"
    echo -e "\n${GREEN}状态信息：${NC}"
    echo "1. 脚本位置: $FULL_SCRIPT_PATH"
    echo "2. 日志文件: $LOG_FILE"
    echo "3. 定时执行: 每天早上 6:00"
    echo "4. 日志轮转: 每周轮转，保留4周"
}

# 根据参数决定运行模式
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [[ "${1:-}" == "clean" ]]; then
        # 直接执行清理
        clean_logs
    else
        # 完整安装
        main
    fi
fi