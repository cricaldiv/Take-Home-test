FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY pipeline ./pipeline
COPY tests ./tests
ENV PYTHONPATH=/app PYTHONUNBUFFERED=1
CMD ["python", "-m", "pipeline.main", "demo"]
