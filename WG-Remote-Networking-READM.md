# WireGuard 纯组网管理脚本

## 简介

这是一个用于WireGuard异地组网的Bash管理脚本，专注于提供简单的点对点网络连接，不修改默认路由或NAT设置。脚本固定使用`wg0`接口和`10.8.0.x`网段，简化了WireGuard的配置和管理过程。

## 功能特点

- 简单易用的命令行界面
- 自动安装依赖和初始化配置
- 固定使用`wg0`接口和`10.8.0.x`网段
- 自动分配客户端IP地址（可手动指定）
- 支持生成客户端配置二维码（需安装qrencode）
- 不修改系统默认路由，纯组网应用
- 支持完全卸载WireGuard

## 系统要求

- Linux系统
- root权限
- 支持apt或yum包管理器的系统
- WireGuard内核支持（大多数现代Linux发行版已包含）

## 安装与使用

1. 下载脚本并赋予执行权限：
   ```bash
   wget https://example.com/wg-manager.sh
   chmod +x wg-manager.sh
   ```

2. 运行脚本（首次运行会自动安装依赖）：
   ```bash
   ./wg-manager.sh [选项] [参数]
   ```

## 命令参数

| 选项 | 参数 | 描述 |
|------|------|------|
| `-a` 或 `--add` | `<客户端名> [IP]` | 添加客户端（IP可选，不指定则自动分配） |
| `-d` 或 `--delete` | `<客户端名>` | 删除指定客户端 |
| `--uninstall` | 无 | 完全卸载WireGuard及相关配置 |
| `-h` 或 `--help` | 无 | 显示帮助信息 |

### 使用示例

```bash
# 添加客户端（自动分配IP）
./wg-manager.sh -a laptop

# 添加客户端（指定IP）
./wg-manager.sh -a phone 10.8.0.10

# 删除客户端
./wg-manager.sh -d laptop

# 显示帮助
./wg-manager.sh -h

# 完全卸载WireGuard
./wg-manager.sh --uninstall
```

## 配置说明

脚本默认使用以下配置，如需修改请编辑脚本中的配置区域：

- **接口名称**: wg0
- **子网**: 10.8.0.0/24
- **服务器IP**: 10.8.0.1
- **监听端口**: 51820
- **DNS服务器**: 1.1.1.1, 8.8.8.8
- **保活间隔**: 25秒
- **IP分配范围**: 10.8.0.2 - 10.8.0.254

## 配置文件位置

- **服务端配置**: `/etc/wireguard/wg0.conf`
- **客户端配置**: `/etc/wireguard/clients/<客户端名>.conf`

## 常见问题

### Q: 如何查看当前已添加的客户端？
A: 可以通过查看服务端配置文件获取：
```bash
cat /etc/wireguard/wg0.conf | grep "# "
```

### Q: 如何连接到WireGuard网络？
A: 将生成的客户端配置文件（位于`/etc/wireguard/clients/`目录）导入到WireGuard客户端即可。

### Q: 二维码功能如何使用？
A: 系统需要安装`qrencode`包，添加客户端时会自动生成二维码，可用于移动设备快速导入配置。

### Q: 如何修改默认配置？
A: 编辑脚本中的配置区域（标记为`# ===== 配置区域 =====`的部分），然后重新运行脚本。

### Q: 脚本支持哪些Linux发行版？
A: 支持使用apt或yum作为包管理器的Linux发行版，如Ubuntu、Debian、CentOS、RHEL等。

## 注意事项

- 脚本必须以root权限运行
- 首次运行会自动安装必要的依赖包
- 卸载功能会删除所有WireGuard配置，请谨慎使用
- 确保服务器防火墙已开放UDP 51820端口
- 如果服务器有多个网络接口，可能需要手动指定公网IP

## 贡献

欢迎提交Issue和Pull Request来改进此脚本。
