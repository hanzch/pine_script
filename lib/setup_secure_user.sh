#!/bin/bash

# 错误处理函数
handle_error() {
    echo "错误: $1"
    exit 1
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    handle_error "请使用root权限运行此脚本"
fi

# 参数检查
if [ "$#" -lt 1 ]; then
    echo "用法: $0 <用户名> [UID] [GID] [公钥]"
    echo "示例: $0 newuser 1001 1001 'ssh-rsa AAAAB3NzaC1...'"
    exit 1
fi

# 参数处理
USERNAME=$1
# 自动找到可用的UID（1000-60000之间的最大值+1）
USER_UID=${2:-$(getent passwd | awk -F: '{if ($3 >= 1000 && $3 < 60000) max=$3} END{print max+1}')}
USER_GID=${3:-$USER_UID}

# 检查用户名是否已存在
if id "$USERNAME" &>/dev/null; then
    handle_error "用户名 $USERNAME 已存在"
fi

# 检查 UID 是否已存在
if id -u $USER_UID &>/dev/null; then
    handle_error "UID $USER_UID 已存在"
fi

# 检查 GID 是否已存在
if getent group $USER_GID &>/dev/null; then
    handle_error "GID $USER_GID 已存在"
fi

# 创建用户组
echo "正在创建新用户组，GID: $USER_GID"
sudo groupadd -g $USER_GID $USERNAME || handle_error "创建用户组失败"

# 创建用户并指定 UID 和 GID
echo "正在创建新用户: $USERNAME，UID: $USER_UID，GID: $USER_GID"
sudo useradd -m -u $USER_UID -g $USER_GID -s /bin/bash $USERNAME || handle_error "创建用户失败"

# 配置 sudo 权限
configure_sudo() {
    # 创建备份
    sudo cp /etc/sudoers /etc/sudoers.bak_$(date +%Y%m%d_%H%M%S)

    # 创建新的配置文件
    SUDO_TMP=$(mktemp)
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "$SUDO_TMP" > /dev/null

    # 检查新配置语法
    if ! sudo visudo -c -f "$SUDO_TMP"; then
        echo "无效的sudoers配置项"
        sudo rm -f "$SUDO_TMP"
        return 1
    fi

    # 将配置添加到 sudoers.d 目录
    sudo mv "$SUDO_TMP" "/etc/sudoers.d/99-$USERNAME"

    # 验证 sudo 权限
    if ! sudo -l -U "$USERNAME" >/dev/null 2>&1; then
        echo "配置sudo权限失败"
        return 1
    fi
}

# 添加到sudo组并配置权限
echo "正在添加用户到sudo组并配置权限"
sudo usermod -aG sudo $USERNAME || handle_error "添加用户到sudo组失败"
configure_sudo || handle_error "配置sudo权限失败"

# 创建SSH目录
echo "正在设置SSH目录"
SSH_DIR="/home/$USERNAME/.ssh"
sudo -u $USERNAME mkdir -p "$SSH_DIR" || handle_error "创建.ssh目录失败"
sudo -u $USERNAME chmod 700 "$SSH_DIR"

# 处理SSH密钥
if [ -z "$4" ]; then
    echo "未提供公钥，正在生成新的SSH密钥对..."
    KEY_FILE="/tmp/${USERNAME}_ssh_key"
    sudo -u $USERNAME ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" || handle_error "生成SSH密钥对失败"
    PUBLIC_KEY=$(cat "${KEY_FILE}.pub") || handle_error "读取公钥失败"

    echo "新的SSH密钥对已生成："
    echo "私钥位置: ${KEY_FILE}"
    echo "公钥位置: ${KEY_FILE}.pub"
    echo -e "\033[1;31m=====================================================================\033[0m"
    echo -e "\033[1;31m重要: 请在关闭窗口前，妥善保存这些密钥。\033[0m"
    echo -e "\033[1;31m=====================================================================\033[0m"
else
    PUBLIC_KEY=$4
fi

# 添加公钥
echo "正在添加SSH公钥"
echo "$PUBLIC_KEY" | sudo -u $USERNAME tee "$SSH_DIR/authorized_keys" > /dev/null || handle_error "添加公钥失败"
sudo -u $USERNAME chmod 600 "$SSH_DIR/authorized_keys"

# 配置SSH
echo "正在配置SSH"
SSHD_CONFIG="/etc/ssh/sshd_config"
# 备份原配置
sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" || handle_error "备份sshd_config失败"

# 更新配置函数
update_ssh_config() {
    local key=$1
    local value=$2
    sudo sed -i "/^#*${key}\s/d" "$SSHD_CONFIG"
    echo "${key} ${value}" | sudo tee -a "$SSHD_CONFIG" > /dev/null
}

# 更新SSH配置
echo "正在更新SSH配置"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "PubkeyAuthentication" "yes"
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UsePAM" "yes"

# 验证SSH配置
echo "正在验证SSH配置"
sudo sshd -t || handle_error "SSH配置无效"

# 重启SSH服务（优化后的版本）
echo "正在重启SSH服务"
if command -v systemctl &>/dev/null; then
    # 检查服务名称
    if systemctl list-unit-files | grep -q sshd.service; then
        sudo systemctl restart sshd || handle_error "重启SSH服务失败"
    elif systemctl list-unit-files | grep -q ssh.service; then
        sudo systemctl restart ssh || handle_error "重启SSH服务失败"
    else
        handle_error "未找到SSH服务单元"
    fi
else
    # 对于使用service命令的系统
    if service --status-all 2>&1 | grep -q sshd; then
        sudo service sshd restart || handle_error "重启SSH服务失败"
    elif service --status-all 2>&1 | grep -q ssh; then
        sudo service ssh restart || handle_error "重启SSH服务失败"
    else
        handle_error "未找到SSH服务"
    fi
fi

# 显示结果
echo -e "\n====== 设置完成！======"
echo "用户详情:"
echo "用户名: $USERNAME"
echo "UID: $USER_UID"
echo "GID: $USER_GID"
echo "主目录: /home/$USERNAME"
echo "SSH目录: $SSH_DIR"

echo -e "\033[1;31m=====================================================================\033[0m"
echo "连接命令:"
echo "首先保存私钥文件： ${KEY_FILE}"
echo "然后使用命令: ssh -i <私钥路径> $USERNAME@<服务器IP>"
echo -e "\033[1;31m请在关闭这个窗口前，创建新的连接并测试通过！\033[0m"
echo -e "\033[1;31m=====================================================================\033[0m"