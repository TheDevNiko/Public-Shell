#!/bin/bash

# 备份原始源文件
backup_sources() {
    echo "备份原始源文件..."
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
    echo "原始源文件已备份为 /etc/apt/sources.list.bak"
}

# 检测系统版本和发行版
detect_system() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$NAME
        VERSION=$VERSION_ID
        echo "检测到系统: $OS $VERSION"
        return 0
    else
        echo "无法检测系统版本"
        exit 1
    fi
}

# 更新Ubuntu源
update_ubuntu_sources() {
    local version=$1
    echo "更新 Ubuntu $version 的软件源..."
    
    case $version in
        "20.04")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/ubuntu/ focal main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ focal-backports main restricted universe multiverse
EOF
            ;;
        "22.04")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/ubuntu/ jammy main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ jammy-backports main restricted universe multiverse
EOF
            ;;
        "24.04")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/ubuntu/ noble main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-security main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-updates main restricted universe multiverse
deb http://mirrors.aliyun.com/ubuntu/ noble-backports main restricted universe multiverse
EOF
            ;;
        *)
            echo "不支持的 Ubuntu 版本: $version"
            exit 1
            ;;
    esac
}

# 更新Debian源
update_debian_sources() {
    local version=$1
    echo "更新 Debian $version 的软件源..."
    
    case $version in
        "10")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/debian/ buster main non-free contrib
deb http://mirrors.aliyun.com/debian/ buster-updates main non-free contrib
deb http://mirrors.aliyun.com/debian/ buster-backports main non-free contrib
deb http://mirrors.aliyun.com/debian-security buster/updates main non-free contrib
EOF
            ;;
        "11")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/debian/ bullseye main non-free contrib
deb http://mirrors.aliyun.com/debian/ bullseye-updates main non-free contrib
deb http://mirrors.aliyun.com/debian/ bullseye-backports main non-free contrib
deb http://mirrors.aliyun.com/debian-security bullseye-security main non-free contrib
EOF
            ;;
        "12")
            cat << EOF | sudo tee /etc/apt/sources.list
deb http://mirrors.aliyun.com/debian/ bookworm main non-free-firmware contrib
deb http://mirrors.aliyun.com/debian/ bookworm-updates main non-free-firmware contrib
deb http://mirrors.aliyun.com/debian/ bookworm-backports main non-free-firmware contrib
deb http://mirrors.aliyun.com/debian-security bookworm-security main non-free-firmware contrib
EOF
            ;;
        *)
            echo "不支持的 Debian 版本: $version"
            exit 1
            ;;
    esac
}

# 主函数
main() {
    # 检查是否以root权限运行
    if [ "$EUID" -ne 0 ]; then 
        echo "请使用 sudo 运行此脚本"
        exit 1
    fi

    # 检测系统版本
    detect_system

    # 备份源文件
    backup_sources

    # 根据不同的发行版更新源
    case $OS in
        "Ubuntu")
            update_ubuntu_sources $VERSION
            ;;
        "Debian GNU/Linux"|"Debian")
            update_debian_sources $VERSION
            ;;
        *)
            echo "不支持的操作系统: $OS"
            exit 1
            ;;
    esac

    # 更新软件包列表
    echo "更新软件包列表..."
    sudo apt update

    echo "镜像源已成功更换为阿里云源"
}

# 运行主函数
main