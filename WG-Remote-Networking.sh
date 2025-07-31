#!/bin/bash
# WireGuard 纯组网管理脚本
# 功能：异地组网（不修改默认路由/NAT）
# 特点：固定使用 wg0 接口和 10.8.0.x 网段

set -e

# ===== 配置区域 =====
# 网络配置
INTERFACE="wg0"
SUBNET="10.8.0"
SERVER_IP="${SUBNET}.1"
SERVER_PORT="51820"
SUBNET_MASK="24"

# 目录和文件配置
WG_DIR="/etc/wireguard"
CLIENTS_DIR="$WG_DIR/clients"
FIRST_RUN_FILE="$WG_DIR/.first_run"
CONFIG_FILE="$WG_DIR/$INTERFACE.conf"

# 功能配置
DNS_SERVERS="1.1.1.1, 8.8.8.8"  # 客户端DNS服务器，多个用逗号分隔
KEEPALIVE_INTERVAL="25"         # 保活间隔（秒）
IP_RANGE_START="2"              # IP地址分配起始值
IP_RANGE_END="254"              # IP地址分配结束值

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color
# ===== 配置区域结束 =====

# 打印函数
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 用户运行此脚本！"
        exit 1
    fi
}

# 检测包管理器
detect_pkg_manager() {
    if command -v apt &> /dev/null; then
        echo "apt"
    elif command -v yum &> /dev/null; then
        echo "yum"
    else
        print_error "不支持的系统：未找到 apt 或 yum"
        exit 1
    fi
}

# 检查软件包是否安装
is_package_installed() {
    local pkg=$1
    local pkg_manager=$(detect_pkg_manager)
    if [[ "$pkg_manager" == "apt" ]]; then
        dpkg -l | grep -q "^ii  $pkg "
    else
        rpm -qa | grep -q "^$pkg"
    fi
}

# 安装单个软件包
install_package() {
    local pkg=$1
    local pkg_manager=$(detect_pkg_manager)
    if is_package_installed "$pkg"; then
        return 0
    else
        print_warning "$pkg 未安装，正在安装..."
        if [[ "$pkg_manager" == "apt" ]]; then
            apt update >/dev/null 2>&1 && apt install -y "$pkg" >/dev/null 2>&1
        else
            yum install -y "$pkg" >/dev/null 2>&1
        fi
        if is_package_installed "$pkg"; then
            print_success "$pkg 安装完成！"
        else
            print_error "$pkg 安装失败！"
            exit 1
        fi
    fi
}

# 首次运行安装依赖
first_run_setup() {
    if [[ ! -f "$FIRST_RUN_FILE" ]]; then
        print_info "首次运行，正在安装依赖..."
        local dependencies=(wireguard-tools curl iproute2)
        for pkg in "${dependencies[@]}"; do
            install_package "$pkg"
        done
        # 检查可选组件qrencode
        if ! command -v qrencode &> /dev/null; then
            print_warning "qrencode 未安装，二维码生成功能将不可用"
        fi
        mkdir -p "$CLIENTS_DIR"
        chmod 700 "$CLIENTS_DIR"
        touch "$FIRST_RUN_FILE"
        print_success "初始化完成！"
    fi
}

# 生成随机IP
generate_random_ip() {
    local last_octet=$((IP_RANGE_START + RANDOM % (IP_RANGE_END - IP_RANGE_START + 1)))
    echo "$SUBNET.$last_octet"
}

# 检查IP是否被占用
check_ip_used() {
    local ip=$1
    if grep -q "AllowedIPs = $ip" "$CONFIG_FILE" 2>/dev/null; then
        return 0
    fi
    return 1
}

# 初始化接口
init_interface() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        local server_private_key=$(wg genkey)
        local server_public_key=$(echo "$server_private_key" | wg pubkey)
        
        cat > "$CONFIG_FILE" << EOF
[Interface]
PrivateKey = $server_private_key
Address = $SERVER_IP/$SUBNET_MASK
ListenPort = $SERVER_PORT
EOF
        chmod 600 "$CONFIG_FILE"
        print_success "已创建接口 $INTERFACE！"
    fi
}

# 添加客户端
add_client() {
    local client_name=$1
    local client_ip=$2
    
    # 检查客户端是否已存在
    if [[ -f "$CLIENTS_DIR/$client_name.conf" ]]; then
        print_error "客户端 $client_name 已存在！"
        exit 1
    fi
    
    # 自动分配IP
    if [[ -z "$client_ip" ]]; then
        while true; do
            client_ip=$(generate_random_ip)
            if ! check_ip_used "$client_ip"; then
                break
            fi
        done
        print_info "自动分配 IP: $client_ip"
    fi
    
    # 检查IP冲突
    if check_ip_used "$client_ip"; then
        print_error "IP $client_ip 已被占用！"
        exit 1
    fi
    
    # 初始化接口
    init_interface
    
    # 生成客户端密钥
    local client_private_key=$(wg genkey)
    local client_public_key=$(echo "$client_private_key" | wg pubkey)
    
    # 添加客户端到服务端配置
    cat >> "$CONFIG_FILE" << EOF
[Peer]
# $client_name
PublicKey = $client_public_key
AllowedIPs = $client_ip/32
EOF
    
    # 生成客户端配置
    local server_public_key=$(grep -m1 "PrivateKey" "$CONFIG_FILE" | awk '{print $3}' | wg pubkey)
    local server_public_ip=$(curl -s ifconfig.me)
    
    cat > "$CLIENTS_DIR/$client_name.conf" << EOF
[Interface]
PrivateKey = $client_private_key
Address = $client_ip/$SUBNET_MASK
DNS = $DNS_SERVERS

[Peer]
PublicKey = $server_public_key
Endpoint = $server_public_ip:$SERVER_PORT
AllowedIPs = $SUBNET.0/$SUBNET_MASK  
PersistentKeepalive = $KEEPALIVE_INTERVAL
EOF
    
    # 生成二维码（如果可用）
    if command -v qrencode &> /dev/null; then
        qrencode -t ansiutf8 < "$CLIENTS_DIR/$client_name.conf"
        print_info "客户端二维码已生成"
    fi
    
    chmod 600 "$CLIENTS_DIR/$client_name.conf"
    
    # 重启接口应用配置
    if systemctl is-active --quiet "wg-quick@$INTERFACE"; then
        wg syncconf "$INTERFACE" <(wg-quick strip "$INTERFACE")
    else
        systemctl enable --now "wg-quick@$INTERFACE"
    fi
    
    print_success "客户端 $client_name 添加成功！"
    print_info "配置文件: $CLIENTS_DIR/$client_name.conf"
    print_info "IP: $client_ip"
}

# 删除客户端
delete_client() {
    local client_name=$1
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "接口 $INTERFACE 不存在！"
        exit 1
    fi
    
    # 从服务端配置删除
    sed -i "/# $client_name$/,+3d" "$CONFIG_FILE"
    
    # 删除客户端文件
    rm -f "$CLIENTS_DIR/$client_name.conf"
    
    # 应用配置变更
    wg syncconf "$INTERFACE" <(wg-quick strip "$INTERFACE")
    
    print_success "客户端 $client_name 已删除！"
}

# 完全卸载
uninstall_wireguard() {
    print_warning "即将卸载 WireGuard，所有配置将被删除！"
    
    # 停止所有接口
    systemctl stop "wg-quick@$INTERFACE" >/dev/null 2>&1 || true
    systemctl disable "wg-quick@$INTERFACE" >/dev/null 2>&1 || true
    
    # 卸载软件包
    local pkg_manager=$(detect_pkg_manager)
    if [[ "$pkg_manager" == "apt" ]]; then
        apt remove --purge -y wireguard wireguard-tools >/dev/null 2>&1
    else
        yum remove -y wireguard-tools >/dev/null 2>&1
    fi
    
    # 清理配置
    rm -rf "$WG_DIR/"
    
    print_success "WireGuard 已完全卸载！"
}

# 显示帮助
show_help() {
    echo -e "${GREEN}WireGuard 纯组网管理脚本${NC}"
    echo "固定使用 wg0 接口和 10.8.0.x 网段"
    echo "用法: $0 [选项] <参数>"
    echo
    echo "选项:"
    echo "  -a <客户端名> [IP]  添加客户端（IP可选，自动分配10.8.0.x地址）"
    echo "  -d <客户端名>      删除客户端"
    echo "  --uninstall        完全卸载 WireGuard"
    echo "  -h, --help        显示帮助"
    echo
    echo "示例:"
    echo "  $0 -a laptop       # 添加客户端"
    echo "  $0 -d laptop       # 删除客户端"
    exit 0
}

# 主程序
main() {
    check_root
    first_run_setup  # 首次运行检查依赖
    
    case "$1" in
        -a|--add)
            [[ $# -lt 2 ]] && { print_error "缺少参数！用法: $0 -a <客户端名> [IP]"; exit 1; }
            add_client "$2" "$3"
            ;;
        -d|--delete)
            [[ $# -lt 2 ]] && { print_error "缺少参数！用法: $0 -d <客户端名>"; exit 1; }
            delete_client "$2"
            ;;
        --uninstall)
            uninstall_wireguard
            ;;
        -h|--help)
            show_help
            ;;
        *)
            print_error "未知选项！使用 -h 查看帮助。"
            exit 1
            ;;
    esac
}

main "$@"
