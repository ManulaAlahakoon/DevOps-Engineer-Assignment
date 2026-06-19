# =============================================================================
# Dockerfile for the API Gateway (FastAPI)
#
# WHAT THIS FILE DOES:
#   Builds a container image for the FastAPI gateway service.
#   This gateway sits between the user and the OCR model:
#     User → sends image to Gateway → Gateway forwards to OCR Model → returns text
#
# WHY TWO STAGES? (same reason as ocr-model Dockerfile)
#   Stage 1 (builder) : installs Poetry and all Python packages
#   Stage 2 (final)   : copies only the installed packages — NOT Poetry
#   Result            : smaller and cleaner final image
#
# WHY python:3.11-slim?
#   - Same base image as ocr-model for consistency
#   - No system packages needed (unlike ocr-model which needs Tesseract)
#   - Small, secure, fast to download
#
# HOW DOES THE GATEWAY KNOW WHERE THE OCR MODEL IS?
#   We use an environment variable called KSERVE_URL
#   This means we can use the SAME image in different environments:
#     Local testing  → KSERVE_URL=http://localhost:8080/...
#     Docker         → KSERVE_URL=http://ocr-model-container:8080/...
#     Kubernetes     → KSERVE_URL=http://ocr-model-service:8080/...
#   No need to rebuild the image for each environment!
# =============================================================================


# -----------------------------------------------------------------------------
# STAGE 1: Builder
# Purpose: Install all Python dependencies using Poetry
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Set working directory inside the container
WORKDIR /app

# Install Poetry
RUN pip install --no-cache-dir poetry==1.8.2

# Copy dependency files BEFORE the actual code
# This way Docker caches the installed packages
# and only reinstalls them if pyproject.toml or poetry.lock changes
COPY pyproject.toml poetry.lock ./

# Install Python packages
# virtualenvs.create false  → no virtual env needed inside Docker
# --no-root                 → don't install our project as a package
# --only main               → skip dev dependencies
RUN poetry config virtualenvs.create false && \
    poetry install --no-root --only main


# -----------------------------------------------------------------------------
# STAGE 2: Final Image
# Purpose: Lightweight container that runs the FastAPI gateway
# -----------------------------------------------------------------------------
FROM python:3.11-slim

# SECURITY: Create a non-root user
# Running containers as root is dangerous — use a regular user instead
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Set working directory
WORKDIR /app

# Copy installed Python packages from Stage 1
# Only the packages are copied — Poetry itself is left behind
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy our gateway code into the container
COPY api-gateway.py .

# Give ownership of /app to our non-root user
RUN chown -R appuser:appuser /app

# Switch to non-root user for security
USER appuser

# Tell Docker this container listens on port 8001
EXPOSE 8001

# Set the default URL for the OCR model server
# This points to the ocr-model container on the Docker network
# You can override this when running the container with:
#   docker run -e KSERVE_URL=http://other-host:8080/... 
ENV KSERVE_URL="http://ocr-model-container:8080/v2/models/ocr-model/infer"

# Health check: verifies the FastAPI gateway is responding
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8001/docs')" || exit 1

# Start the FastAPI gateway when the container runs
CMD ["python", "api-gateway.py"]
