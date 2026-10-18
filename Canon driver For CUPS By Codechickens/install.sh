#!/bin/bash

# Dừng lại ngay nếu có lỗi xảy ra
set -e

echo "==> [1/6] Cập nhật hệ thống và cài đặt các công cụ biên dịch trên Arch..."
omarchy update
sudo pacman -S --needed --noconfirm base-devel git cups autoconf automake libcups

echo "==> [2/6] Tải mã nguồn captdriver từ GitHub..."
if [ -d "captdriver" ]; then
    echo "Thư mục captdriver đã tồn tại, đang cập nhật..."
    cd captdriver
    git pull
else
    git clone https://github.com/mounaiban/captdriver.git
    cd captdriver
fi

echo "==> [3/6] Biên dịch, tạo file PPD và cài đặt captdriver..."
autoreconf -i
./configure
make
make ppd
sudo make install

# Đảm bảo CUPS tìm thấy filter rastertocapt trên Arch Linux
if [ -f /usr/local/bin/rastertocapt ]; then
    sudo ln -sf /usr/local/bin/rastertocapt /usr/lib/cups/filter/rastertocapt
    sudo chmod 755 /usr/lib/cups/filter/rastertocapt
fi

echo "==> [4/6] Sao chép file PPD vào thư mục model của CUPS..."
# Trên Arch, thư mục chứa các file mô hình ppd của CUPS thường là /usr/share/cups/model/
sudo mkdir -p /usr/share/cups/model/
sudo cp -f ppd/*.ppd /usr/share/cups/model/

# Quay lại thư mục ban đầu
cd ..

echo "==> [5/6] Đảm bảo dịch vụ CUPS đang chạy..."
sudo systemctl enable --now cups.service

echo "==> [6/6] Đăng ký máy in Canon LBP2900 vào CUPS..."
# Tự động tìm cổng USB của máy in
USB_URI=$(lpinfo -v | grep -i "usb://Canon/LBP2900" | head -n 1 | awk '{print $2}')

if [ -z "$USB_URI" ]; then
    echo "Cảnh báo: Không tìm thấy máy in kết nối qua USB. Dùng URI mặc định..."
    USB_URI="usb://Canon/LBP2900"
else
    echo "Đã tìm thấy máy in tại: $USB_URI"
fi

# Đăng ký máy in với CUPS sử dụng PPD vừa sinh ra
sudo lpadmin -p Canon_LBP2900 -v "$USB_URI" -E -P /usr/share/cups/model/CanonLBP-2900-3000.ppd
sudo systemctl restart cups.service

echo "==> Hoàn tất! Máy in Canon LBP2900 đã sẵn sàng trên Arch Linux."
