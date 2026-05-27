#!/bin/bash

# 1. Gather user information
echo "--- Invoice System Setup ---"
read -p "Enter your domain (e.g. invoice.yourdomain.com): " DOMAIN

# 2. Create required directory structure
echo "Initializing directories..."
mkdir -p ./nginx/ssl
mkdir -p ./invoice_app_backend/backups
mkdir -p ./invoice_app_frontend/build/web
mkdir -p ./invoice_app_frontend/build/app/outputs/apk/release

# 3. Check for SSL certificate files
if [ ! -f "./nginx/ssl/fullchain.pem" ] || [ ! -f "./nginx/ssl/privkey.pem" ]; then
    echo "⚠️ WARNING: SSL files (fullchain.pem and privkey.pem) from Cloudflare are missing in ./nginx/ssl/"
    echo "Please place the files there and re-run this script!"
    exit 1
fi

# 4. Update nginx.conf with the new domain
echo "Configuring Nginx..."
cp ./nginx/nginx.conf.template ./nginx/nginx.conf
sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" ./nginx/nginx.conf

echo "--- DONE! ---"