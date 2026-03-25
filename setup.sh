#!/bin/bash

# 1. Hỏi thông tin người dùng
echo "--- Cấu hình Hệ thống Hóa đơn (Mini PC) ---"
read -p "Nhập tên miền (VD: invoice.ddns.net): " DOMAIN
read -p "Nhập Email để đăng ký SSL: " EMAIL

# 2. Tạo cấu trúc thư mục cần thiết
echo "Đang khởi tạo thư mục..."
mkdir -p ./nginx/ssl
mkdir -p ./nginx/ssl-lib
mkdir -p ./postgres_data

# 3. Lấy chứng chỉ SSL từ Let's Encrypt (Standalone Mode)
echo "Đang yêu cầu chứng chỉ SSL cho $DOMAIN..."
docker run -it --rm --name certbot \
  -v "$(pwd)/nginx/ssl:/etc/letsencrypt" \
  -v "$(pwd)/nginx/ssl-lib:/var/lib/letsencrypt" \
  -p 80:80 \
  certbot/certbot certonly --standalone \
  -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# 4. Kiểm tra xem Cert đã về chưa
if [ -d "./nginx/ssl/live/$DOMAIN" ]; then
    echo "SSL đã được cấp thành công!"
else
    echo "Lỗi: Không lấy được SSL. Kiểm tra xem Port 80 đã mở chưa."
    exit 1
fi

# 5. Cập nhật file nginx.conf theo tên miền mới
# Tạo bản sao từ template ra file thật
cp ./nginx/nginx.conf.template ./nginx/nginx.conf

sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" ./nginx/nginx.conf

# 6. Khởi động toàn bộ hệ thống
echo "Đang khởi động Docker Compose..."
docker-compose up -d

echo "--- HOÀN TẤT! ---"
echo "Truy cập ngay: https://$DOMAIN"