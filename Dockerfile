FROM python:3.11-slim AS runtime

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY src ./src
RUN useradd --uid 10001 --no-create-home appuser && chown -R appuser:appuser /app
USER 10001
EXPOSE 8080
CMD ["uvicorn", "src.predictor.app:app", "--host", "0.0.0.0", "--port", "8080"]
