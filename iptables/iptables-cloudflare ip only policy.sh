#!/bin/bash

# 设置严格模式
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# 检查root权限
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}此脚本必须以root权限运行${NC}"
    exit 1
fi

# 检查系统类型
check_system() {
    if [ -f /etc/debian_version ]; then
        if [ -f /etc/lsb-release ]; then
            echo -e "${GREEN}检测到 Ubuntu 系统${NC}"
            SYSTEM="ubuntu"
        else
            echo -e "${GREEN}检测到 Debian 系统${NC}"
            SYSTEM="debian"
        fi
    elif [ -f /etc/redhat-release ]; then
        echo -e "${GREEN}检测到 RHEL/CentOS 系统${NC}"
        SYSTEM="rhel"
    elif [ -f /etc/arch-release ]; then
        echo -e "${GREEN}检测到 Arch Linux 系统${NC}"
        SYSTEM="arch"
    elif [ -f /etc/fedora-release ]; then
        echo -e "${GREEN}检测到 Fedora 系统${NC}"
        SYSTEM="fedora"
    else
        echo -e "${YELLOW}未能精确识别系统类型，将使用通用配置${NC}"
        SYSTEM="generic"
    fi
}

# 检查并安装必要工具
check_requirements() {
    local missing_tools=()
    
    # 检查基本工具
    for tool in curl iptables ip6tables; do
        if ! command -v $tool >/dev/null 2>&1; then
            missing_tools+=($tool)
        fi
    done

    # Ubuntu 系统切换到 iptables-legacy
    if [ "$SYSTEM" = "ubuntu" ]; then
        # 获取 Ubuntu 版本号
        ubuntu_version=$(awk -F'[".]' '/VERSION_ID=/ {print $2}' /etc/os-release)
        if [ -n "$ubuntu_version" ] && [ "$ubuntu_version" -ge 20 ]; then
            echo -e "${YELLOW}检测到 Ubuntu 20.04 或更高版本，正在切换到 iptables-legacy...${NC}"
            update-alternatives --set iptables /usr/sbin/iptables-legacy >/dev/null 2>&1 || true
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy >/dev/null 2>&1 || true
        fi
    fi
    
    # 根据不同系统逐个安装缺失工具
    for tool in "${missing_tools[@]}"; do
        case $SYSTEM in
            "debian"|"ubuntu")
                apt-get update >/dev/null 2>&1
                apt-get install -y $tool || echo -e "${RED}Failed to install $tool${NC}"
                ;;
            "rhel"|"fedora")
                yum -y install $tool || echo -e "${RED}Failed to install $tool${NC}"
                ;;
            "arch")
                pacman -Sy --noconfirm $tool || echo -e "${RED}Failed to install $tool${NC}"
                ;;
        esac
    done
    
    # 安装持久化包
    case $SYSTEM in
        "debian"|"ubuntu")
            if ! dpkg -l | grep -q "iptables-persistent"; then
                echo -e "${YELLOW}正在安装 iptables-persistent...${NC}"
                DEBIAN_FRONTEND=noninteractive apt-get install -y iptables-persistent
            fi
            ;;
        "rhel"|"fedora")
            if ! rpm -q iptables-services >/dev/null 2>&1; then
                echo -e "${YELLOW}正在安装 iptables-services...${NC}"
                yum -y install iptables-services
                systemctl enable iptables ip6tables
            fi
            ;;
        "arch")
            if ! pacman -Qs iptables >/dev/null 2>&1; then
                echo -e "${YELLOW}正在安装 iptables...${NC}"
                pacman -Sy --noconfirm iptables
            fi
            ;;
    esac
}

# 下载Cloudflare IP列表
download_cf_ips() {
    local type=$1
    local tmp_file=""
    local url=""
    local max_retries=3
    local retry_count=0
    
    if [ "$type" = "v4" ]; then
        tmp_file="/tmp/cf_ipv4.txt"
        url="https://www.cloudflare.com/ips-v4"
        echo -e "${YELLOW}正在下载 Cloudflare IPv4 列表...${NC}"
    else
        tmp_file="/tmp/cf_ipv6.txt"
        url="https://www.cloudflare.com/ips-v6"
        echo -e "${YELLOW}正在下载 Cloudflare IPv6 列表...${NC}"
    fi
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s --retry 3 --retry-delay 5 --connect-timeout 10 --max-time 30 "$url" -o "$tmp_file"; then
            if [ -s "$tmp_file" ]; then
                echo -e "${GREEN}下载成功${NC}"
                return 0
            fi
        fi
        
        retry_count=$((retry_count + 1))
        echo -e "${YELLOW}下载失败，尝试重试 ($retry_count/$max_retries)...${NC}"
        sleep 5
    done
    
    echo -e "${RED}下载失败，请检查网络连接${NC}"
    exit 1
}

# 配置防火墙规则
configure_firewall() {
    echo -e "${YELLOW}正在配置防火墙规则...${NC}"
    
    # 备份当前规则
    mkdir -p /etc/iptables/backup
    iptables-save > /etc/iptables/backup/rules.v4.$(date +%Y%m%d_%H%M%S)
    ip6tables-save > /etc/iptables/backup/rules.v6.$(date +%Y%m%d_%H%M%S)

    echo -e "${YELLOW}配置 IPv4 规则...${NC}"

    # 删除已存在的相关规则
    while iptables -D INPUT -p tcp -m multiport --dports 80,443 -j DROP 2>/dev/null; do :; done
    while IFS= read -r ip; do
        if [ -n "$ip" ]; then
            iptables -D INPUT -s "$ip" -p tcp -m multiport --dports 80,443 -j ACCEPT 2>/dev/null || true
        fi
    done < /tmp/cf_ipv4.txt
    
    # 添加新规则
    while IFS= read -r ip; do
        if [ -n "$ip" ]; then
            iptables -I INPUT -s "$ip" -p tcp -m multiport --dports 80,443 -j ACCEPT
        fi
    done < /tmp/cf_ipv4.txt
    
    # 添加 DROP 规则
    iptables -A INPUT -p tcp -m multiport --dports 80,443 -j DROP

    # IPv6 配置
    if [ -f /proc/net/if_inet6 ]; then
        echo -e "${YELLOW}配置 IPv6 规则...${NC}"
        
        # 删除已存在的相关规则
        while ip6tables -D INPUT -p tcp -m multiport --dports 80,443 -j DROP 2>/dev/null; do :; done
        while IFS= read -r ip; do
            if [ -n "$ip" ]; then
                ip6tables -D INPUT -s "$ip" -p tcp -m multiport --dports 80,443 -j ACCEPT 2>/dev/null || true
            fi
        done < /tmp/cf_ipv6.txt
        
        # 添加新规则
        while IFS= read -r ip; do
            if [ -n "$ip" ]; then
                ip6tables -I INPUT -s "$ip" -p tcp -m multiport --dports 80,443 -j ACCEPT
            fi
        done < /tmp/cf_ipv6.txt
        
        # 添加 DROP 规则
        ip6tables -A INPUT -p tcp -m multiport --dports 80,443 -j DROP
    fi
}

# 确保规则持久化
ensure_persistence() {
    echo -e "${YELLOW}正在确保规则持久化...${NC}"
    
    case $SYSTEM in
        "debian"|"ubuntu")
            mkdir -p /etc/iptables
            # 保存当前规则
            iptables-save > /etc/iptables/rules.v4
            [ -f /proc/net/if_inet6 ] && ip6tables-save > /etc/iptables/rules.v6
            
            # 只启用服务，不重启
            systemctl enable netfilter-persistent --quiet
            ;;
            
        "rhel"|"fedora")
            service iptables save
            [ -f /proc/net/if_inet6 ] && service ip6tables save
            systemctl enable iptables --quiet
            [ -f /proc/net/if_inet6 ] && systemctl enable ip6tables --quiet
            ;;
            
        *)
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            [ -f /proc/net/if_inet6 ] && ip6tables-save > /etc/iptables/rules.v6
            
            if [ -d /etc/systemd/system ]; then
                cat > /etc/systemd/system/iptables-restore.service << 'EOF'
[Unit]
Description=Restore iptables firewall rules
Before=network-pre.target
Wants=network-pre.target
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
ExecStart=/sbin/ip6tables-restore /etc/iptables/rules.v6
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable iptables-restore --quiet
            else
                mkdir -p /etc/network/if-pre-up.d/
                cat > /etc/network/if-pre-up.d/iptables << 'EOF'
#!/bin/sh
if [ -f /etc/iptables/rules.v4 ]; then
    /sbin/iptables-restore < /etc/iptables/rules.v4
fi
if [ -f /etc/iptables/rules.v6 ]; then
    /sbin/ip6tables-restore < /etc/iptables/rules.v6
fi
EOF
                chmod +x /etc/network/if-pre-up.d/iptables
            fi
            ;;
    esac
}

# 验证规则
verify_rules() {
    echo -e "${YELLOW}验证防火墙规则配置...${NC}"
    
    # 检查服务状态
    case $SYSTEM in
        "debian"|"ubuntu")
            if systemctl is-active netfilter-persistent >/dev/null 2>&1; then
                echo -e "${GREEN}netfilter-persistent 服务运行中${NC}"
            else
                echo -e "${RED}netfilter-persistent 服务未运行${NC}"
                return 1
            fi
            ;;
        "rhel"|"fedora")
            if systemctl is-active iptables >/dev/null 2>&1; then
                echo -e "${GREEN}iptables 服务运行中${NC}"
            else
                echo -e "${RED}iptables 服务未运行${NC}"
                return 1
            fi
            ;;
    esac
    
    # 检查 IPv4 规则
    echo -e "\n${GREEN}当前 IPv4 Web 端口规则：${NC}"
    iptables -L INPUT -n -v | grep -E "tcp.*dports 80,443"
    
    # 检查 IPv6 规则（如果启用了IPv6）
    if [ -f /proc/net/if_inet6 ]; then
        echo -e "\n${GREEN}当前 IPv6 Web 端口规则：${NC}"
        ip6tables -L INPUT -n -v | grep -E "tcp.*dports 80,443"
    fi
}

# 清理临时文件
cleanup() {
    rm -f /tmp/cf_ipv4.txt /tmp/cf_ipv6.txt
}

# 主函数
main() {
    echo -e "${GREEN}开始配置 Cloudflare IP 防护...${NC}"
    
    check_system
    check_requirements
    download_cf_ips "v4"
    [ -f /proc/net/if_inet6 ] && download_cf_ips "v6"
    configure_firewall
    ensure_persistence
    verify_rules
    cleanup
    
    echo -e "\n${GREEN}Cloudflare IP 防护配置完成！${NC}"
    echo -e "${YELLOW}规则备份保存在 /etc/iptables/backup/ 目录下${NC}"
    echo -e "${GREEN}请检查以上输出确认规则配置正确${NC}"
    echo -e "${GREEN}完成配置后建议重启系统以确保规则正确加载${NC}"
}

main

exit 0