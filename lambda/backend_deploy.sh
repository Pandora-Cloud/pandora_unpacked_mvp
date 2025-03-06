#!/bin/bash

# Ensure script runs from the lambda directory
cd "$(dirname "$0")" || { echo "Failed to change to lambda directory"; exit 1; }

# Create temporary directories for each Lambda function
TEMP_AUTH=$(mktemp -d)
TEMP_CHAT=$(mktemp -d)
TEMP_HISTORY=$(mktemp -d)

# Build auth_handler
cp auth_handler/auth_handler.py "$TEMP_AUTH"
cp utils.py "$TEMP_AUTH"
cp auth_handler/requirements.txt "$TEMP_AUTH"
cd "$TEMP_AUTH"
pip install -r requirements.txt -t . || { echo "Failed to install auth_handler dependencies"; exit 1; }
zip -r auth_handler.zip . || { echo "Failed to zip auth_handler"; exit 1; }
mv auth_handler.zip ../auth_handler/

# Build chat_processor
cd ../
cp chat_processor/chat_processor.py "$TEMP_CHAT"
cp chat_processor/llm_config.py "$TEMP_CHAT"
cp utils.py "$TEMP_CHAT"
cp chat_processor/requirements.txt "$TEMP_CHAT"
cd "$TEMP_CHAT"
pip install -r requirements.txt -t . || { echo "Failed to install chat_processor dependencies"; exit 1; }
zip -r chat_processor.zip . || { echo "Failed to zip chat_processor"; exit 1; }
mv chat_processor.zip ../chat_processor/

# Build history_manager
cd ../
cp history_manager/history_manager.py "$TEMP_HISTORY"
cp utils.py "$TEMP_HISTORY"
cp history_manager/requirements.txt "$TEMP_HISTORY"
cd "$TEMP_HISTORY"
pip install -r requirements.txt -t . || { echo "Failed to install history_manager dependencies"; exit 1; }
zip -r history_manager.zip . || { echo "Failed to zip history_manager"; exit 1; }
mv history_manager.zip ../history_manager/

# Clean up temporary directories
cd ../
rm -rf "$TEMP_AUTH" "$TEMP_CHAT" "$TEMP_HISTORY"

echo "Lambda deployment packages created: auth_handler/auth_handler.zip, chat_processor/chat_processor.zip, history_manager/history_manager.zip"
