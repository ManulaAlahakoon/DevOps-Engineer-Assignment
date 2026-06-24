
# Dockerfile for API Gateway

# DESIGN DECISIONS:
# 1. Base Image
#    - Uses python:3.11-slim because it is lightweight and already contains Python.
#
# 2. Security
#    - Runs the application as a non-root user.
#
# 3. Build Optimization
#    - Uses a multi-stage build.
#    - Copies dependency files first so Docker can cache dependencies.

# STAGE 1: Install Dependencies
FROM python:3.11-slim AS builder

# Set working directory
WORKDIR /app

# Install Poetry
RUN pip install poetry

# Copy dependency files only
COPY pyproject.toml poetry.lock ./

# Install project dependencies
RUN poetry config virtualenvs.create false && \
    poetry install --no-root

# STAGE 2: Runtime Image

FROM python:3.11-slim

# Create non-root user
RUN useradd -m appuser

# Set working directory
WORKDIR /app

# Copy installed Python packages from builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# Copy Python executables
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application source code
COPY api-gateway.py .

# Give ownership to non-root user
RUN chown -R appuser:appuser /app

# Run as non-root user
USER appuser

# OCR model endpoint
ENV KSERVE_URL=http://ocr-model-container:8080/v2/models/ocr-model/infer

# Application listens on port 8001
EXPOSE 8001

# Start FastAPI gateway
CMD ["python", "api-gateway.py"]
