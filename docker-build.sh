#!/bin/bash

# Docker Hub username
DOCKER_USERNAME="manulaalahakoon"

# Image names
OCR_IMAGE="$DOCKER_USERNAME/ocr-model:v2"
GATEWAY_IMAGE="$DOCKER_USERNAME/api-gateway:v2"

echo "Building OCR image..."
docker build -t $OCR_IMAGE -f ocr-model/Dockerfile ocr-model/

echo "Building API Gateway image..."
docker build -t $GATEWAY_IMAGE -f api-gateway/Dockerfile api-gateway/

echo "Creating Docker network..."
docker network create ocr-network-test-2

echo "Starting OCR Model container..."
docker run -d \
  --name ocr-model-container \
  --network ocr-network \
  -p 8080:8080 \
  $OCR_IMAGE

echo "Starting API Gateway container..."
docker run -d \
  --name api-gateway-container \
  --network ocr-network \
  -p 8001:8001 \
  -e KSERVE_URL=http://ocr-model-container:8080/v2/models/ocr-model/infer \
  $GATEWAY_IMAGE


echo "Logging into Docker Hub..."
docker login

echo "Pushing images to Docker Hub..."
docker push $OCR_IMAGE
docker push $GATEWAY_IMAGE

