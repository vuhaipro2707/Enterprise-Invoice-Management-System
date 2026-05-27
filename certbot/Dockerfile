FROM certbot/dns-cloudflare
# Add curl to call Docker REST API via socket (for nginx reload)
RUN apk add --no-cache curl openssl

# Copy scripts into the image
COPY entrypoint.sh /entrypoint.sh
COPY deploy.sh /deploy.sh

# Ensure they have execution permissions
RUN chmod +x /entrypoint.sh /deploy.sh

