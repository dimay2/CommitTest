FROM python:3.9-slim
WORKDIR /app
COPY . .
RUN pip install flask requests && \
    useradd -m appuser
USER appuser
CMD ["python", "front_app.py"]