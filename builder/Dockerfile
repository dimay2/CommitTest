ARG REGISTRY_URL=docker.io/library
FROM ${REGISTRY_URL}/amazonlinux:2023

# Install Docker, Git, and build tools
RUN dnf update -y && \
    dnf install -y docker git unzip tar gzip openssl python3-pip && \
    dnf clean all

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf aws awscliv2.zip

# Install kubectl (v1.30)
RUN curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl && \
    chmod +x ./kubectl && \
    mv ./kubectl /usr/local/bin/

# Install Helm (v3)
RUN curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && \
    chmod 700 get_helm.sh && \
    ./get_helm.sh && \
    rm get_helm.sh

# Download Python dependencies for air-gapped application builds
# Backend Dependencies
RUN mkdir -p /dependencies/backend && \
    pip3 download -d /dependencies/backend \
    flask \
    mysql-connector-python \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.11 \
    --implementation cp \
    --abi cp311

# Frontend Dependencies
RUN mkdir -p /dependencies/frontend && \
    pip3 download -d /dependencies/frontend \
    flask \
    requests \
    --platform manylinux2014_x86_64 \
    --only-binary=:all: \
    --python-version 3.11 \
    --implementation cp \
    --abi cp311