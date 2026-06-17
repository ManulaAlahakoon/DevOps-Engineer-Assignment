#!/bin/bash
# commands.sh — Local Setup and Testing Script
# Separated into two independent services:
#   - ocr-model/     → KServe model server (port 8080)
#   - api-gateway/   → FastAPI gateway     (port 8001)

set -e  # Exit immediately on any error

# ==============================================================================
# SECTION 0: Install System Dependencies (Run once)
# ==============================================================================

install_system_deps() {
    echo ""
    echo ">>> [STEP 0] Installing system dependencies..."

    sudo apt update
    sudo apt install -y software-properties-common curl

    echo ">>> Adding deadsnakes PPA for Python 3.11..."
    sudo add-apt-repository ppa:deadsnakes/ppa -y
    sudo apt update

    sudo apt install -y python3.11 python3.11-venv python3.11-distutils python3-pip
    sudo apt install -y tesseract-ocr

    echo ""
    echo ">>> Python version:"
    python3.11 --version

    echo ">>> Tesseract version:"
    tesseract --version

    echo ">>> System dependencies installed successfully."
}

# ==============================================================================
# SECTION 1: Install Poetry (Run once)
# ==============================================================================

install_poetry() {
    echo ""
    echo ">>> [STEP 1] Installing Poetry..."
    curl -sSL https://install.python-poetry.org | python3 -
    export PATH="$HOME/.local/bin:$PATH"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    source ~/.bashrc
    echo ""
    echo ">>> Poetry version:"
    poetry --version
    echo ">>> Poetry installed successfully."
}

# ==============================================================================
# SECTION 2: Verify Project Folder Structure
# Works whether files are already in subfolders OR still in root
# ==============================================================================

setup_folders() {
    echo ""
    echo ">>> [STEP 2] Verifying project folder structure..."

    # Create folders if they don't exist
    mkdir -p ocr-model
    mkdir -p api-gateway

    # --- model.py ---
    if [ -f "ocr-model/model.py" ]; then
        echo ">>> ocr-model/model.py already exists ✅"
    elif [ -f "model.py" ]; then
        cp model.py ocr-model/model.py
        echo ">>> Copied model.py → ocr-model/ ✅"
    else
        echo "ERROR: model.py not found in ocr-project/ or ocr-model/"
        exit 1
    fi

    # --- api-gateway.py ---
    if [ -f "api-gateway/api-gateway.py" ]; then
        echo ">>> api-gateway/api-gateway.py already exists ✅"
    elif [ -f "api-gateway.py" ]; then
        cp api-gateway.py api-gateway/api-gateway.py
        echo ">>> Copied api-gateway.py → api-gateway/ ✅"
    else
        echo "ERROR: api-gateway.py not found in ocr-project/ or api-gateway/"
        exit 1
    fi

    # --- pyproject.toml for ocr-model ---
    if [ ! -f "ocr-model/pyproject.toml" ]; then
        echo "ERROR: ocr-model/pyproject.toml not found!"
        echo "       Download it from the files provided and place it in ocr-model/"
        exit 1
    else
        echo ">>> ocr-model/pyproject.toml exists ✅"
    fi

    # --- pyproject.toml for api-gateway ---
    if [ ! -f "api-gateway/pyproject.toml" ]; then
        echo "ERROR: api-gateway/pyproject.toml not found!"
        echo "       Download it from the files provided and place it in api-gateway/"
        exit 1
    else
        echo ">>> api-gateway/pyproject.toml exists ✅"
    fi

    echo ""
    echo "  ocr-project/"
    echo "  ├── ocr-model/"
    echo "  │   ├── model.py"
    echo "  │   └── pyproject.toml   (kserve, pillow, pytesseract)"
    echo "  ├── api-gateway/"
    echo "  │   ├── api-gateway.py"
    echo "  │   └── pyproject.toml   (fastapi, requests, python-multipart)"
    echo "  └── commands.sh"
    echo ""
    echo ">>> Folder structure verified and ready ✅"
}

# ==============================================================================
# SECTION 3: Install Dependencies for Each Service
# ==============================================================================

setup_env_model() {
    echo ""
    echo ">>> [STEP 3a] Setting up Python environment for ocr-model..."
    cd ocr-model
    poetry env use python3.11
    poetry install
    echo ""
    echo ">>> ocr-model environment info:"
    poetry env info
    cd ..
    echo ">>> ocr-model environment ready ✅"
}

setup_env_gateway() {
    echo ""
    echo ">>> [STEP 3b] Setting up Python environment for api-gateway..."
    cd api-gateway
    poetry env use python3.11
    poetry install
    echo ""
    echo ">>> api-gateway environment info:"
    poetry env info
    cd ..
    echo ">>> api-gateway environment ready ✅"
}

# ==============================================================================
# SECTION 4: Fix Gateway URL for Local Testing
# ==============================================================================

fix_gateway_url() {
    echo ""
    echo ">>> [STEP 4] Patching api-gateway.py URL for local testing..."
    echo "    Changing 'ocr-model-container' -> 'localhost'"
    echo ""
    sed -i 's|http://ocr-model-container:8080|http://localhost:8080|g' api-gateway/api-gateway.py
    echo ">>> Verified change:"
    grep "KSERVE_URL" api-gateway/api-gateway.py
    echo ">>> URL patched successfully ✅"
}

# ==============================================================================
# SECTION 5: Run KServe Model Server — Terminal 1
# ==============================================================================

run_model_server() {
    echo ""
    echo ">>> [Terminal 1] Starting KServe OCR Model Server on port 8080..."
    echo ">>> Keep this terminal open!"
    cd ocr-model
    poetry run python model.py
}

# ==============================================================================
# SECTION 6: Run FastAPI Gateway — Terminal 2
# ==============================================================================

run_gateway() {
    echo ""
    echo ">>> [Terminal 2] Starting FastAPI Gateway on port 8001..."
    echo ">>> Keep this terminal open!"
    cd api-gateway
    poetry run python api-gateway.py
}

# ==============================================================================
# SECTION 7: Health Checks — Terminal 3
# ==============================================================================

health_check() {
    echo ""
    echo ">>> Checking ocr-model server (port 8080)..."
    curl -s http://localhost:8080/v2/health/ready && echo "" || echo "ocr-model NOT running! ❌"

    echo ""
    echo ">>> Checking api-gateway (port 8001)..."
    curl -s http://localhost:8001/docs > /dev/null \
        && echo "api-gateway is UP ✅" \
        || echo "api-gateway NOT running! ❌"
}

# ==============================================================================
# SECTION 8: Test OCR via curl
# Usage: ./commands.sh test_ocr /path/to/image.png
# ==============================================================================

test_ocr() {
    IMAGE_PATH="${1:-}"
    if [ -z "$IMAGE_PATH" ] || [ ! -f "$IMAGE_PATH" ]; then
        echo "ERROR: Provide a valid image path."
        echo "Usage: ./commands.sh test_ocr /path/to/your/image.png"
        exit 1
    fi
    echo ""
    echo ">>> Sending OCR request: $IMAGE_PATH"
    curl -s -X POST http://localhost:8001/gateway/ocr \
        -F "image_file=@${IMAGE_PATH}" \
        | python3 -m json.tool
}

# ==============================================================================
# POSTMAN INSTRUCTIONS
# ==============================================================================

postman_instructions() {
    echo ""
    echo "============================================================"
    echo "  POSTMAN TESTING INSTRUCTIONS"
    echo "============================================================"
    echo "  1. Open Postman"
    echo "  2. Click [New] → [HTTP Request]"
    echo "  3. Method : POST"
    echo "  4. URL    : http://localhost:8001/gateway/ocr"
    echo "  5. Click [Body] tab → select [form-data]"
    echo "  6. KEY    : image_file"
    echo "     TYPE   : change 'Text' → 'File' (dropdown on right)"
    echo "     VALUE  : click 'Select Files' → pick an image with text"
    echo "  7. Click [Send]"
    echo ""
    echo "  Expected 200 OK Response:"
    echo "  {"
    echo "    \"model_name\": \"ocr-model\","
    echo "    \"id\": \"<uuid>\","
    echo "    \"outputs\": [{"
    echo "      \"name\": \"output-0\","
    echo "      \"datatype\": \"BYTES\","
    echo "      \"data\": \"<extracted text from your image>\""
    echo "    }]"
    echo "  }"
    echo "============================================================"
}

# ==============================================================================
# MAIN — Full first-time setup
# ==============================================================================

main() {
    echo ""
    echo "============================================================"
    echo "  OCR Project — Full Local Setup"
    echo "============================================================"
    install_system_deps
    install_poetry
    setup_folders
    setup_env_model
    setup_env_gateway
    fix_gateway_url
    postman_instructions
    echo ""
    echo "============================================================"
    echo "  Setup Complete! Now open 3 terminals and run:"
    echo "  Terminal 1:  ./commands.sh run_model_server"
    echo "  Terminal 2:  ./commands.sh run_gateway"
    echo "  Terminal 3:  ./commands.sh health_check"
    echo "  Terminal 3:  ./commands.sh test_ocr /path/to/image.png"
    echo "============================================================"
}

# ==============================================================================
# Entry point
# ==============================================================================
COMMAND="${1:-main}"
case "$COMMAND" in
    install_system_deps)  install_system_deps ;;
    install_poetry)       install_poetry ;;
    setup_folders)        setup_folders ;;
    setup_env_model)      setup_env_model ;;
    setup_env_gateway)    setup_env_gateway ;;
    fix_gateway_url)      fix_gateway_url ;;
    run_model_server)     run_model_server ;;
    run_gateway)          run_gateway ;;
    health_check)         health_check ;;
    test_ocr)             test_ocr "$2" ;;
    postman_instructions) postman_instructions ;;
    main)                 main ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run ./commands.sh for full setup, or use a specific command."
        exit 1
        ;;
esac
