# PowerShell script for Windows setup

# 1. Prompt user for information
Write-Host "--- Invoice System Configuration (Windows) ---"
$DOMAIN = Read-Host "Enter domain (e.g., invoice.ddns.net)"
$EMAIL = Read-Host "Enter email for SSL registration"

# 2. Create necessary directory structure
Write-Host "Initializing directories..."
New-Item -ItemType Directory -Force -Path ./nginx/ssl
New-Item -ItemType Directory -Force -Path ./nginx/ssl-lib
New-Item -ItemType Directory -Force -Path ./postgres_data
New-Item -ItemType Directory -Force -Path ./invoice_app_backend/db/sqlc
New-Item -ItemType Directory -Force -Path ./invoice_app_backend/db/queries

# 3. Get SSL certificate from Let's Encrypt (Standalone Mode)
Write-Host "Requesting SSL certificate for $DOMAIN..."
docker run -it --rm --name certbot `
  -v "${PWD}/nginx/ssl:/etc/letsencrypt" `
  -v "${PWD}/nginx/ssl-lib:/var/lib/letsencrypt" `
  -p 80:80 `
  certbot/certbot certonly --standalone `
  -d $DOMAIN --email $EMAIL --agree-tos --no-eff-email

# 4. Check if SSL cert was obtained
if (Test-Path "./nginx/ssl/live/$DOMAIN") {
    Write-Host "SSL certificate obtained successfully!"
} else {
    Write-Host "Error: SSL certificate not obtained. Check if port 80 is open."
    exit 1
}

# 5. Update nginx.conf based on new domain
# Create copy from template to actual file
Copy-Item ./nginx/nginx.conf.template ./nginx/nginx.conf

(Get-Content ./nginx/nginx.conf) -replace 'DOMAIN_PLACEHOLDER', $DOMAIN | Set-Content ./nginx/nginx.conf

# 6. Generate JWT secret key
python generate_jwt_key.py

# 7. Start the entire system
Write-Host "Starting Docker Compose..."
docker-compose up -d

Write-Host "--- COMPLETED! ---"
Write-Host "Access now: https://$DOMAIN"