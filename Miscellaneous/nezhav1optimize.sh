#!/bin/bash

CONFIG_FILE="/opt/nezha/agent/config.yml"

# 检查文件是否存在
if [ ! -f "$CONFIG_FILE" ]; then
    echo "错误：配置文件 $CONFIG_FILE 不存在"
    exit 1
fi

# 创建备份
cp "$CONFIG_FILE" "${CONFIG_FILE}.backup"
if [ $? -ne 0 ]; then
    echo "错误：无法创建配置文件备份"
    exit 1
fi

# 使用sed命令修改配置文件
sed -i 's/disable_auto_update: false/disable_auto_update: true/' "$CONFIG_FILE"
sed -i 's/disable_command_execute: false/disable_command_execute: true/' "$CONFIG_FILE"
sed -i 's/disable_nat: false/disable_nat: true/' "$CONFIG_FILE"
sed -i 's/disable_send_query: false/disable_send_query: true/' "$CONFIG_FILE"
sed -i 's/report_delay: 1/report_delay: 3/' "$CONFIG_FILE"

# 检查修改是否成功
if [ $? -ne 0 ]; then
    echo "错误：修改配置文件失败"
    echo "正在恢复备份..."
    mv "${CONFIG_FILE}.backup" "$CONFIG_FILE"
    exit 1
fi

# 显示修改后的内容
echo "配置文件修改成功。修改后的内容如下："
grep -E "disable_|report_delay:" "$CONFIG_FILE"

# 删除备份文件
rm "${CONFIG_FILE}.backup"

# 重启 nezha-agent 服务
if ! sudo systemctl restart nezha-agent.service; then
    echo "错误：重启 nezha-agent 服务失败"
    exit 1
fi

echo "脚本执行完成，服务已重启"