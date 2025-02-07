echo "-------------------- Install bw cli -------------------- "

apt update
apt install wget unzip -y
# 下载 CLI 包
wget https://github.com/bitwarden/clients/releases/download/cli-v2024.12.0/bw-linux-2024.12.0.zip

# 解压文件
unzip bw-linux-2024.12.0.zip
# 移动到系统可执行文件目录
sudo mv bw /usr/local/bin/
# 添加执行权限
chmod +x /usr/local/bin/bw

bw --version

bw config server $BW_SERVER
bw login

# 解锁并导出会话密钥
export BW_SESSION="$(bw unlock --raw)"

# 同步数据
bw sync

# 检查登录状态
bw status

rm -f bw-linux-2024.12.0*
