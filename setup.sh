#!/bin/bash

# 1. Load environment variables from root .env file
echo "--- Loading environment variables from .env ---"
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "❌ ERROR: .env file not found in root directory!"
    exit 1
fi

# Validate required variables
if [ -z "$DOMAIN" ]; then
    echo "❌ ERROR: DOMAIN variable is not defined or is empty in .env!"
    exit 1
fi

# 2. Create required directory structure
echo "Initializing directories..."
mkdir -p ./nginx/ssl
mkdir -p ./nginx/letsencrypt
mkdir -p ./invoice_app_backend/backups
mkdir -p ./invoice_app_frontend/build/web
mkdir -p ./invoice_app_frontend/build/app/outputs/flutter-apk

# 3. Check for SSL certificate files, create dummy self-signed certs if missing
if [ ! -f "./nginx/ssl/fullchain.pem" ] || [ ! -f "./nginx/ssl/privkey.pem" ]; then
    echo "💡 INFO: SSL files not found in ./nginx/ssl/. Generating temporary self-signed dummy certificates..."
    echo "   (This prevents Nginx from failing at startup. Certbot will automatically replace them soon!)"
    
    # Generate temporary key and self-signed cert using openssl
    openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "./nginx/ssl/privkey.pem" \
        -out "./nginx/ssl/fullchain.pem" \
        -subj "/CN=localhost"
    
    echo "✅ Temporary dummy certificates created."
fi

# 4. Update nginx.conf with the new domain
echo "Configuring Nginx for domain: $DOMAIN"
cp ./nginx/nginx.conf.template ./nginx/nginx.conf

# macOS requires a backup extension (even empty "") for sed -i, whereas Linux does not
if [[ "$OSTYPE" == "darwin"* ]]; then
    sed -i "" "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" ./nginx/nginx.conf
else
    sed -i "s|DOMAIN_PLACEHOLDER|$DOMAIN|g" ./nginx/nginx.conf
fi

# 5. Configure invoice_app_frontend/.env for production build
echo "Configuring invoice_app_frontend/.env for production build with api.$DOMAIN..."
ENV_FILE="./invoice_app_frontend/.env"
KEY="API_URL"
VALUE="https://api.$DOMAIN:${DEPLOY_HTTPS_PORT:-27443}"

if [ -f "$ENV_FILE" ]; then
    TEMP_FILE="${ENV_FILE}.tmp"
    FOUND=0
    rm -f "$TEMP_FILE"
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^${KEY}= ]]; then
            echo "${KEY}=${VALUE}" >> "$TEMP_FILE"
            FOUND=1
        else
            echo "$line" >> "$TEMP_FILE"
        fi
    done < "$ENV_FILE"
    
    if [ $FOUND -eq 0 ]; then
        echo "${KEY}=${VALUE}" >> "$TEMP_FILE"
    fi
    mv "$TEMP_FILE" "$ENV_FILE"
else
    echo "${KEY}=${VALUE}" > "$ENV_FILE"
fi

echo "--- DONE! ---"