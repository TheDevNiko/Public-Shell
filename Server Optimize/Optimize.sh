#!/usr/bin/env bash

# 启用严格模式
set -euo pipefail

# 定义日志文件
LOG_FILE="/var/log/server-optimization.log"
BACKUP_DIR="/root/system_backup"

# 定义全局变量
declare release=""
declare -i cpu_cores=0
declare -i cpu_threads=0
declare server_country=""
declare server_region=""
declare is_in_china=""

# 定义颜色输出
CSI="\033["
CEND="${CSI}0m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CCYAN="${CSI}1;36m"

# 输出函数
OUT_ALERT() { echo -e "${CYELLOW}$1${CEND}" | tee -a "${LOG_FILE}"; }
OUT_ERROR() { echo -e "${CRED}$1${CEND}" | tee -a "${LOG_FILE}"; }
OUT_INFO() { echo -e "${CCYAN}$1${CEND}" | tee -a "${LOG_FILE}"; }
OUT_SUCCESS() { echo -e "${CGREEN}$1${CEND}" | tee -a "${LOG_FILE}"; }

# 创建备份目录
init_backup() {
    if ! mkdir -p "${BACKUP_DIR}"; then
        OUT_ERROR "[错误] 无法创建备份目录"
        return 1
    fi
    return 0
}

# 检查root权限
check_root() { 
    if [ $EUID -ne 0 ]; then
        OUT_ERROR "[错误] 此脚本需要root权限运行"
        return 1
    fi
}

# 检查服务器位置
check_location() { 
    OUT_INFO "[信息] 正在检查服务器位置..."
    
    if ! location_info=$(curl -s "https://ipinfo.io"); then
        OUT_ERROR "[错误] 无法获取位置信息，默认使用国际配置"
        server_country="UNKNOWN"
        server_region="UNKNOWN"
        is_in_china="false"
        return 1
    fi
    
    # 解析位置信息
    server_country=$(echo "${location_info}" | grep -o '"country": "[^"]*' | cut -d'"' -f4)
    server_region=$(echo "${location_info}" | grep -o '"region": "[^"]*' | cut -d'"' -f4)
    
    if [ "${server_country}" = "CN" ]; then
        OUT_INFO "[信息] 检测到服务器位于中国 ${server_region}"
        is_in_china="true"
    else
        OUT_INFO "[信息] 检测到服务器位于海外：${server_country} ${server_region}"
        is_in_china="false"
    fi
}

# 检测系统类型
check_system() { 
    # 首先检查是否存在 /etc/os-release 文件
    if [ -f /etc/os-release ]; then
        source /etc/os-release
        if echo "${ID}" | grep -qi "debian"; then
            release="debian"
            return 0
        elif echo "${ID}" | grep -qi "ubuntu"; then
            release="ubuntu"
            return 0
        elif echo "${ID}" | grep -qi "centos|rhel|fedora"; then
            release="centos"
            return 0
        fi
    fi

    # 如果无法从 os-release 确定，使用传统方法
    if [ -f /etc/redhat-release ]; then
        release="centos"
        return 0
    fi
    
    if [ -f /etc/debian_version ]; then
        release="debian"
        return 0
    fi
    
    if grep -qi "debian" /etc/issue; then
        release="debian"
        return 0
    fi
    
    if grep -qi "ubuntu" /etc/issue; then
        release="ubuntu"
        return 0
    fi
    
    if grep -qi "centos|red hat|redhat" /etc/issue; then
        release="centos"
        return 0
    fi
    
    OUT_ERROR "[错误] 不支持的操作系统！"
    OUT_INFO "系统信息："
    if [ -f /etc/os-release ]; then
        cat /etc/os-release
    fi
    return 1
}

# 检测CPU配置
detect_cpu() {
    OUT_INFO "[信息] 检测CPU配置..."
    
    if [ ! -f /proc/cpuinfo ]; then
        OUT_ERROR "[错误] 无法访问 /proc/cpuinfo"
        return 1
    fi
    
    # 获取物理核心数（cpu cores）
    cpu_cores=$(grep "cpu cores" /proc/cpuinfo | uniq | awk '{print $4}')
    if [ -z "$cpu_cores" ]; then
        OUT_ERROR "[错误] 无法获取CPU核心数"
        return 1
    fi
    
    # 获取线程数（siblings）
    cpu_threads=$(grep "siblings" /proc/cpuinfo | uniq | awk '{print $3}')
    if [ -z "$cpu_threads" ]; then
        # 如果无法获取线程数，则回退到处理器数量
        cpu_threads=$(grep -c processor /proc/cpuinfo)
    fi
    
    # 获取CPU型号
    local cpu_model
    cpu_model=$(grep "model name" /proc/cpuinfo | head -n1 | cut -d':' -f2 | tr -s ' ')
    
    OUT_INFO "[信息] CPU型号: ${cpu_model}"
    OUT_INFO "[信息] CPU物理核心数: ${cpu_cores}"
    OUT_INFO "[信息] CPU逻辑核心数: ${cpu_threads}"
}

# 安装必要工具
install_requirements() { 
    OUT_INFO "[信息] 安装必要工具..."
    
    if [ "${release}" = "centos" ]; then
        if ! yum install -y epel-release; then
            OUT_ERROR "[错误] 安装 epel-release 失败"
            return 1
        fi
        
        if ! yum install -y wget curl chrony; then
            OUT_ERROR "[错误] 安装必要工具失败"
            return 1
        fi
    else
        if ! apt-get update; then
            OUT_ERROR "[错误] 更新软件源失败"
            return 1
        fi
        
        if ! apt-get install -y wget curl chrony; then
            OUT_ERROR "[错误] 安装必要工具失败"
            return 1
        fi
    fi
    
    OUT_SUCCESS "[成功] 工具安装完成"
    return 0
}

# 配置DNS
configure_dns() { 
    OUT_INFO "配置系统DNS..."

    # 确保备份目录存在
    if [ ! -d "${BACKUP_DIR}" ]; then
        if ! mkdir -p "${BACKUP_DIR}"; then
            OUT_ERROR "无法创建备份目录：${BACKUP_DIR}"
            return 1
        fi
    fi

    # 检查并移除符号链接或不可修改属性
    if [ -L /etc/resolv.conf ]; then
        if ! rm -f /etc/resolv.conf; then
            OUT_ERROR "无法删除 resolv.conf 符号链接"
            return 1
        fi
    fi
    
    if [ -f /etc/resolv.conf ]; then
        chattr -i /etc/resolv.conf 2>/dev/null || true
        if ! mv /etc/resolv.conf "${BACKUP_DIR}/resolv.conf.bak"; then
            OUT_ERROR "无法备份 /etc/resolv.conf 文件"
            return 1
        fi
    fi

    # 写入新的 DNS 配置
    if [ "${is_in_china}" = "true" ]; then
        # 国内DNS配置
        if ! cat > /etc/resolv.conf << 'EOF'
options timeout:2 attempts:3 rotate
nameserver 223.5.5.5
nameserver 223.6.6.6
nameserver 119.29.29.29
nameserver 180.76.76.76
EOF
        then
            OUT_ERROR "无法写入DNS配置"
            return 1
        fi
        OUT_INFO "已配置国内DNS"
    else
        # 国外DNS配置
        if ! cat > /etc/resolv.conf << 'EOF'
options timeout:2 attempts:3 rotate
nameserver 1.1.1.1
nameserver 8.8.8.8
nameserver 9.9.9.9
nameserver 208.67.222.222
EOF
        then
            OUT_ERROR "无法写入DNS配置"
            return 1
        fi
        OUT_INFO "已配置国际DNS"
    fi

    # 设置文件为不可修改
    if ! chattr +i /etc/resolv.conf; then
        OUT_ERROR "无法设置 /etc/resolv.conf 为只读"
        return 1
    fi

    OUT_SUCCESS "DNS配置完成"
    return 0
}

# 配置NTP
configure_ntp() { 
    OUT_INFO "配置NTP时间同步..."

    # 使用真实服务名称 chrony.service
    NTP_SERVICE="chrony.service"

    # 备份原始配置
    if [ -f /etc/chrony.conf ] && \
       ! cp -f /etc/chrony.conf "${BACKUP_DIR}/chrony.conf.bak"; then
        OUT_ERROR "无法备份 chrony.conf"
        return 1
    fi

    if [ "${is_in_china}" = "true" ]; then
        # 国内NTP配置
        if ! cat > /etc/chrony.conf << 'EOF'
server ntp.aliyun.com iburst
server cn.ntp.org.cn iburst
server ntp.tencent.com iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
        then
            OUT_ERROR "无法写入 chrony 配置文件"
            return 1
        fi
        OUT_INFO "已配置国内NTP服务器"
    else
        # 国外NTP配置
        if ! cat > /etc/chrony.conf << 'EOF'
pool pool.ntp.org iburst
pool time.google.com iburst
pool time.cloudflare.com iburst
driftfile /var/lib/chrony/drift
makestep 1.0 3
rtcsync
logdir /var/log/chrony
EOF
        then
            OUT_ERROR "无法写入 chrony 配置文件"
            return 1
        fi
        OUT_INFO "已配置国际NTP服务器"
    fi

    # 设置适当的权限
    chown -R root:root /etc/chrony.conf
    chmod 644 /etc/chrony.conf

    # 启用并重启服务
    if ! systemctl enable "${NTP_SERVICE}"; then
        OUT_ERROR "无法启用 NTP 服务：${NTP_SERVICE}"
        return 1
    fi
    
    if ! systemctl restart "${NTP_SERVICE}"; then
        OUT_ERROR "无法重启 NTP 服务：${NTP_SERVICE}"
        return 1
    fi

    OUT_SUCCESS "NTP配置完成"
    return 0
}

# 配置rc.local服务
configure_rc_local() {
    OUT_INFO "[信息] 配置rc.local服务..."
    
    # 对于systemd系统，需要创建rc-local.service
    if [ ! -f /etc/systemd/system/rc-local.service ]; then
        if ! cat > /etc/systemd/system/rc-local.service << 'EOF'
[Unit]
Description=/etc/rc.local Compatibility
ConditionPathExists=/etc/rc.local

[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99

[Install]
WantedBy=multi-user.target
EOF
        then
            OUT_ERROR "[错误] 无法创建rc-local.service"
            return 1
        fi
    fi
    
    # 创建/etc/rc.local文件
    if [ ! -f /etc/rc.local ]; then
        if ! cat > /etc/rc.local << 'EOF'
#!/bin/bash
# rc.local

# 应用sysctl参数
sysctl -p

exit 0
EOF
        then
            OUT_ERROR "[错误] 无法创建rc.local"
            return 1
        fi
    fi
    
    # 设置执行权限
    chmod +x /etc/rc.local
    
    # 启用rc-local服务
    systemctl daemon-reload
    systemctl enable rc-local
    systemctl start rc-local
    
    OUT_SUCCESS "[成功] rc.local服务配置完成"
    return 0
}

# 生成网络优化参数
generate_optimization_params() {
    local params="# 网络优化参数
net.ipv4.tcp_rmem = 4096 524288 42205184
net.ipv4.tcp_wmem = 4096 524288 42205184
net.core.rmem_max = 42205184
net.core.wmem_max = 42205184
net.core.netdev_max_backlog = 20000
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_moderate_rcvbuf = 1
net.core.default_qdisc = fq"
    
    echo "${params}"
    return 0
}

# 系统参数优化
optimize_system() { 
    OUT_INFO "[信息] 优化系统参数..."
    
    # 检测CPU配置
    if ! detect_cpu; then
        OUT_ERROR "[错误] CPU检测失败"
        return 1
    fi
    
    # 备份原始配置
    if [ -f /etc/sysctl.conf ] && \
       ! cp -f /etc/sysctl.conf "${BACKUP_DIR}/sysctl.conf.bak"; then
        OUT_ERROR "[错误] 无法备份sysctl.conf"
        return 1
    fi
    
    # 获取纯净的优化参数
    local optimization_params
    optimization_params=$(generate_optimization_params)
    
    # 配置sysctl参数
    if ! cat > /etc/sysctl.conf << EOF
# 基础网络参数
net.ipv4.ip_forward = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 30
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_max_tw_buckets = 550000
net.ipv4.tcp_max_syn_backlog = 30000
net.ipv4.tcp_mtu_probing = 1
net.ipv4.tcp_fastopen = 0

${optimization_params}

# 路由设置
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0

# 文件描述符限制
fs.file-max = 2097152
fs.nr_open = 2097152
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
fs.pipe-max-size = 1048576

# 内存参数
vm.swappiness = 10
vm.min_free_kbytes = 65536
vm.overcommit_memory = 1
vm.max_map_count = 262144
EOF
    then
        OUT_ERROR "[错误] 无法写入sysctl配置"
        return 1
    fi

    # 备份并配置系统限制
    if [ -f /etc/security/limits.conf ] && \
       ! cp -f /etc/security/limits.conf "${BACKUP_DIR}/limits.conf.bak"; then
        OUT_ERROR "[错误] 无法备份limits.conf"
        return 1
    fi
    
    if ! cat > /etc/security/limits.conf << 'EOF'
* soft nofile 2097152
* hard nofile 2097152
* soft nproc 2097152
* hard nproc 2097152
root soft nofile 2097152
root hard nofile 2097152
root soft nproc 2097152
root hard nproc 2097152
* soft memlock unlimited
* hard memlock unlimited
EOF
    then
        OUT_ERROR "[错误] 无法写入limits配置"
        return 1
    fi
    
    # 确保PAM加载limits配置
    if [ -f /etc/pam.d/common-session ]; then
        if ! grep -q '^session.*pam_limits.so$' /etc/pam.d/common-session; then
            if ! echo "session required pam_limits.so" >> /etc/pam.d/common-session; then
                OUT_ERROR "[错误] 无法配置PAM加载limits"
                return 1
            fi
        fi
    fi
    
    # 应用sysctl参数
    if ! sysctl -p; then
        OUT_ERROR "[错误] 应用sysctl参数失败"
        return 1
    fi
    
    OUT_SUCCESS "[成功] 系统参数优化完成"
    return 0
}

# 主函数
main() { 
    OUT_INFO "[信息] 开始系统优化..."
    
    # 创建备份目录
    init_backup
    
    # 基础检查（这些检查建议保留）
    check_root
    check_system
    check_location
    
    # 可选功能（可以注释掉不需要的部分）
    install_requirements
    configure_dns
    configure_ntp
    optimize_system
    configure_rc_local
    
    OUT_SUCCESS "[成功] 系统优化完成！"
    OUT_INFO "[信息] 建议重启系统使所有优化生效"
}

# 执行主函数
main