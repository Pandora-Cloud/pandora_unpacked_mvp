#!/bin/bash

# Ensure script runs from its own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change to script directory"; exit 1; }

# Define variables
BUCKET_NAME="chatbot-mvp-frontend"
REGION="us-west-2"
SOURCE_DIR="frontend"

# Check if frontend directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: $SOURCE_DIR directory not found. Run install_frontend.sh first."
    exit 1
fi

# Check if env.js has been populated
if grep -q 'window.REACT_APP_USER_POOL_ID = ""' "$SOURCE_DIR/js/env.js"; then
    echo "Warning: $SOURCE_DIR/js/env.js appears unpopulated."
    echo "Run 'cd $SOURCE_DIR && node fetch_ssm.js' to fetch SSM parameters before deploying."
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Sync files to S3 with appropriate content types
echo "Deploying frontend to s3://$BUCKET_NAME..."
aws s3 sync "$SOURCE_DIR/" "s3://$BUCKET_NAME/" \
    --region "$REGION" \
    --exclude "*" \
    --include "*.html" --content-type "text/html" \
    --include "*.css" --content-type "text/css" \
    --include "*.js" --content-type "application/javascript" \
    || { echo "Failed to sync files to S3"; exit 1; }

# Configure S3 bucket for static website hosting (if not already set)
echo "Configuring S3 bucket for static website hosting..."
aws s3 website "s3://$BUCKET_NAME/" \
    --index-document "index.html" \
    --error-document "index.html" \
    --region "$REGION" \
    || { echo "Warning: Failed to configure static website hosting (might already be set)"; }

# Output deployment details
ENDPOINT="http://$BUCKET_NAME.s3-website-$REGION.amazonaws.com"
echo "Frontend deployed successfully!"
echo "Test it at: $ENDPOINT"
echo "Note: If using a custom domain (e.g., https://chat.pandoracloud.net), ensure CloudFront is configured separately."
