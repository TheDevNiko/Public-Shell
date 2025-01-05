#!/bin/bash

# Define colors for output
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Define the main paths
NEZHA_AGENT_PATH="/opt/nezha/agent"
NEZHA_BASE_PATH="/opt/nezha"

echo -e "${GREEN}> 卸载 Agent${NC}"

# Function to check if running as root/sudo
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 请使用 sudo 运行此脚本"
        exit 1
    fi
}

# Function to uninstall service and remove files
uninstall_agent() {
    # Kill any running nezha-agent processes
    killall nezha-agent 2>/dev/null
    echo "已终止所有 nezha-agent 进程"

    if [ -f "${NEZHA_AGENT_PATH}/nezha-agent" ]; then
        ${NEZHA_AGENT_PATH}/nezha-agent service uninstall
        echo "已停止并卸载 Nezha Agent 服务"
    fi

    # Remove directories
    rm -rf "${NEZHA_AGENT_PATH}" 2>/dev/null
    rm -rf "${NEZHA_BASE_PATH}" 2>/dev/null
    
    echo "已完成清理"
}

# Main execution
check_root
uninstall_agent

echo -e "${GREEN}> Nezha Agent 卸载完成${NC}"