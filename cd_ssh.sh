#!/bin/bash

echo "--- Upload Config & SSL to Remote Server ---"

# 1. Check root .env exists first
if [ ! -f "./.env" ]; then
    echo "❌ ERROR: Root .env (./.env) not found. Please create it from env.example. Aborting."
    exit 1
fi

# Load connection info from root .env
echo "Loading deployment config from root .env..."
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ ! "$line" =~ ^# ]] && [[ -n "$line" ]]; then
        if [[ "$line" =~ ^([^=]+)=(.*)$ ]]; then
            key="${BASH_REMATCH[1]}"
            value="${BASH_REMATCH[2]}"
            key=$(echo "$key" | xargs)
            value=$(echo "$value" | xargs)
            export "$key"="$value"
        fi
    fi
done < "./.env"

# Fallback/prompt if not set in .env
if [ -z "$REMOTE_SERVER" ]; then
    read -p "Enter remote server (e.g. user@192.168.1.100): " REMOTE_SERVER
fi

if [ -z "$REMOTE_PATH" ]; then
    read -p "Enter source code path on remote server (e.g. /home/user/Invoice_App): " REMOTE_PATH
fi

if [ -z "$DOMAIN" ]; then
    read -p "Enter your domain (e.g. invoice.yourdomain.com): " DOMAIN
fi

echo ""
echo "Target  : $REMOTE_SERVER:$REMOTE_PATH"
echo "Domain  : $DOMAIN"
echo ""

# 1.5 Prepare backend env & run generate_jwt_key.py
if [ ! -f "./invoice_app_backend/.env" ]; then
    if [ -f "./invoice_app_backend/.env.example" ]; then
        echo "⚠️ ./invoice_app_backend/.env not found. Creating from env.example..."
        cp ./invoice_app_backend/.env.example ./invoice_app_backend/.env
    else
        echo "❌ ERROR: ./invoice_app_backend/.env not found. Aborting."
        exit 1
    fi
fi

if [ -f "./generate_jwt_key.py" ]; then
    echo "Running generate_jwt_key.py to ensure secure JWT Secret..."
    python3 ./generate_jwt_key.py || python ./generate_jwt_key.py
    if [ $? -ne 0 ]; then
        echo "⚠️ Warning: Failed to execute generate_jwt_key.py. Proceeding with existing config..."
    fi
fi

# 2. Check that local files exist before uploading
echo "Checking local files..."

if [ ! -f "./invoice_app_backend/.env" ]; then
    echo "❌ ERROR: ./invoice_app_backend/.env not found. Aborting."
    exit 1
fi

if [ ! -f "./invoice_app_frontend/.env" ]; then
    echo "❌ ERROR: ./invoice_app_frontend/.env not found. Aborting."
    exit 1
fi

if [ ! -f "./nginx/ssl/fullchain.pem" ] || [ ! -f "./nginx/ssl/privkey.pem" ]; then
    echo "❌ ERROR: SSL files (fullchain.pem and/or privkey.pem) not found in ./nginx/ssl/. Aborting."
    exit 1
fi

if [ ! -f "./invoice_app_frontend/pubspec.yaml" ]; then
    echo "❌ ERROR: ./invoice_app_frontend/pubspec.yaml not found. Aborting."
    exit 1
fi

echo "✅ Local files OK."
echo ""

# 3. Create remote directories if they don't exist
echo "Ensuring remote directories exist..."
ssh "$REMOTE_SERVER" "mkdir -p $REMOTE_PATH/invoice_app_backend && mkdir -p $REMOTE_PATH/nginx/ssl && mkdir -p $REMOTE_PATH/invoice_app_frontend"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to create remote directories. Check your SSH connection."
    exit 1
fi

# 4. Upload .env files
echo "Uploading invoice_app_backend/.env..."
scp ./invoice_app_backend/.env "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_backend/.env"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload backend .env file."
    exit 1
fi

echo "Uploading root .env..."
scp ./.env "$REMOTE_SERVER:$REMOTE_PATH/.env"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload root .env file."
    exit 1
fi

echo "Uploading invoice_app_frontend/.env..."
scp ./invoice_app_frontend/.env "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_frontend/.env"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload frontend .env file."
    exit 1
fi

echo "✅ .env files uploaded."

# 5. Upload SSL certificates
echo "Uploading nginx/ssl/fullchain.pem..."
scp ./nginx/ssl/fullchain.pem "$REMOTE_SERVER:$REMOTE_PATH/nginx/ssl/fullchain.pem"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload fullchain.pem."
    exit 1
fi

echo "Uploading nginx/ssl/privkey.pem..."
scp ./nginx/ssl/privkey.pem "$REMOTE_SERVER:$REMOTE_PATH/nginx/ssl/privkey.pem"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload privkey.pem."
    exit 1
fi
echo "✅ SSL certificates uploaded."

# 5.5 Upload pubspec.yaml file
echo "Uploading invoice_app_frontend/pubspec.yaml..."
scp ./invoice_app_frontend/pubspec.yaml "$REMOTE_SERVER:$REMOTE_PATH/invoice_app_frontend/pubspec.yaml"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload pubspec.yaml."
    exit 1
fi
echo "✅ pubspec.yaml uploaded."

echo ""

# ─── CONFIG FRONTEND .ENV FOR PRODUCTION ──────────────────────────────────────
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

# ─── FLUTTER BUILD & UPLOAD ───────────────────────────────────────────────────
REMOTE_SERVER="$REMOTE_SERVER" REMOTE_PATH="$REMOTE_PATH" bash ./build_flutter.sh
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Flutter build/upload step failed."
    exit 1
fi

# 6. Upload deployment scripts and docker configs from local
echo "Uploading deployment configurations..."

echo "Uploading setup.sh..."
scp ./setup.sh "$REMOTE_SERVER:$REMOTE_PATH/setup.sh"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload setup.sh."
    exit 1
fi

echo "Uploading docker-compose.prod.yml..."
scp ./docker-compose.prod.yml "$REMOTE_SERVER:$REMOTE_PATH/docker-compose.prod.yml"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload docker-compose.prod.yml."
    exit 1
fi

echo "Uploading nginx/nginx.conf.template..."
ssh "$REMOTE_SERVER" "mkdir -p $REMOTE_PATH/nginx"
scp ./nginx/nginx.conf.template "$REMOTE_SERVER:$REMOTE_PATH/nginx/nginx.conf.template"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload nginx.conf.template."
    exit 1
fi
echo "✅ Configuration files uploaded."
echo ""

# 7. Run setup.sh on remote server (pass domain non-interactively)
echo "Running setup.sh on remote server..."
ssh "$REMOTE_SERVER" "cd $REMOTE_PATH && echo '$DOMAIN' | bash setup.sh"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: setup.sh failed on remote server."
    exit 1
fi
echo "✅ setup.sh done."
echo ""

# 8. Pull remote images and restart Docker (no local build)
echo "Pulling remote Docker images and restarting containers..."
ssh "$REMOTE_SERVER" "cd $REMOTE_PATH && docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml down && docker compose -f docker-compose.prod.yml up -d --force-recreate"
if [ $? -ne 0 ]; then
    echo "❌ ERROR: Docker Compose pull & restart failed."
    exit 1
fi
echo "✅ Docker Compose is up and running with the latest pulled images."

echo ""
echo "--- DONE! Remote server is updated and running: $REMOTE_SERVER:$REMOTE_PATH ---"
