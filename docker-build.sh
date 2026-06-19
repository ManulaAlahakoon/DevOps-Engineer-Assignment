#!/bin/bash

set -e

# Set your Docker Hub username

DOCKER_USERNAME=${DOCKER_USERNAME:-your-dockerhub-username}

OCR_IMAGE="$DOCKER_USERNAME/ocr-model:latest"
GATEWAY_IMAGE="$DOCKER_USERNAME/api-gateway:latest"

case "$1" in

build)
echo "Building images..."
docker build -t $OCR_IMAGE -f ocr-model/Dockerfile ocr-model/
docker build -t $GATEWAY_IMAGE -f api-gateway/Dockerfile api-gateway/
;;

test)
echo "Creating network..."
docker network create ocr-network 2>/dev/null || true

echo "Starting OCR model..."
docker run -d --rm \
    --name ocr-model-container \
    --network ocr-network \
    -p 8080:8080 \
    $OCR_IMAGE

sleep 10

echo "Starting API gateway..."
docker run -d --rm \
    --name api-gateway-container \
    --network ocr-network \
    -p 8001:8001 \
    -e KSERVE_URL=http://ocr-model-container:8080/v2/models/ocr-model/infer \
    $GATEWAY_IMAGE

sleep 5

echo "Testing services..."
curl http://localhost:8080/v2/health/ready
curl http://localhost:8001/docs
;;

push)
docker login
docker push $OCR_IMAGE
docker push $GATEWAY_IMAGE
;;

clean)
docker rm -f ocr-model-container api-gateway-container 2>/dev/null || true
docker network rm ocr-network 2>/dev/null || true
;;

all)
$0 build
$0 test
$0 push
;;

*)
echo "Usage:"
echo "  ./docker-build.sh build"
echo "  ./docker-build.sh test"
echo "  ./docker-build.sh push"
echo "  ./docker-build.sh clean"
echo "  ./docker-build.sh all"
;;
esac
