# =============================================================================
# Dockerfile for the OCR Model Server (KServe + Tesseract)
#
# WHAT THIS FILE DOES:
#   Docker reads this file top to bottom and builds a container image.
#   A container image is like a snapshot of a mini computer that has
#   everything needed to run our OCR model — Python, libraries, and code.
#
# WHY TWO STAGES?
#   Stage 1 (builder) : installs Poetry and all Python packages
#   Stage 2 (final)   : copies only the installed packages — NOT Poetry itself
#   Result            : smaller and cleaner final image
#
# WHY python:3.11-slim?
#   - "slim" means minimal Debian Linux — only essential tools included
#   - Small image size (fewer security risks, faster downloads)
#   - Has apt-get so we can install Tesseract OCR
#   - Matches our pyproject.toml requirement: python = ">=3.11,<3.13"
# =============================================================================


# -----------------------------------------------------------------------------
# STAGE 1: Builder
# Purpose: Install all Python dependencies using Poetry
# This stage is temporary — it will NOT be in the final image
# -----------------------------------------------------------------------------
FROM python:3.11-slim AS builder

# Set the working directory inside the container
# All commands below will run from this folder
WORKDIR /app

# Install Poetry (Python package manager)
# --no-cache-dir means don't save the download cache (keeps image smaller)
RUN pip install --no-cache-dir poetry==1.8.2

# Copy dependency files BEFORE copying the actual code
# WHY? Docker caches each step (called a "layer")
# If pyproject.toml and poetry.lock don't change, Docker skips reinstalling
# packages and reuses the cache — this makes rebuilds much faster
COPY pyproject.toml poetry.lock ./

# Install Python packages defined in pyproject.toml
# virtualenvs.create false  → install directly, no virtual env needed in Docker
# --no-root                 → don't install our project itself as a package
# --only main               → skip any dev/test dependencies
RUN poetry config virtualenvs.create false && \
    poetry install --no-root --only main


# -----------------------------------------------------------------------------
# STAGE 2: Final Image
# Purpose: Create the actual container that will run our OCR model
# Only copies what is needed — does NOT include Poetry or build tools
# -----------------------------------------------------------------------------
FROM python:3.11-slim

# SECURITY: Create a non-root user called "appuser"
# By default containers run as root (admin) which is dangerous
# If someone hacks the container, they would have full system access
# Running as a normal user limits what an attacker can do
RUN groupadd -r appuser && useradd -r -g appuser appuser

# Install Tesseract OCR engine
# Tesseract is the actual OCR tool that reads text from images
# pytesseract (Python library) is just a wrapper that calls Tesseract
# --no-install-recommends → only install what's necessary (smaller image)
# apt-get clean + rm      → delete apt cache after install (smaller image)
RUN apt-get update && \
    apt-get install -y --no-install-recommends tesseract-ocr && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Set working directory for our application
WORKDIR /app

# Copy the installed Python packages from Stage 1 (builder)
# We copy packages but NOT Poetry itself — we don't need it to run the app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy our OCR model code into the container
COPY model.py .

# Give ownership of the /app folder to our non-root user
RUN chown -R appuser:appuser /app

# Switch from root to our non-root user for security
USER appuser

# Tell Docker this container listens on port 8080
# This is just documentation — it does not actually open the port
# You still need -p 8080:8080 when running docker run
EXPOSE 8080

# Health check: Docker will run this every 30 seconds
# to check if the service is still alive and working
# If it fails 3 times in a row, Docker marks the container as "unhealthy"
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/v2/health/ready')" || exit 1

# The command that runs when the container starts
CMD ["python", "model.py"]
