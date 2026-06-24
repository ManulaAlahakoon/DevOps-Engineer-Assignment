
# Dockerfile for OCR Model Server

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

# Install Tesseract OCR engine

RUN apt-get update && \
    apt-get install -y tesseract-ocr

# Set working directory
WORKDIR /app

# Copy installed Python packages from builder stage
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages

# Copy Python executables
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application source code
COPY model.py .

# Give ownership to non-root user
RUN chown -R appuser:appuser /app

# Run as non-root user
USER appuser

# Application listens on port 8080
EXPOSE 8080

# Start OCR model server
CMD ["python", "model.py"]
