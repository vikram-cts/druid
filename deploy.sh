#!/bin/bash

APP_NAME="metrix_druid_master"
ENV_NAME="dev"
PRODUCT_COMPONENT="$APP_NAME"
DENV=$ENV_NAME

echo "###################################################"
echo "Starting deployment for: $PRODUCT_COMPONENT"
echo "Environment:          $ENV_NAME"
START_TIME=$(date)
echo "Time:                 $START_TIME"
echo "###################################################"

base_dir="/opt/talech"
cd "$base_dir/build/" 

# Download secrets from Secrets Manager
echo "Fetching secrets from AWS Secrets Manager..."
python3 secrets_download.py

# Load local Docker image only if not already present
echo "----------------------------------------------------"
EXPECTED_IMAGE="artifact-build-obc.us.bank-dns.com:5008/talech/druid-image:495aeb56"

if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${EXPECTED_IMAGE}$"; then
  echo "Docker image '${EXPECTED_IMAGE}' already loaded — skipping docker load."
else
  if [ -f "${base_dir}/build/image.tar" ]; then
    echo "Docker image not found locally. Loading from image.tar..."
    sudo docker load -i "${base_dir}/build/image.tar"
  else
    echo "image.tar not found in ${base_dir}/build — cannot load image."
    exit 1
  fi
fi

# Show available images
echo "----------------------------------------------------"
echo "Available Docker images after load:"
docker images
echo "----------------------------------------------------"

# Start containers using docker-compose
echo "Starting containers using docker-compose..."
docker-compose -f docker-compose.yml up -d

# Retry once after 60s (in case some containers were slow to initialize)
echo "Waiting 60 seconds before verifying container startup..."
sleep 60
sudo docker-compose -f docker-compose.yml up -d

echo "----------------------------------------------------"
echo "Deployment complete!"
echo "----------------------------------------------------"
END_TIME=$(date)
echo "Completed at: $END_TIME"