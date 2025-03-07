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

# Sync files to S3 with appropriate content types - one type at a time for clarity
echo "Deploying frontend to s3://$BUCKET_NAME/..."

# HTML files
aws s3 sync "$SOURCE_DIR/" "s3://$BUCKET_NAME/" \
    --region "$REGION" \
    --include "*.html" \
    --exclude "*" \
    --content-type "text/html" \
    --acl public-read

# CSS files
aws s3 sync "$SOURCE_DIR/" "s3://$BUCKET_NAME/" \
    --region "$REGION" \
    --include "*.css" \
    --exclude "*" \
    --content-type "text/css" \
    --acl public-read

# JavaScript files
aws s3 sync "$SOURCE_DIR/" "s3://$BUCKET_NAME/" \
    --region "$REGION" \
    --include "*.js" \
    --exclude "*" \
    --content-type "application/javascript" \
    --acl public-read

# Other files (images, etc.)
aws s3 sync "$SOURCE_DIR/" "s3://$BUCKET_NAME/" \
    --region "$REGION" \
    --exclude "*.html" \
    --exclude "*.css" \
    --exclude "*.js" \
    --acl public-read

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
echo "Note: If using a custom domain (e.g., https://chat.pandoracloud.net), ensure CloudFront is configured correctly."