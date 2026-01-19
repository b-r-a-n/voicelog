FROM python:3.12-slim

WORKDIR /app

# Install dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir .

# Copy application code
COPY app/ app/

# Create data directories
RUN mkdir -p /data/transcripts /data/exports

# Set environment variables
ENV DATABASE_PATH=/data/voicelog.db
ENV STORAGE_PATH=/data/transcripts
ENV EXPORT_PATH=/data/exports

EXPOSE 8000

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
