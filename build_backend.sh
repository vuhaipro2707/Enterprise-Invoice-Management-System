#!/bin/bash
# build_backend.sh
# Usage: Called from cd_ssh.sh (REMOTE_SERVER and REMOTE_PATH must be set)
# Or run standalone: ./build_backend.sh <deploy_docker_image> [remote_server] [remote_path]

DEPLOY_DOCKER_IMAGE="${DEPLOY_DOCKER_IMAGE:-$1}"
REMOTE_SERVER="${REMOTE_SERVER:-$2}"
REMOTE_PATH="${REMOTE_PATH:-$3}"

if [ -z "$DEPLOY_DOCKER_IMAGE" ]; then
    echo "❌ ERROR: DEPLOY_DOCKER_IMAGE is not set. Aborting."
    exit 1
fi

PUSH=true
if [ -z "$REMOTE_SERVER" ] || [ -z "$REMOTE_PATH" ]; then
    PUSH=false
fi

if [ "$PUSH" = true ]; then
    echo "--- Backend Docker Build & Push ---"
else
    echo "--- Backend Docker Build (Local Only) ---"
fi
echo "Image tag: $DEPLOY_DOCKER_IMAGE"
echo ""

BUILD_IMAGE=true
if docker image inspect "$DEPLOY_DOCKER_IMAGE" >/dev/null 2>&1; then
    read -p "Docker image $DEPLOY_DOCKER_IMAGE already exists locally. Rebuild backend? (y/N): " CONFIRM_DOCKER
    echo ""
    if [[ ! "$CONFIRM_DOCKER" =~ ^[Yy]$ ]]; then
        BUILD_IMAGE=false
    fi
fi

if [ "$BUILD_IMAGE" = true ]; then
    if [ "$PUSH" = true ]; then
        echo "Building backend for linux/amd64 and pushing to registry..."
        docker buildx build --platform linux/amd64 -t "$DEPLOY_DOCKER_IMAGE" ./invoice_app_backend --push
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to build and push Docker image."
            exit 1
        fi
        echo "✅ Docker image built and pushed."
    else
        echo "Building backend locally (no push)..."
        docker build -t "$DEPLOY_DOCKER_IMAGE" ./invoice_app_backend
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to build Docker image locally."
            exit 1
        fi
        echo "✅ Docker image built locally."
    fi
else
    echo "⏭  Skipping backend rebuild."
    if [ "$PUSH" = true ]; then
        echo "Pushing existing local Docker image to registry..."
        docker push "$DEPLOY_DOCKER_IMAGE"
        if [ $? -ne 0 ]; then
            echo "❌ ERROR: Failed to push existing Docker image. Check your Docker daemon and login status."
            exit 1
        fi
        echo "✅ Existing Docker image pushed."
    else
        echo "ℹ️  Local mode only. Skipping push."
    fi
fi
echo ""
