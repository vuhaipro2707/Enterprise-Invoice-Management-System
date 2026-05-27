#!/bin/sh
set -e

# === Create Cloudflare credentials file from env ===
mkdir -p /cloudflare
cat > /cloudflare/cloudflare.ini << EOF
dns_cloudflare_api_token = ${CLOUDFLARE_API_TOKEN}
EOF
chmod 600 /cloudflare/cloudflare.ini


echo "=== Certbot DNS Challenge (Cloudflare) ==="
echo "  Domain : ${DOMAIN}"
echo "  Email       : ${CERTBOT_EMAIL}"
echo ""

# === Issue certificate if not already exists ===
CERT_PATH="/etc/letsencrypt/live/${DOMAIN}"
NGINX_SSL_PATH="/etc/nginx/ssl"

# Helper to check if the certificate in Nginx SSL is a dummy self-signed one
is_dummy_cert() {
    if [ -f "${NGINX_SSL_PATH}/fullchain.pem" ]; then
        # Check if the issuer/subject contains "localhost" (which setup.sh generates)
        if openssl x509 -in "${NGINX_SSL_PATH}/fullchain.pem" -text -noout | grep -qi "localhost"; then
            return 0 # is dummy
        fi
    fi
    return 1 # not dummy (or doesn't exist)
}

if [ -f "${NGINX_SSL_PATH}/fullchain.pem" ] && [ -f "${NGINX_SSL_PATH}/privkey.pem" ] && ! is_dummy_cert; then
    echo "✅ Found pre-existing real certificates in Nginx SSL directory (e.g. copied from backup/old server)."
    echo "   Skipping initial certificate issuance, proceeding straight to auto-renewal loop."
elif [ -f "${CERT_PATH}/fullchain.pem" ]; then
    echo "✅ Existing Certbot certificate found in local storage, skipping initial issuance."
else
    if is_dummy_cert; then
        echo "💡 Temporary dummy certificate detected. Replacing it with a real Let's Encrypt certificate..."
    else
        echo "📋 No existing certificate found anywhere. Requesting new certificate from Let's Encrypt..."
    fi
    
    certbot certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /cloudflare/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 60 \
        --non-interactive \
        --agree-tos \
        --email "${CERTBOT_EMAIL}" \
        -d "${DOMAIN}" \
        -d "api.${DOMAIN}"
    echo "✅ Certificate issued successfully."
fi

# === Deploy certs to nginx/ssl on startup ===
/deploy.sh

# === Start renewal loop (every 12h) ===
echo ""
echo "🔄 Starting auto-renewal loop (checks every 12h)..."
trap "exit 0" TERM INT
while :; do
    sleep 12h & wait $!
    echo "🔄 Running certbot renew..."
    certbot renew \
        --dns-cloudflare \
        --dns-cloudflare-credentials /cloudflare/cloudflare.ini \
        --dns-cloudflare-propagation-seconds 60 \
        --quiet \
        --deploy-hook "/deploy.sh"
done
