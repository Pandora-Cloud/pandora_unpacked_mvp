#!/bin/bash
 
# Store the initial working directory (where the script is run from)
INITIAL_DIR="$(pwd)"
SCRIPT_DIR="$(dirname "$0")"
 
# Ensure script runs from the lambda directory
cd "$SCRIPT_DIR" || { echo "Failed to change to lambda directory: $SCRIPT_DIR"; exit 1; }
 
# Create temporary directories for each Lambda function
TEMP_AUTH=$(mktemp -d)
TEMP_CHAT=$(mktemp -d)
TEMP_HISTORY=$(mktemp -d)
 
# Build auth_handler
cp auth_handler/auth_handler.py "$TEMP_AUTH" || { echo "Failed to copy auth_handler.py"; exit 1; }
cp utils.py "$TEMP_AUTH" || { echo "Failed to copy utils.py to auth_handler"; exit 1; }
cp auth_handler/requirements.txt "$TEMP_AUTH" || { echo "Failed to copy auth_handler requirements.txt"; exit 1; }
cd "$TEMP_AUTH" || { echo "Failed to cd to $TEMP_AUTH"; exit 1; }
pip install -r requirements.txt -t . || { echo "Failed to install auth_handler dependencies"; exit 1; }
zip -r auth_handler.zip . || { echo "Failed to zip auth_handler"; exit 1; }
mv auth_handler.zip "$INITIAL_DIR/" || { echo "Failed to move auth_handler.zip"; exit 1; }
 
# Build chat_processor
cd "$INITIAL_DIR" || { echo "Failed to return to $INITIAL_DIR"; exit 1; }
cp chat_processor/chat_processor.py "$TEMP_CHAT" || { echo "Failed to copy chat_processor.py"; exit 1; }
cp chat_processor/llm_config.py "$TEMP_CHAT" || { echo "Failed to copy llm_config.py"; exit 1; }
cp utils.py "$TEMP_CHAT" || { echo "Failed to copy utils.py to chat_processor"; exit 1; }
cp chat_processor/requirements.txt "$TEMP_CHAT" || { echo "Failed to copy chat_processor requirements.txt"; exit 1; }
cd "$TEMP_CHAT" || { echo "Failed to cd to $TEMP_CHAT"; exit 1; }
pip install -r requirements.txt -t . || { echo "Failed to install chat_processor dependencies"; exit 1; }
zip -r chat_processor.zip . || { echo "Failed to zip chat_processor"; exit 1; }
mv chat_processor.zip "$INITIAL_DIR/" || { echo "Failed to move chat_processor.zip"; exit 1; }
 
# Build history_manager
cd "$INITIAL_DIR" || { echo "Failed to return to $INITIAL_DIR"; exit 1; }
cp history_manager/history_manager.py "$TEMP_HISTORY" || { echo "Failed to copy history_manager.py"; exit 1; }
cp utils.py "$TEMP_HISTORY" || { echo "Failed to copy utils.py to history_manager"; exit 1; }
cp history_manager/requirements.txt "$TEMP_HISTORY" || { echo "Failed to copy history_manager requirements.txt"; exit 1; }
cd "$TEMP_HISTORY" || { echo "Failed to cd to $TEMP_HISTORY"; exit 1; }
pip install -r requirements.txt -t . || { echo "Failed to install history_manager dependencies"; exit 1; }
zip -r history_manager.zip . || { echo "Failed to zip history_manager"; exit 1; }
mv history_manager.zip "$INITIAL_DIR/" || { echo "Failed to move history_manager.zip"; exit 1; }
 
# Clean up temporary directories
cd "$INITIAL_DIR" || { echo "Failed to return to $INITIAL_DIR for cleanup"; exit 1; }
rm -rf "$TEMP_AUTH" "$TEMP_CHAT" "$TEMP_HISTORY" || { echo "Failed to clean up temporary directories"; exit 1; }
 
echo "Lambda deployment packages created: auth_handler/auth_handler.zip, chat_processor/chat_processor.zip, history_manager/history_manager.zip"