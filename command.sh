#!/bin/bash

echo "OCR Project Local Setup"
echo ""

echo "Installing Poetry..."
curl -sSL https://install.python-poetry.org | python3 -

echo ""
echo "Installing OCR Service dependencies..."
cd ocr-model
poetry install

cd ..

echo ""
echo "Installing API Gateway dependencies..."
cd api-gateway
poetry install

cd ..

echo ""
echo "Setup completed successfully!"
echo ""

kill -9 $(lsof -t -i:8001)
kill -9 $(lsof -t -i:8080)

echo "Starting OCR Service..."
cd ocr-model
poetry run python model.py &

cd ..

echo "Starting API Gateway..."
cd api-gateway
poetry run python api-gateway.py &


