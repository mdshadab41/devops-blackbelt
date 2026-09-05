# Stage 1
FROM python:3.11-slim AS builder
WORKDIR /app
ENV PYTHONUSERBASE=/install
COPY requirements.txt .
RUN pip install --user -r requirements.txt

# Stage 2
FROM python:3.11-alpine
WORKDIR /app
RUN apk add --no-cache curl
COPY --from=builder /install /home/appuser/.local
COPY app.py .
RUN adduser -D appuser && chown -R appuser:appuser /app /home/appuser
USER appuser
ENV PATH=/home/appuser/.local/bin:$PATH
ENV PYTHONPATH=/home/appuser/.local/lib/python3.11/site-packages
HEALTHCHECK --interval=30s --timeout=3s CMD curl -f http://localhost:5000/health || exit 1
CMD ["python3", "app.py"]
