FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install flask mysql-connector-python && \
    useradd -m appuser
USER appuser
CMD ["python", "back_app.py"]