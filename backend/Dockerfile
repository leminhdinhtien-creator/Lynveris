FROM python:3.12-slim
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1
WORKDIR /app
COPY requirements.lock ./requirements.lock
RUN pip install -r requirements.lock
COPY . .
RUN pip install --no-deps . && useradd --create-home --uid 10001 lynveris
USER lynveris
EXPOSE 8000
CMD ["uvicorn", "lynveris.api:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log", "--no-proxy-headers"]
