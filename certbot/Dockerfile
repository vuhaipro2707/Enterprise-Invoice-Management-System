FROM certbot/dns-cloudflare
# Add curl, openssl, and jq for Docker REST API and DDNS Cloudflare updates
RUN apk add --no-cache curl openssl jq

# Copy scripts into the image
COPY entrypoint.sh /entrypoint.sh
COPY deploy.sh /deploy.sh
COPY ddns.sh /ddns.sh

# Ensure they have execution permissions
RUN chmod +x /entrypoint.sh /deploy.sh /ddns.sh

