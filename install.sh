#!/bin/bash

# 设置变量
MihomoDir="/etc/mihomo"
DistFile1="mihomo-linux-amd64-alpha-c7661d7.gz"
DistFile2="compressed-dist.tgz"
ConfigFile="config.yaml"
CountryFile="Country.mmdb"

# 检查并安装必要工具
echo "检查依赖工具..."
sudo apt update
sudo apt install -y curl tar gzip lsb-release net-tools

# 检查 /etc/mihomo 是否存在
if [ -d "$MihomoDir" ]; then
    read -p "$MihomoDir 已存在，是否覆盖？[y/N]: " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "取消安装"
        exit 0
    fi
    echo "正在覆盖 $MihomoDir ..."
    sudo rm -rf "$MihomoDir"
fi

# 创建目录
echo "创建目录 $MihomoDir..."
sudo mkdir -p "$MihomoDir"

# 停止正在运行的 mihomo
echo "尝试终止正在运行的 mihomo..."
pid=$(pgrep mihomo)
if [ -n "$pid" ]; then
    sudo kill -9 "$pid"
fi

# 解压 mihomo 主程序
echo "解压 $DistFile1..."
if [ -f "$DistFile1" ]; then
    gunzip -c "$DistFile1" | sudo tee "$MihomoDir/mihomo" > /dev/null
    sudo chmod +x "$MihomoDir/mihomo"
else
    echo "❌ 未找到 $DistFile1，跳过"
fi

# 解压 UI 资源
echo "解压 UI 文件 $DistFile2..."
if [ -f "$DistFile2" ]; then
    sudo mkdir -p "$MihomoDir/ui"
    sudo tar -xvzf "$DistFile2" -C "$MihomoDir/ui"
else
    echo "❌ 未找到 $DistFile2，跳过"
fi

# 复制配置文件
[ -f "$ConfigFile" ] && sudo cp "$ConfigFile" "$MihomoDir/" || echo "⚠️ config.yaml 未找到，跳过"
[ -f "$CountryFile" ] && sudo cp "$CountryFile" "$MihomoDir/" || echo "⚠️ Country.mmdb 未找到，跳过"

# 创建 systemd 服务
echo "写入 mihomo systemd 服务..."
sudo tee /etc/systemd/system/mihomo.service > /dev/null << EOF
[Unit]
Description=mihomo Daemon
After=network.target NetworkManager.service systemd-networkd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=$MihomoDir/mihomo -d $MihomoDir
ExecReload=/bin/kill -HUP \$MAINPID

[Install]
WantedBy=multi-user.target
EOF

# 启用并启动服务
sudo systemctl daemon-reload
sudo systemctl enable mihomo
sudo systemctl start mihomo

# 创建控制脚本
echo "创建 clash 控制脚本..."
sudo tee "$MihomoDir/clash_control.sh" > /dev/null << 'EOF'
#!/bin/bash
function clashon() {
    sudo systemctl start mihomo && echo '✅ 代理已开启' || echo '❌ 启动失败，请检查 systemctl status mihomo'
    export http_proxy=http://127.0.0.1:7890
    export https_proxy=http://127.0.0.1:7890
    export HTTP_PROXY=http://127.0.0.1:7890
    export HTTPS_PROXY=http://127.0.0.1:7890
}
function clashoff() {
    sudo systemctl stop mihomo && echo '🛑 代理已关闭' || echo '❌ 关闭失败'
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
}
function clashui() {
    local local_ip=$(hostname -I | awk '{print $1}')
    local public_ip=$(curl -s ifconfig.me)
    local port=7890
    echo "📡 内网 UI: http://$local_ip:$port/ui"
    echo "🌍 公网 UI: http://$public_ip:$port/ui"
}
EOF

# 设置执行权限
sudo chmod +x "$MihomoDir/clash_control.sh"

# 添加到当前用户 bashrc
echo "添加代理控制命令到 ~/.bashrc..."
if ! grep -q "source $MihomoDir/clash_control.sh" ~/.bashrc; then
    echo "source $MihomoDir/clash_control.sh" >> ~/.bashrc
    source ~/.bashrc
fi

# 启动代理
clashon

echo -e "\n🎉 安装完成！使用以下命令控制代理："
echo "- 启用代理: \e[1mclashon\e[0m"
echo "- 关闭代理: \e[1mclashoff\e[0m"
echo "- 查看 UI 地址: \e[1mclashui\e[0m"
