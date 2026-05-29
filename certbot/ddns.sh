#!/bin/sh

# Exit immediately if any required variable is missing
if [ -z "$DOMAIN" ] || [ -z "$CLOUDFLARE_API_TOKEN" ]; then
    echo "❌ [DDNS] DOMAIN or CLOUDFLARE_API_TOKEN is not set. Skipping DDNS update."
    exit 1
fi

ROOT_DOMAIN=$(echo "$DOMAIN" | awk -F. '{print $(NF-1)"."$NF}')
API_DOMAIN="api.${DOMAIN}"
LAST_IP=""

echo "🔄 [DDNS] Initializing DDNS update for ${API_DOMAIN} (Root domain: ${ROOT_DOMAIN})"

while :; do
    # Fetch public IP
    IP=$(curl -s --max-time 10 https://api.ipify.org || curl -s --max-time 10 https://ifconfig.me || curl -s --max-time 10 https://icanhazip.com)
    
    # Strip any whitespace/newlines
    IP=$(echo "$IP" | tr -d '[:space:]')

    if [ -z "$IP" ]; then
        echo "⚠️  [DDNS] Failed to fetch public IP. Retrying in 5 minutes..."
        sleep 300 & wait $!
        continue
    fi

    if [ "$IP" = "$LAST_IP" ]; then
        # IP has not changed, sleep and check again
        sleep 300 & wait $!
        continue
    fi

    echo "🔍 [DDNS] Current public IP: ${IP} (Previous: ${LAST_IP:-None})"

    # Fetch Zone ID
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ROOT_DOMAIN}" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [ -z "$ZONE_ID" ] || [ "$ZONE_ID" = "null" ]; then
        echo "❌ [DDNS] Failed to find Cloudflare Zone ID for ${ROOT_DOMAIN}. Verify your domain or API token permissions."
        sleep 300 & wait $!
        continue
    fi

    # Fetch DNS Record ID for api.domain
    RECORD_RESPONSE=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?name=${API_DOMAIN}&type=A" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json")

    RECORD_ID=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].id')
    RECORD_IP=$(echo "$RECORD_RESPONSE" | jq -r '.result[0].content')

    if [ "$IP" = "$RECORD_IP" ]; then
        echo "✅ [DDNS] Cloudflare DNS record is already up-to-date (${IP})."
        LAST_IP="$IP"
        sleep 300 & wait $!
        continue
    fi

    if [ -n "$RECORD_ID" ] && [ "$RECORD_ID" != "null" ]; then
        # Update existing record
        echo "🔄 [DDNS] Updating DNS record for ${API_DOMAIN} to ${IP}..."
        UPDATE_RESPONSE=$(curl -s -X PUT "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records/${RECORD_ID}" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${API_DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")
        
        SUCCESS=$(echo "$UPDATE_RESPONSE" | jq -r '.success')
        if [ "$SUCCESS" = "true" ]; then
            echo "✅ [DDNS] Successfully updated ${API_DOMAIN} to ${IP}"
            LAST_IP="$IP"
        else
            ERROR_MSG=$(echo "$UPDATE_RESPONSE" | jq -r '.errors[0].message')
            echo "❌ [DDNS] Failed to update DNS record: ${ERROR_MSG}"
        fi
    else
        # Create new record
        echo "➕ [DDNS] DNS record not found. Creating new A record for ${API_DOMAIN} to ${IP}..."
        CREATE_RESPONSE=$(curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
            -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
            -H "Content-Type: application/json" \
            --data "{\"type\":\"A\",\"name\":\"${API_DOMAIN}\",\"content\":\"${IP}\",\"ttl\":120,\"proxied\":false}")
        
        SUCCESS=$(echo "$CREATE_RESPONSE" | jq -r '.success')
        if [ "$SUCCESS" = "true" ]; then
            echo "✅ [DDNS] Successfully created A record for ${API_DOMAIN} pointing to ${IP}"
            LAST_IP="$IP"
        else
            ERROR_MSG=$(echo "$CREATE_RESPONSE" | jq -r '.errors[0].message')
            echo "❌ [DDNS] Failed to create DNS record: ${ERROR_MSG}"
        fi
    fi

    # Wait for 5 minutes before checking again
    sleep 300 & wait $!
done
