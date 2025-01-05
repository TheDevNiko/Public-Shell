#!/usr/bin/env bash
echo=echo
for cmd in echo /bin/echo; do
    $cmd > /dev/null 2>&1 || continue

    if ! $cmd -e "" | grep -qE '^-e'; then
        echo=$cmd
        break
    fi
done

CSI=$($echo -e "\033[")
CEND="${CSI}0m"
CDGREEN="${CSI}32m"
CRED="${CSI}1;31m"
CGREEN="${CSI}1;32m"
CYELLOW="${CSI}1;33m"
CBLUE="${CSI}1;34m"
CMAGENTA="${CSI}1;35m"
CCYAN="${CSI}1;36m"
CSUCCESS="$CDGREEN"
CFAILURE="$CRED"
CQUESTION="$CMAGENTA"
CWARNING="$CYELLOW"
CMSG="$CCYAN"

VERSION="1.0.0"

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
    release="debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
elif cat /proc/version | grep -q -E -i "debian"; then
    release="debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
    release="centos"
fi

do_iptables() {
    iptables_exists=$(iptables -V)
    if [[ ${iptables_exists} != "" ]]; then
        echo -e "${CMSG}[信息] 检测到已安装 iptables 程序！${CEND}"
    else
        echo -e "${CMSG}[信息] 检测到未安装 iptables 程序！${CEND}"
        if [[ ${release} == "centos" ]]; then
            yum makecache
            yum update -y
            yum install iptables iptables-services -y
        else
            apt update
            apt dist-upgrade -y
            apt install iptables iptables-persistent -y
        fi

        iptables_exists=$(iptables -V)
        if [[ ${iptables_exists} != "" ]]; then
            echo -e "${CSUCCESS}[信息] 安装 iptables 完毕！${CEND}"
        else
            echo -e "${CFAILURE}[错误] 安装 iptables 失败，请检查！${CEND}"
            exit 1
        fi
    fi

    echo -e "${CMSG}[信息] 写入 IP 转发参数中！ ${CEND}"
    iptables -P FORWARD ACCEPT
    sysctl -w "net.ipv4.ip_forward=1"
    sysctl -w "net.ipv6.conf.all.forwarding=1"
    sysctl -w "net.ipv6.conf.default.forwarding=1"

    echo -e "${CMSG}[信息] 执行完毕！${CEND}"
}

create_iptables() {
    read -e -p "请输入 iptables 远程端口 [1-65535]（支持端口段，如 10000-20000）：" REMOTE_PORT
    if [[ -z "${REMOTE_PORT}" ]]; then
        exit 1
    fi

    read -e -p "请输入 iptables 远程地址：" REMOTE_ADDR
    if [[ -z "${REMOTE_ADDR}" ]]; then
        exit 1
    fi

    read -e -p "请输入 iptables 本地端口 [1-65535]（回车跟随远程端口）：" LOCAL_PORT
    if [[ -z "${LOCAL_PORT}" ]]; then
        LOCAL_PORT="${REMOTE_PORT}"
    fi

    read -e -p "请输入 iptables 本地地址（输入网卡名称即可，回车默认 eth0）：" ETHERNET
    if [[ -z "${ETHERNET}" ]]; then
        ETHERNET="eth0"
    fi

    LOCAL_ADDR=$(ifconfig ${ETHERNET} | awk -F "[^0-9.]+" 'NR==2{print $2}')
    if [[ -z "${LOCAL_ADDR}" ]]; then
        echo -e "${CFAILURE}无法检测 ${ETHERNET} 网卡的 IP 地址${CEND}"
    fi

    echo -e "请选择 iptables 转发类型
 1. TCP
 2. UDP
 3. TCP + UDP\n"
    read -e -p "（默认 TCP + UDP）：" FORWARD_TYPE
    if [[ -z "${FORWARD_TYPE}" ]]; then
        FORWARD_TYPE="3"
    fi

    if [[ ${FORWARD_TYPE} == "1" ]]; then
        FORWARD_TYPE_TEXT="TCP"
    elif [[ ${FORWARD_TYPE} == "2" ]]; then
        FORWARD_TYPE_TEXT="UDP"
    elif [[ ${FORWARD_TYPE} == "3" ]]; then
        FORWARD_TYPE_TEXT="TCP + UDP"
    else
        FORWARD_TYPE="3"
        FORWARD_TYPE_TEXT="TCP + UDP"
    fi

    echo
    echo -e "——————————————————————————————
    请检查 iptables 转发规则配置是否有误！\n
    远程端口：${CGREEN}${REMOTE_PORT}${CEND}
    远程地址：${CGREEN}${REMOTE_ADDR}${CEND}
    本地端口：${CGREEN}${LOCAL_PORT}${CEND}
    本地地址：${CGREEN}${LOCAL_ADDR}${CEND}
    转发类型：${CGREEN}${FORWARD_TYPE_TEXT}${CEND}
——————————————————————————————\n"

    read -e -p "请按回车键继续，如有配置错误请使用 CTRL + C 退出！" TRASH
    
    REMOTE_PORT_IPT=$(echo ${REMOTE_PORT} | sed 's/-/:/g')
    LOCAL_PORT_IPT=$(echo ${LOCAL_PORT} | sed 's/-/:/g')

    clear
    if [[ ${FORWARD_TYPE} == "1" ]]; then
        iptables -t nat -A PREROUTING -p tcp -m tcp --dport "${LOCAL_PORT_IPT}" -j DNAT --to-destination "${REMOTE_ADDR}:${REMOTE_PORT}"
        echo "iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${LOCAL_PORT_IPT} -j DNAT --to-destination ${REMOTE_ADDR}:${REMOTE_PORT}"
        iptables -t nat -A POSTROUTING -d "${REMOTE_ADDR}/32" -p tcp -m tcp --dport "${REMOTE_PORT_IPT}" -j SNAT --to-source "${LOCAL_ADDR}"
        echo "iptables -t nat -A POSTROUTING -d ${REMOTE_ADDR}/32 -p tcp -m tcp --dport ${REMOTE_PORT_IPT} -j SNAT --to-source ${LOCAL_ADDR}"
    elif [[ ${FORWARD_TYPE} == "2" ]]; then
        iptables -t nat -A PREROUTING -p udp -m udp --dport "${LOCAL_PORT_IPT}" -j DNAT --to-destination "${REMOTE_ADDR}:${REMOTE_PORT}"
        echo "iptables -t nat -A PREROUTING -p udp -m udp --dport ${LOCAL_PORT_IPT} -j DNAT --to-destination ${REMOTE_ADDR}:${REMOTE_PORT}"
        iptables -t nat -A POSTROUTING -d "${REMOTE_ADDR}/32" -p udp -m udp --dport "${REMOTE_PORT_IPT}" -j SNAT --to-source "${LOCAL_ADDR}"
        echo "iptables -t nat -A POSTROUTING -d ${REMOTE_ADDR}/32 -p udp -m udp --dport ${REMOTE_PORT_IPT} -j SNAT --to-source ${LOCAL_ADDR}"
    elif [[ ${FORWARD_TYPE} == "3" ]]; then
        iptables -t nat -A PREROUTING -p tcp -m tcp --dport "${LOCAL_PORT_IPT}" -j DNAT --to-destination "${REMOTE_ADDR}:${REMOTE_PORT}"
        echo "iptables -t nat -A PREROUTING -p tcp -m tcp --dport ${LOCAL_PORT_IPT} -j DNAT --to-destination ${REMOTE_ADDR}:${REMOTE_PORT}"
        iptables -t nat -A POSTROUTING -d "${REMOTE_ADDR}/32" -p tcp -m tcp --dport "${REMOTE_PORT_IPT}" -j SNAT --to-source "${LOCAL_ADDR}"
        echo "iptables -t nat -A POSTROUTING -d ${REMOTE_ADDR}/32 -p tcp -m tcp --dport ${REMOTE_PORT_IPT} -j SNAT --to-source ${LOCAL_ADDR}"

        iptables -t nat -A PREROUTING -p udp -m udp --dport "${LOCAL_PORT_IPT}" -j DNAT --to-destination "${REMOTE_ADDR}:${REMOTE_PORT}"
        echo "iptables -t nat -A PREROUTING -p udp -m udp --dport ${LOCAL_PORT_IPT} -j DNAT --to-destination ${REMOTE_ADDR}:${REMOTE_PORT}"
        iptables -t nat -A POSTROUTING -d "${REMOTE_ADDR}/32" -p udp -m udp --dport "${REMOTE_PORT_IPT}" -j SNAT --to-source "${LOCAL_ADDR}"
        echo "iptables -t nat -A POSTROUTING -d ${REMOTE_ADDR}/32 -p udp -m udp --dport ${REMOTE_PORT_IPT} -j SNAT --to-source ${LOCAL_ADDR}"
    fi

    echo
    echo -e "——————————————————————————————
    ${CMSG}创建 iptables 转发规则完毕！${CEND}\n
    远程端口：${CGREEN}${REMOTE_PORT}${CEND}
    远程地址：${CGREEN}${REMOTE_ADDR}${CEND}
    本地端口：${CGREEN}${LOCAL_PORT}${CEND}
    本地地址：${CGREEN}${LOCAL_ADDR}${CEND}
    转发类型：${CGREEN}${FORWARD_TYPE_TEXT}${CEND}
——————————————————————————————\n"
}

delete_iptables() {
    select_iptables

    echo
    read -e -p "请选择需要删除的转发规则：" DELETE_ID
    if [[ -z "${DELETE_ID}" ]]; then
        exit 1
    fi

    echo
    iptables -t nat -D PREROUTING "${DELETE_ID}"
    echo "iptables -t nat -D PREROUTING ${DELETE_ID}"
    iptables -t nat -D POSTROUTING "${DELETE_ID}"
    echo "iptables -t nat -D POSTROUTING ${DELETE_ID}"

    echo
    echo -e "${CMSG}[信息] 执行完毕！${CEND}"
}

select_iptables() {
    SELECT_TEXT=$(iptables -t nat -vnL PREROUTING | tail -n +3)
    if [[ -z "${SELECT_TEXT}" ]]; then
        echo -e "${CFAILURE}[错误] 没有检测到 iptables 转发规则，请检查！${CEND}"
        exit 1
    fi

    SELECT_COUT=$(echo -e "${SELECT_TEXT}" | wc -l)
    SELECT_LIST=""

    for ((i = 1; i <= ${SELECT_COUT}; i++))
    do
        RULE_TYPE=$(echo -e "${SELECT_TEXT}" | awk '{print $4}' | sed -n "${i}p" | tr '[:lower:]' '[:upper:]')
        RULE_LOCAL=$(echo -e "${SELECT_TEXT}" | awk '{print $11}' | sed -n "${i}p" | awk -F "dpt:" '{print $2}')

        if [[ -z ${RULE_LOCAL} ]]; then
            RULE_LOCAL=$(echo -e "${SELECT_TEXT}" | awk '{print $11}' | sed -n "${i}p" | awk -F "dpts:" '{print $2}')
        fi

        RULE_REMOTE=$(echo -e "${SELECT_TEXT}" | awk '{print $12}' | sed -n "${i}p" | awk -F "to:" '{print $2}')
        SELECT_LIST="${SELECT_LIST}${CGREEN}${i}.${CEND} ${CYELLOW}类型：${CEND}${RULE_TYPE} ${CYELLOW}本地端口: ${CEND}${RULE_LOCAL} ${CYELLOW}远程地址和端口: ${CEND}${RULE_REMOTE}${CEND}\n"
    done

    clear
    echo
    echo -e "当前有 ${CGREEN}${SELECT_COUT}${CEND} 条 iptables 转发规则"
    echo -e ${SELECT_LIST}
}   

save_iptables() {
    clear

    echo -e "${CMSG}[信息] 正在保存 iptables 转发规则中！ ${CEND}"
    if [[ ${release} == "centos" ]]; then
        service iptables save
    else
        netfilter-persistent save
    fi

    echo -e "${CMSG}[信息] 执行完毕！${CEND}"
}

clear_iptables() {
    clear

    echo -e "${CMSG}[信息] 正在清空 iptables 转发规则中！ ${CEND}"
    iptables -t nat -F
    iptables -t nat -X

    echo -e "${CMSG}[信息] 执行完毕！${CEND}"
}

echo -e "端口转发管理脚本 ${CRED}[v${VERSION}]${CEND}

 ${CGREEN}0.${CEND} 安装 iptables / 启用 IP 转发
————————————
 ${CGREEN}1.${CEND} 添加 iptables 转发规则
 ${CGREEN}2.${CEND} 删除 iptables 转发规则
 ${CGREEN}3.${CEND} 查看 iptables 转发规则
 ${CGREEN}4.${CEND} 保存 iptables 转发规则
 ${CGREEN}5.${CEND} 清空 iptables 转发规则
————————————

"

read -e -p "请输入数字 [0-5]：" code
case "$code" in
    0)
        do_iptables
    ;;
    1)
        create_iptables
    ;;
    2)
        delete_iptables
    ;;
    3)
        select_iptables
    ;;
    4)
        save_iptables
    ;;
    5)
        clear_iptables
    ;;
    *)
        echo -e "${CFAILURE}[错误] 请输入正确的数字！${CEND}"
    ;;
esac

exit 0
