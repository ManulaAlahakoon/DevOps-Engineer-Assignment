#!/bin/bash
# =============================================================================
# docker-build.sh — Build, Test, and Push Docker Images
#
# WHAT THIS SCRIPT DOES:
#   Automates the entire Docker workflow for both services:
#     1. Build  → creates Docker images from Dockerfiles
#     2. Test   → runs both containers locally and checks they work
#     3. Push   → uploads images to Docker Hub
#     4. Clean  → removes containers and images from your machine
#
# HOW TO USE:
#   ./docker-build.sh build              → build both images
#   ./docker-build.sh test               → run and test both containers
#   ./docker-build.sh test_ocr image.png → send a test image via curl
#   ./docker-build.sh push               → push images to Docker Hub
#   ./docker-build.sh clean              → remove all containers and images
#   ./docker-build.sh all                → build + test + push in one go
#
# BEFORE RUNNING:
#   Set your Docker Hub username:
#     export DOCKER_USERNAME="your-dockerhub-username"
#   Or edit the line below directly.
# =============================================================================

# Stop the script immediately if any command fails
set -e

# =============================================================================
# CONFIGURATION
# Change "your-dockerhub-username" to your actual Docker Hub username
# =============================================================================

# Read DOCKER_USERNAME from environment, or use the default below
DOCKER_USERNAME="${DOCKER_USERNAME:-your-dockerhub-username}"

# Image names on Docker Hub (username/imagename)
OCR_MODEL_IMAGE="$DOCKER_USERNAME/ocr-model"
GATEWAY_IMAGE="$DOCKER_USERNAME/api-gateway"

# Tag for the images — "latest" means the most recent version
IMAGE_TAG="latest"

# Names for the running containers (used in docker run and docker rm)
OCR_MODEL_CONTAINER="ocr-model-container"
GATEWAY_CONTAINER="api-gateway-container"

# Docker network name — containers on the same network can talk to each other
# by using their container name as the hostname
NETWORK_NAME="ocr-network"


# =============================================================================
# BUILD FUNCTION
# Builds Docker images for both services from their Dockerfiles
# =============================================================================
build() {
    echo ""
    echo "============================================================"
    echo "  Building Docker Images"
    echo "============================================================"

    # Build the OCR model image
    # -t  → tag (name) for the image
    # -f  → path to the Dockerfile
    # Last argument → build context (folder with files to copy into image)
    echo ""
    echo ">>> Building ocr-model image..."
    docker build \
        -t $OCR_MODEL_IMAGE:$IMAGE_TAG \
        -f ocr-model/Dockerfile \
        ocr-model/
    echo ">>> ocr-model image built ✅"

    # Build the API gateway image
    echo ""
    echo ">>> Building api-gateway image..."
    docker build \
        -t $GATEWAY_IMAGE:$IMAGE_TAG \
        -f api-gateway/Dockerfile \
        api-gateway/
    echo ">>> api-gateway image built ✅"

    # Show the built images
    echo ""
    echo ">>> Images on your machine:"
    docker images | grep -E "$DOCKER_USERNAME|REPOSITORY"
}


# =============================================================================
# TEST FUNCTION
# Runs both containers locally and verifies they are working
#
# HOW CONTAINERS COMMUNICATE:
#   We create a Docker network called "ocr-network"
#   Both containers join this network
#   The gateway uses the container name "ocr-model-container" as hostname
#   Docker automatically resolves this to the correct IP inside the network
# =============================================================================
test() {
    echo ""
    echo "============================================================"
    echo "  Testing Docker Images Locally"
    echo "============================================================"

    # Remove any old containers from previous test runs
    echo ">>> Cleaning up any old containers..."
    docker rm -f $OCR_MODEL_CONTAINER $GATEWAY_CONTAINER 2>/dev/null || true
    docker network rm $NETWORK_NAME 2>/dev/null || true

    # Create a private Docker network for our containers
    # Containers on the same network can reach each other by container name
    echo ">>> Creating Docker network: $NETWORK_NAME..."
    docker network create $NETWORK_NAME

    # -------------------------------------------------------------------------
    # Start the OCR model container
    # -d              → run in background (detached mode)
    # --name          → give the container a name
    # --network       → connect to our Docker network
    # -p 8080:8080    → map host port 8080 to container port 8080
    #                   format: -p HOST_PORT:CONTAINER_PORT
    # -------------------------------------------------------------------------
    echo ""
    echo ">>> Starting ocr-model container..."
    docker run -d \
        --name $OCR_MODEL_CONTAINER \
        --network $NETWORK_NAME \
        -p 8080:8080 \
        $OCR_MODEL_IMAGE:$IMAGE_TAG
    echo ">>> ocr-model container started ✅"

    # Wait for the OCR model to finish starting up
    # KServe takes a few seconds to initialize
    echo ">>> Waiting for ocr-model to be ready..."
    sleep 10
    for i in {1..10}; do
        if curl -s http://localhost:8080/v2/health/ready > /dev/null 2>&1; then
            echo ">>> ocr-model is ready ✅"
            break
        fi
        echo "    Still starting... ($i/10)"
        sleep 5
    done

    # -------------------------------------------------------------------------
    # Start the API gateway container
    # -e KSERVE_URL   → set environment variable inside the container
    #                   tells the gateway where to find the OCR model
    #                   uses the container name as hostname (Docker DNS)
    # -------------------------------------------------------------------------
    echo ""
    echo ">>> Starting api-gateway container..."
    docker run -d \
        --name $GATEWAY_CONTAINER \
        --network $NETWORK_NAME \
        -p 8001:8001 \
        -e KSERVE_URL="http://$OCR_MODEL_CONTAINER:8080/v2/models/ocr-model/infer" \
        $GATEWAY_IMAGE:$IMAGE_TAG
    echo ">>> api-gateway container started ✅"

    # Give the gateway a moment to start
    echo ">>> Waiting for api-gateway to be ready..."
    sleep 5

    # -------------------------------------------------------------------------
    # Health checks — verify both services are responding
    # -------------------------------------------------------------------------
    echo ""
    echo ">>> Running health checks..."

    echo ""
    echo "--- ocr-model health check (port 8080) ---"
    curl -s http://localhost:8080/v2/health/ready && echo "" \
        || echo "❌ ocr-model is not responding"

    echo ""
    echo "--- api-gateway health check (port 8001) ---"
    curl -s http://localhost:8001/docs > /dev/null \
        && echo "api-gateway is UP ✅" \
        || echo "❌ api-gateway is not responding"

    echo ""
    echo ">>> Both containers are running!"
    echo ">>> Test with Postman  : POST http://localhost:8001/gateway/ocr"
    echo ">>> Test with curl     : ./docker-build.sh test_ocr /path/to/image.png"
    echo ""
    echo ">>> Running containers:"
    docker ps --filter "name=$OCR_MODEL_CONTAINER" --filter "name=$GATEWAY_CONTAINER"
}


# =============================================================================
# TEST OCR FUNCTION
# Sends a real image to the gateway and prints the extracted text
# Usage: ./docker-build.sh test_ocr /path/to/your/image.png
# =============================================================================
test_ocr() {
    IMAGE_PATH="${1:-}"

    # Check that an image path was provided and the file exists
    if [ -z "$IMAGE_PATH" ] || [ ! -f "$IMAGE_PATH" ]; then
        echo "ERROR: Please provide a valid image file path."
        echo "Usage: ./docker-build.sh test_ocr /path/to/your/image.png"
        exit 1
    fi

    echo ""
    echo ">>> Sending image to OCR gateway: $IMAGE_PATH"

    # Send the image as a multipart form upload (same as Postman form-data)
    # -F "image_file=@path" → @ means attach the file at that path
    # python3 -m json.tool  → formats the JSON response nicely
    curl -s -X POST http://localhost:8001/gateway/ocr \
        -F "image_file=@${IMAGE_PATH}" \
        | python3 -m json.tool

    echo ""
    echo ">>> OCR test complete."
}


# =============================================================================
# PUSH FUNCTION
# Uploads both images to your Docker Hub repository
#
# BEFORE RUNNING:
#   1. Create a free account at hub.docker.com
#   2. Set DOCKER_USERNAME at the top of this script
#   3. Have your Docker Hub password ready
# =============================================================================
push() {
    echo ""
    echo "============================================================"
    echo "  Pushing Images to Docker Hub"
    echo "============================================================"

    # Log in to Docker Hub — it will ask for username and password
    echo ">>> Logging in to Docker Hub..."
    docker login

    # Push the OCR model image to Docker Hub
    echo ""
    echo ">>> Pushing ocr-model image to Docker Hub..."
    docker push $OCR_MODEL_IMAGE:$IMAGE_TAG
    echo ">>> ocr-model image pushed ✅"

    # Push the API gateway image to Docker Hub
    echo ""
    echo ">>> Pushing api-gateway image to Docker Hub..."
    docker push $GATEWAY_IMAGE:$IMAGE_TAG
    echo ">>> api-gateway image pushed ✅"

    echo ""
    echo ">>> Your images are now on Docker Hub:"
    echo "    $OCR_MODEL_IMAGE:$IMAGE_TAG"
    echo "    $GATEWAY_IMAGE:$IMAGE_TAG"
}


# =============================================================================
# CLEAN FUNCTION
# Removes all containers, the network, and images from your machine
# Useful for starting fresh or freeing up disk space
# =============================================================================
clean() {
    echo ""
    echo ">>> Stopping and removing containers..."
    docker rm -f $OCR_MODEL_CONTAINER $GATEWAY_CONTAINER 2>/dev/null || true

    echo ">>> Removing Docker network..."
    docker network rm $NETWORK_NAME 2>/dev/null || true

    echo ">>> Removing Docker images..."
    docker rmi $OCR_MODEL_IMAGE:$IMAGE_TAG $GATEWAY_IMAGE:$IMAGE_TAG 2>/dev/null || true

    echo ">>> Cleanup complete ✅"
}


# =============================================================================
# ALL FUNCTION
# Runs build + test + push in sequence
# =============================================================================
all() {
    build
    test
    push
}


# =============================================================================
# ENTRY POINT
# Reads the first argument and calls the matching function
# If no argument given, runs "all" by default
# =============================================================================
COMMAND="${1:-all}"

case "$COMMAND" in
    build)    build ;;
    test)     test ;;
    test_ocr) test_ocr "$2" ;;
    push)     push ;;
    clean)    clean ;;
    all)      all ;;
    *)
        echo "Unknown command: $COMMAND"
        echo ""
        echo "Usage: ./docker-build.sh [command]"
        echo ""
        echo "Commands:"
        echo "  build              Build both Docker images"
        echo "  test               Run and test both containers locally"
        echo "  test_ocr <image>   Send a test image and see extracted text"
        echo "  push               Push images to Docker Hub"
        echo "  clean              Remove all containers and images"
        echo "  all                Build + test + push"
        exit 1
        ;;
esac
