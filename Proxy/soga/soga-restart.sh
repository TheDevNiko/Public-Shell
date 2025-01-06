#!/bin/bash
# 配置参数
INSTALL_PATH="/usr/local/bin/memory_monitor.sh"
THRESHOLD=1024
COMMAND="soga restart"
LOG_FILE="/var/log/soga_memory_monitor.log"
LOCK_FILE="/var/run/soga_monitor.lock"
RESTART_COOLDOWN=600
LOG_DAYS=7

# 彩色输出函数
print_success() {
    echo -e "\033[32m[成功]\033[0m $1"
}

print_info() {
    echo -e "\033[34m[信息]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[错误]\033[0m $1"
}

# root权限检查
if [ "$(id -u)" != "0" ]; then
   print_error "此脚本需要root权限"
   exit 1
fi

# 安装脚本到系统
install_script() {
    print_info "正在安装脚本到系统..."
    cat > "$INSTALL_PATH" << 'EEOF'
#!/bin/bash
# 配置参数
THRESHOLD=1024
COMMAND="soga restart"
LOG_FILE="/var/log/soga_memory_monitor.log"
LOCK_FILE="/var/run/soga_monitor.lock"
RESTART_COOLDOWN=600
LOG_DAYS=7

# 彩色输出函数
print_success() {
    echo -e "\033[32m[成功]\033[0m $1"
}

print_info() {
    echo -e "\033[34m[信息]\033[0m $1"
}

print_error() {
    echo -e "\033[31m[错误]\033[0m $1"
}

# 创建日志目录
mkdir -p "$(dirname "$LOG_FILE")"

# 记录日志
log_message() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1" >> "$LOG_FILE"
}

# 获取当前空余内存（单位：MB）
FREE_MEMORY=$(free -m | awk '/^Mem:/{print $7}')
print_info "当前空余内存: ${FREE_MEMORY}MB"

# 检查上次重启时间
if [ -f "/tmp/last_restart" ]; then
    last_restart=$(cat "/tmp/last_restart")
    now=$(date +%s)
    if [ $((now - last_restart)) -lt "$RESTART_COOLDOWN" ]; then
        print_info "距离上次重启时间不足 ${RESTART_COOLDOWN} 秒，跳过本次检查"
        log_message "距离上次重启时间不足 ${RESTART_COOLDOWN} 秒，跳过本次检查"
        exit 0
    fi
fi

# 检查内存是否低于阈值
if [ "$FREE_MEMORY" -lt "$THRESHOLD" ]; then
    print_error "内存不足: 当前空余内存 ${FREE_MEMORY}MB，小于阈值 ${THRESHOLD}MB"
    log_message "内存不足: 当前空余内存 ${FREE_MEMORY}MB，小于阈值 ${THRESHOLD}MB"
    
    print_info "正在重启服务：soga..."
    log_message "正在重启服务：soga..."
    if $COMMAND; then
        print_success "服务 soga 已成功重启"
        log_message "服务 soga 已成功重启"
        date +%s > "/tmp/last_restart"
    else
        print_error "服务 soga 重启失败，请检查系统状态！"
        log_message "服务 soga 重启失败，请检查系统状态！"
    fi
else
    print_success "内存正常: 当前空余内存 ${FREE_MEMORY}MB，大于阈值 ${THRESHOLD}MB"
    log_message "内存正常: 当前空余内存 ${FREE_MEMORY}MB，大于阈值 ${THRESHOLD}MB"
fi

print_success "检查完成！日志已保存到: $LOG_FILE"
EEOF

    chmod +x "$INSTALL_PATH"
    print_success "脚本已安装到: $INSTALL_PATH"
}

# 设置crontab
setup_crontab() {
    print_info "正在设置定时任务..."
    CRON_CMD="*/10 * * * * $INSTALL_PATH"
    (crontab -l 2>/dev/null | grep -v "$INSTALL_PATH"; echo "$CRON_CMD") | crontab -
    print_success "已添加到crontab，每10分钟运行一次"
}

# 主要安装流程
main() {
    install_script
    setup_crontab
    print_info "开始执行第一次检查..."
    bash "$INSTALL_PATH"
}

# 执行主函数
main