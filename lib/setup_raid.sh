#!/bin/bash

# 创建日志目录
mkdir -p "$(pwd)/logs"

# 设置日志文件
LOG_FILE="$(pwd)/logs/raid_setup.log"

# 默认配置
DISK1="/dev/nvme1n1"
DISK2="/dev/nvme2n1"
MOUNT_POINT="/mnt/raid1"
RAID_DEVICE="/dev/md0"

# 日志函数
log() {
   local message="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
   echo "$message" | tee -a "$LOG_FILE"
}

# 错误处理函数
handle_error() {
   log "错误: $1"
   rollback
   exit 1
}

# 回滚函数
rollback() {
   log "开始回滚操作..."
   mdadm --stop "$RAID_DEVICE" 2>/dev/null
   sed -i "\|UUID=.*$MOUNT_POINT|d" /etc/fstab
   umount "$MOUNT_POINT" 2>/dev/null
   log "回滚完成"
}

cleanup_old_log() {
   if [ -f "$LOG_FILE" ]; then
       log "发现旧日志文件，正在删除..."
       rm -f "$LOG_FILE"
   fi
}

show_help() {
    echo "当前系统中的硬盘："
    # 显示所有磁盘设备
    lsblk -d -o NAME,SIZE,MODEL | grep -E 'nvme|sd'

    echo -e "\n可用的硬盘设备：(仅展示非系统硬盘的磁盘，可能已经被其他RAID使用)"
    # 处理 NVMe 设备
    for dev in /dev/nvme*n1; do
        if [ -b "$dev" ]; then
            if ! mount | grep -q "^$dev.* / " && ! mount | grep -q "^$dev.* /boot"; then
                if ! mount | grep -q "^$dev"; then
                    echo "$dev ($(lsblk -dn -o SIZE,MODEL "$dev"))"
                fi
            fi
        fi
    done

    # 处理 SATA 设备
    if [ -e /dev/sda ]; then  # 只有在存在 SATA 设备时才执行
        for letter in {a..z}; do
            dev="/dev/sd$letter"
            if [ -b "$dev" ]; then
                if ! mount | grep -q "^$dev.* / " && ! mount | grep -q "^$dev.* /boot"; then
                    if ! mount | grep -q "^$dev"; then
                        echo "$dev ($(lsblk -dn -o SIZE,MODEL "$dev"))"
                    fi
                fi
            fi
        done
    fi

    echo -e "\n用法: $(basename "$0") [选项]"
    cat << EOF
选项:
    -h          显示帮助信息
    -d1 设备1    第一个磁盘设备 (默认: $DISK1)
    -d2 设备2    第二个磁盘设备 (默认: $DISK2)
    -m 挂载点    RAID挂载点 (默认: $MOUNT_POINT)
EOF
    exit 0
}

# 检查root权限
if [ "$EUID" -ne 0 ]; then
    log "请使用root权限运行此脚本"
    exit 1
fi

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 检查参数数量
if [ $# -lt 2 ]; then
    echo "错误: 至少需要提供两个磁盘设备"
    show_help
    exit 1
fi

# 如果只有两个参数，设置磁盘设备
if [ $# -eq 2 ]; then
    DISK1="$1"
    DISK2="$2"
# 如果有三个参数，最后一个设置为挂载点
elif [ $# -eq 3 ]; then
    DISK1="$1"
    DISK2="$2"
    MOUNT_POINT="$3"
fi

check_existing_raid() {
    log "扫描现有 RAID 配置..."

    # 检查是否存在现有RAID
    if grep -q "${RAID_DEVICE#/dev/}" /proc/mdstat; then
        log "检测到 RAID 设备 $RAID_DEVICE 已处于活动状态"
        if mdadm --detail "$RAID_DEVICE" &>/dev/null; then
            local raid_status=$(mdadm --detail "$RAID_DEVICE" | grep "State :" | awk '{print $3}')
            log "RAID 状态: $raid_status"
            return 0  # 返回0表示找到了正常运行的RAID
        fi
    fi

    local has_raid=false
    local raid_uuid=""
    local found_disks=()

    for disk in "$DISK1" "$DISK2"; do
        if mdadm --examine "$disk" &>/dev/null; then
            local disk_role=$(mdadm --examine "$disk" | grep "Device Role" | awk '{print $4}')
            local disk_uuid=$(mdadm --examine "$disk" | grep "Array UUID" | awk '{print $4}')
            local array_level=$(mdadm --examine "$disk" | grep "Raid Level" | awk '{print $4}')

            found_disks+=("$disk")

            if [[ -n "$raid_uuid" && "$disk_uuid" != "$raid_uuid" ]]; then
                log "错误：检测到磁盘属于不同的 RAID 阵列"
                log "磁盘 ${found_disks[*]} 不能一起使用"
                exit 2
            fi

            raid_uuid="$disk_uuid"
            has_raid=true

            log "发现磁盘 $disk 属于 RAID$array_level 阵列 ($raid_uuid)"
        fi
    done

    if $has_raid && [[ -n "$raid_uuid" ]]; then
        log "发现现有 RAID 配置，尝试组装..."

        # 如果 RAID 已经在运行但不是完全正常状态，尝试停止它
        if grep -q "${RAID_DEVICE#/dev/}" /proc/mdstat; then
            log "停止现有 RAID 设备..."
            mdadm --stop "$RAID_DEVICE"
        fi

        if mdadm --assemble "$RAID_DEVICE" --uuid="$raid_uuid"; then
            log "成功组装 RAID 设备 $RAID_DEVICE"
            local raid_status=$(mdadm --detail "$RAID_DEVICE" | grep "State :" | awk '{print $3}')
            log "RAID 状态: $raid_status"
            return 0
        else
            log "组装 RAID 设备失败"
            log "当前 RAID 状态:"
            mdadm --detail "$RAID_DEVICE" 2>&1 | while IFS= read -r line; do
                log "  $line"
            done
            log "建议执行以下步骤排查："
            log "1. 检查 dmesg 输出是否有相关错误"
            log "2. 验证磁盘权限和可用性"
            log "3. 如需重新创建 RAID，请先清除现有配置："
            log "   mdadm --zero-superblock ${found_disks[*]}"
            exit 3
        fi
    fi

    log "未发现现有 RAID 配置，可以继续创建新的 RAID"
    return 1
}

# 磁盘检查
check_disks() {
   log "检查磁盘设备..."

   for DISK in "$DISK1" "$DISK2"; do
       # 检查设备是否存在
       if [ ! -b "$DISK" ]; then
           handle_error "找不到磁盘 $DISK"
       fi

       # 检查是否被挂载
       if mount | grep -q "$DISK"; then
           handle_error "错误：$DISK 已被挂载，请先卸载"
       fi

       # 检查是否有活动的分区和数据
       if lsblk "$DISK" -n -o MOUNTPOINT | grep -q .; then
           handle_error "错误：$DISK 的分区当前正在使用中"
       fi

       # 检查分区表
       if fdisk -l "$DISK" | grep -q "Disk label type:"; then
           echo "警告：检测到 $DISK 存在分区表"
           echo "分区信息："
           fdisk -l "$DISK"
           read -p "是否确定要清除 $DISK 的所有数据？(yes/no) " confirm
           if [ "$confirm" != "yes" ]; then
               handle_error "用户取消操作"
           fi
       fi

       # 检查是否为系统盘
       if mount | grep -q "^$DISK.* / " || mount | grep -q "^$DISK.* /boot"; then
           handle_error "错误：$DISK 包含系统分区，不能用于RAID"
       fi
   done

   # 最后确认
   echo "将要使用以下磁盘创建RAID："
   echo "磁盘1: $DISK1"
   echo "磁盘2: $DISK2"
   read -p "确认继续？这将清除这些磁盘上的所有数据 (yes/no) " final_confirm
   if [ "$final_confirm" != "yes" ]; then
       handle_error "用户取消操作"
   fi

   # 清除分区表
   for DISK in "$DISK1" "$DISK2"; do
       log "清除 $DISK 的分区表"
       sgdisk --zap-all "$DISK" || handle_error "清除分区表失败"
   done

   log "磁盘检查完成"
}

# 检查挂载点
check_mount_point() {
   log "检查挂载点 $MOUNT_POINT..."

   # 检查挂载点是否已经存在且不为空
   if [ -d "$MOUNT_POINT" ]; then
       if [ "$(ls -A "$MOUNT_POINT")" ]; then
           handle_error "挂载点 $MOUNT_POINT 不为空，请先清空或指定其他挂载点"
       fi
   fi

   # 检查挂载点是否已经被其他设备使用
   if mount | grep -q " on $MOUNT_POINT "; then
       handle_error "挂载点 $MOUNT_POINT 已被其他设备使用"
   fi

   # 检查挂载点是否在 fstab 中已有配置
   if grep -q "$MOUNT_POINT" /etc/fstab; then
       handle_error "挂载点 $MOUNT_POINT 在 /etc/fstab 中已有配置"
   fi

   # 检查挂载点路径的父目录是否存在且有写权限
   parent_dir=$(dirname "$MOUNT_POINT")
   if [ ! -w "$parent_dir" ]; then
       handle_error "没有权限创建挂载点，请检查 $parent_dir 的权限"
   fi

   log "挂载点检查完成"
}

# 最终检查函数
# 最终检查函数
final_check() {
    log "执行最终检查..."

    # 首先检查RAID设备是否存在
    if [ ! -b "$RAID_DEVICE" ]; then
       handle_error "RAID设备 $RAID_DEVICE 不存在"
    fi   # 这里是正确的写法，之前有多余的 }

   # 检查RAID状态
   raid_state=$(mdadm --detail "$RAID_DEVICE" | grep "State :" | awk '{print $3, $4, $5}')
   log "当前RAID状态: $raid_state"

    # 检查状态
    case "$raid_state" in
        *"clean"*|*"active"*|*"resyncing"*)
            # 标记是否有特殊情况
            has_special_condition=false

            if [[ "$raid_state" == *"read-only"* ]]; then
                log "警告: RAID当前处于只读状态，请稍后使用 'mdadm --detail $RAID_DEVICE' 确认状态"
                has_special_condition=true
            fi

            if [[ "$raid_state" == *"degraded"* ]]; then
                log "警告: RAID当前处于降级状态，请稍后使用 'mdadm --detail $RAID_DEVICE' 检查具体情况"
                has_special_condition=true
            fi

            if [[ "$raid_state" == *"resyncing"* ]]; then
                log "提示: RAID正在重新同步，请稍后使用 'mdadm --detail $RAID_DEVICE' 确认同步是否完成"
                has_special_condition=true
            fi

            # 如果没有特殊情况，输出正常状态信息
            if [ "$has_special_condition" = false ]; then
                log "RAID状态正常，可以正常使用"
            fi
            ;;
        *)
            handle_error "RAID状态异常: $raid_state"
            ;;
    esac

    # 检查挂载状态
    if ! mount | grep -q "$RAID_DEVICE on $MOUNT_POINT"; then
       handle_error "挂载点检查失败"
    fi

    # 检查文件系统
    if ! df -h "$MOUNT_POINT"; then
       handle_error "文件系统检查失败"
    fi

    log "所有检查通过"

    # 显示最终状态
    echo "RAID 1设置完成！"
    echo "挂载点: $MOUNT_POINT"
    echo "详细日志请查看: $LOG_FILE"

    return 0
}

# 主要处理流程
main() {
    # 清理旧日志
    cleanup_old_log

    # 检查是否存在现有 RAID
    if check_existing_raid; then
       log "现有 RAID 配置正常运行"
       final_check
       exit 0
    fi

    # 如果没有现有RAID,继续创建新的RAID
    log "开始创建新的RAID配置..."

    # 检查磁盘
    check_disks

    # 检查挂载点
    check_mount_point

    # 创建挂载点
    log "创建挂载点 $MOUNT_POINT"
    mkdir -p "$MOUNT_POINT" || handle_error "创建挂载点失败"

    # 创建RAID 1阵列
    log "创建RAID 1阵列..."
    mdadm --create "$RAID_DEVICE" --level=1 --raid-devices=2 "$DISK1" "$DISK2" || \
       handle_error "创建RAID失败"

    # 等待RAID设备就绪
    log "等待RAID设备就绪..."
    sleep 5

    # 创建文件系统
    log "等待文件系统准备就绪..."
    sleep 3
    log "创建文件系统..."
    mkfs.ext4 "$RAID_DEVICE" || handle_error "创建文件系统失败"

    # 获取UUID并更新fstab
    UUID=$(blkid -s UUID -o value "$RAID_DEVICE")
    echo "UUID=$UUID $MOUNT_POINT ext4 defaults 0 0" >> /etc/fstab || \
       handle_error "更新fstab失败"

    # 重载系统服务
    log "重载系统服务..."
    systemctl daemon-reload || handle_error "重载系统服务失败"

    # 挂载RAID
    log "挂载RAID..."
    mount "$RAID_DEVICE" "$MOUNT_POINT" || handle_error "挂载失败"

    # 保存RAID配置
    log "保存RAID配置..."
    mkdir -p /etc/mdadm
    mdadm --detail --scan >> /etc/mdadm/mdadm.conf || handle_error "保存RAID配置失败"
    update-initramfs -u || handle_error "更新initramfs失败"

    # 最终检查
    final_check

    exit 0

}

# 执行主程序
trap rollback ERR
main