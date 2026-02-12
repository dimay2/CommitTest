ARG REGISTRY_URL
FROM ${REGISTRY_URL}/python:3.11-slim
WORKDIR /app
COPY . .
RUN pip install --no-index --find-links=packages flask requests && \
    useradd -m appuser
USER appuser
CMD ["python", "front_app.py"]