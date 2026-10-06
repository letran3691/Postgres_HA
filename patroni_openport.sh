#!/bin/bash

# Script sẽ nhận danh sách IP từ tham số hoặc biến môi trường
IP_NODES=("$@")  # Nhận danh sách IP từ arguments

if [ ${#IP_NODES[@]} -eq 0 ]; then
    echo "ERROR: No IP addresses provided"
    exit 1
fi

# Tìm interface ens*
interface=$(ip -brief addr show | grep ens | awk '{print $1}' | head -n1)

if [ -z "$interface" ]; then
    echo "ERROR: No ens* interface found"
    exit 1
fi

echo "Using interface: $interface"

# Kiểm tra zone đã tồn tại chưa
if sudo firewall-cmd --get-zones | grep -q p-pg; then
    echo "Zone p-pg already exists, updating..."
else
    echo "Creating zone p-pg..."
    sudo firewall-cmd --permanent --new-zone=p-pg
fi

# Gán interface cho zone
#sudo firewall-cmd --permanent --zone=p-pg --add-interface=$interface 2>/dev/null || echo "Interface already added"

# Thêm service/port cần thiết
sudo firewall-cmd --permanent --zone=p-pg --add-service=postgresql 2>/dev/null || echo "Service postgresql already added"
sudo firewall-cmd --permanent --zone=p-pg --add-port=8008/tcp 2>/dev/null || echo "Port 8008 already added"
sudo firewall-cmd --permanent --zone=p-pg --add-port=2379/tcp 2>/dev/null || echo "Port 2379 already added"
sudo firewall-cmd --permanent --zone=p-pg --add-port=2380/tcp 2>/dev/null || echo "Port 2380 already added"

# Thêm VRRP rule
sudo firewall-cmd --permanent --zone=p-pg --add-rich-rule='rule protocol value="vrrp" accept' 2>/dev/null || echo "VRRP rule already added"

# Thêm các source IP
for ip_node in "${IP_NODES[@]}"; do
    echo "Adding source: $ip_node/32"
    sudo firewall-cmd --permanent --zone=p-pg --add-source="$ip_node"/32 2>/dev/null || echo "Source $ip_node already added"
done

# Reload và hiển thị kết quả
sudo firewall-cmd --reload
echo "=== Final configuration for zone p-pg ==="
sudo firewall-cmd --list-all --zone=p-pg
