#!/bin/bash
echo "-------------------- 安装 Bitwarden CLI --------------------"

# 安装依赖
echo "正在更新软件包列表..."
apt update
echo "正在安装必要依赖..."
apt install wget zip unzip -y

# 配置变量
FILE_NAME="bw-linux-2024.12.0.zip"
URL="https://github.com/bitwarden/clients/releases/download/cli-v2024.12.0/${FILE_NAME}"

# 下载函数
download_file() {
    echo "开始下载文件..."
    if ! wget -c "${URL}"; then
        echo "下载失败，请检查网络连接或 URL 是否正确"
        exit 1
    fi
}

# 文件检查和下载逻辑
NEED_DOWNLOAD=true

if [ -f "${FILE_NAME}" ]; then
    echo "发现本地文件，正在检查完整性..."
    LOCAL_SIZE=$(stat -c%s "${FILE_NAME}" 2>/dev/null)
    REMOTE_SIZE=$(curl -sI "${URL}" | grep -i content-length | awk '{print $2}' | tr -d '\r')

    if [ -n "${LOCAL_SIZE}" ] && [ -n "${REMOTE_SIZE}" ]; then
        if [ "${LOCAL_SIZE}" = "${REMOTE_SIZE}" ]; then
            echo "文件已存在且完整，无需重新下载"
            NEED_DOWNLOAD=false
        else
            echo "文件不完整，开始断点续传..."
        fi
    else
        echo "无法获取文件大小信息，开始重新下载..."
    fi
else
    echo "本地文件不存在，开始下载..."
fi

[ "$NEED_DOWNLOAD" = true ] && download_file

# 解压前检查文件是否存在和完整
if [ ! -f "${FILE_NAME}" ]; then
    echo "错误：ZIP 文件不存在，无法继续安装"
    exit 1
fi

# 检查文件是否为有效的 ZIP 文件
if ! unzip -t "${FILE_NAME}" > /dev/null 2>&1; then
    echo "错误：文件已损坏或不是有效的 ZIP 文件"
    echo "删除损坏的文件并重新运行脚本"
    rm -f "${FILE_NAME}"
    exit 1
fi

# 安装步骤
echo "正在解压文件..."
if ! unzip -o ${FILE_NAME}; then
    echo "解压失败"
    exit 1
fi

# 检查解压后的文件是否存在
if [ ! -f "bw" ]; then
    echo "错误：未找到 bw 可执行文件"
    exit 1
fi

echo "正在移动可执行文件到系统目录..."
if ! sudo mv bw /usr/local/bin/; then
    echo "移动文件失败"
    exit 1
fi

echo "设置执行权限..."
if ! chmod +x /usr/local/bin/bw; then
    echo "设置权限失败"
    exit 1
fi

# 验证安装
echo "验证安装版本..."
if ! bw --version; then
    echo "安装似乎有问题，无法执行 bw 命令"
    exit 1
fi

# 配置和登录
if [ -n "$BW_SERVER" ]; then
    echo "配置服务器地址..."
    if ! bw config server "$BW_SERVER"; then
        echo "服务器配置失败"
        exit 1
    fi
fi

echo "请登录您的账户..."
if ! bw login; then
    echo "登录失败"
    exit 1
fi

# 解锁并设置会话
echo "解锁保管库..."
BW_SESSION_OUTPUT=$(bw unlock --raw)
if [ -z "$BW_SESSION_OUTPUT" ]; then
    echo "解锁失败"
    exit 1
fi
export BW_SESSION="$BW_SESSION_OUTPUT"

# 同步和状态检查
echo "同步数据..."
if ! bw sync; then
    echo "同步失败"
    exit 1
fi

echo "检查登录状态..."
if ! bw status; then
    echo "状态检查失败"
    exit 1
fi

# 清理
echo "清理临时文件..."
rm -rf bw-linux-2024.12.0*
echo "安装完成！"