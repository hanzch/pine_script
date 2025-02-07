#!/bin/bash

# 错误处理函数
handle_error() {
    echo "Error: $1"
    exit 1
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    handle_error "请使用root权限运行此脚本"
fi

# 参数检查
if [ "$#" -lt 1 ]; then
    echo "Usage: $0 <username> [uid] [gid] [public_key]"
    echo "Example: $0 newuser 1001 1001 'ssh-rsa AAAAB3NzaC1...'"
    exit 1
fi


# 参数处理
USERNAME=$1
# 自动找到可用的UID（1000-60000之间的最大值+1）
USER_UID=${2:-$(getent passwd | awk -F: '{if ($3 >= 1000 && $3 < 60000) max=$3} END{print max+1}')}
USER_GID=${3:-$USER_UID}

# 检查用户名是否已存在
if id "$USERNAME" &>/dev/null; then
    handle_error "Username $USERNAME already exists"
fi

# 检查 UID 是否已存在
if id -u $USER_UID &>/dev/null; then
    handle_error "UID $USER_UID already exists"
fi

# 检查 GID 是否已存在
if getent group $USER_GID &>/dev/null; then
    handle_error "GID $USER_GID already exists"
fi

# 创建用户组
echo "Creating new group with GID: $USER_GID"
sudo groupadd -g $USER_GID $USERNAME || handle_error "Failed to create group"

# 创建用户并指定 UID 和 GID
echo "Creating new user: $USERNAME with UID: $USER_UID and GID: $USER_GID"
sudo useradd -m -u $USER_UID -g $USER_GID -s /bin/bash $USERNAME || handle_error "Failed to create user"

# 配置 sudo 权限
configure_sudo() {
    # 创建备份
    sudo cp /etc/sudoers /etc/sudoers.bak_$(date +%Y%m%d_%H%M%S)

    # 创建新的配置文件
    SUDO_TMP=$(mktemp)
    echo "$USERNAME ALL=(ALL:ALL) NOPASSWD: ALL" | sudo tee "$SUDO_TMP" > /dev/null

    # 检查新配置语法
    if ! sudo visudo -c -f "$SUDO_TMP"; then
        echo "Invalid sudoers entry"
        sudo rm -f "$SUDO_TMP"
        return 1
    fi

    # 将配置添加到 sudoers.d 目录
    sudo mv "$SUDO_TMP" "/etc/sudoers.d/99-$USERNAME"

    # 验证 sudo 权限
    if ! sudo -l -U "$USERNAME" >/dev/null 2>&1; then
        echo "Failed to configure sudo privileges"
        return 1
    fi
}

# 添加到sudo组并配置权限
echo "Adding user to sudo group and configuring permissions"
sudo usermod -aG sudo $USERNAME || handle_error "Failed to add user to sudo group"
configure_sudo || handle_error "Failed to configure sudo permissions"

# 创建SSH目录
echo "Setting up SSH directory"
SSH_DIR="/home/$USERNAME/.ssh"
sudo -u $USERNAME mkdir -p "$SSH_DIR" || handle_error "Failed to create .ssh directory"
sudo -u $USERNAME chmod 700 "$SSH_DIR"

# 处理SSH密钥
if [ -z "$4" ]; then
    echo "No public key provided, generating new SSH key pair..."
    KEY_FILE="/tmp/${USERNAME}_ssh_key"
    sudo -u $USERNAME ssh-keygen -t ed25519 -f "$KEY_FILE" -N "" || handle_error "Failed to generate SSH key pair"
    PUBLIC_KEY=$(cat "${KEY_FILE}.pub") || handle_error "Failed to read public key"

    echo "New SSH key pair generated:"
    echo "Private key location: ${KEY_FILE}"
    echo "Public key location: ${KEY_FILE}.pub"
    echo -e "\033[1;31m=====================================================================\033[0m"
    echo -e "\033[1;31m重要: 请在关闭窗口前，妥善保存这些KEY.\033[0m"
    echo -e "\033[1;31m=====================================================================\033[0m"
else
    PUBLIC_KEY=$4
fi

# 添加公钥
echo "Adding SSH public key"
echo "$PUBLIC_KEY" | sudo -u $USERNAME tee "$SSH_DIR/authorized_keys" > /dev/null || handle_error "Failed to add public key"
sudo -u $USERNAME chmod 600 "$SSH_DIR/authorized_keys"

# 配置SSH
echo "Configuring SSH"
SSHD_CONFIG="/etc/ssh/sshd_config"
# 备份原配置
sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak" || handle_error "Failed to backup sshd_config"

# 更新配置函数
update_ssh_config() {
    local key=$1
    local value=$2

    # 删除所有相关配置（包括注释的）
    sudo sed -i "/^#*${key}\s/d" "$SSHD_CONFIG"
    # 添加新配置
    echo "${key} ${value}" | sudo tee -a "$SSHD_CONFIG" > /dev/null
}

# 更新SSH配置
echo "Updating SSH configuration"
update_ssh_config "PasswordAuthentication" "no"
update_ssh_config "PubkeyAuthentication" "yes"
update_ssh_config "PermitRootLogin" "no"
update_ssh_config "ChallengeResponseAuthentication" "no"
update_ssh_config "UsePAM" "yes"

# 验证SSH配置
echo "Validating SSH configuration"
sudo sshd -t || handle_error "SSH configuration is invalid"

# 重启SSH服务
echo "Restarting SSH service"
if command -v systemctl &>/dev/null; then
    sudo systemctl restart sshd || handle_error "Failed to restart SSH service"
else
    sudo service sshd restart || handle_error "Failed to restart SSH service"
fi



# 显示结果
echo -e "\n====== Setup completed successfully! ======"
echo "User details:"
echo "Username: $USERNAME"
echo "UID: $USER_UID"
echo "GID: $USER_GID"
echo "Home directory: /home/$USERNAME"
echo "SSH directory: $SSH_DIR"


echo -e "\033[1;31m=====================================================================\033[0m"
echo "Connection command:"
echo "首先保存私钥文件： ${KEY_FILE}"
echo "然后使用命令: ssh -i <path_to_private_key> $USERNAME@<SERVER_IP>"
echo -e "\033[1;31m请在关闭这个窗口前，创建新的连接并测试通过！\033[0m"
echo -e "\033[1;31m=====================================================================\033[0m"