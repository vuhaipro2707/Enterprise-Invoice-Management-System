#!/bin/sh
# Called by certbot --deploy-hook after successful renewal,
# and also manually on container startup.
#
# certbot sets $RENEWED_LINEAGE when called as deploy-hook.
# On manual call, we fall back to computing the path from $DOMAIN.

ROOT_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
CERT_DIR="${RENEWED_LINEAGE:-/etc/letsencrypt/live/${DOMAIN}}"

echo "📋 Deploying certificates from: ${CERT_DIR}"

if [ -f "${CERT_DIR}/fullchain.pem" ] && [ -f "${CERT_DIR}/privkey.pem" ]; then
    cp "${CERT_DIR}/fullchain.pem" /etc/nginx/ssl/fullchain.pem
    cp "${CERT_DIR}/privkey.pem"   /etc/nginx/ssl/privkey.pem
    echo "✅ Certs saved to /etc/nginx/ssl/"

    # Signal Nginx to reload via Docker REST API (Unix socket)
    echo "🔄 Sending reload signal to Nginx..."
    curl -sf --unix-socket /var/run/docker.sock \
        -X POST "http://localhost/containers/invoice_gateway/kill?signal=HUP" \
        && echo "✅ Nginx reload signal sent (HUP)." \
        || echo "⚠️  Could not signal Nginx (may not be running yet — cert will still be applied on next start)."
else
    echo "⚠️  WARNING: Certificate files not found in ${CERT_DIR} yet."
    echo "   (This is normal during the initial startup while Let's Encrypt DNS verification is still in progress.)"
fi
