#!/bin/bash

# Ensure script runs from its own directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || { echo "Failed to change to script directory"; exit 1; }

# Create Lambda directories with error checking
for dir in lambda/{auth_handler,chat_processor,history_manager}; do
  mkdir -p "$dir" || { echo "Failed to create directory $dir"; exit 1; }
done

# Lambda Shared Utility File (utils.py remains in lambda/ root for shared use)
cat << 'EOF' > lambda/utils.py || { echo "Failed to create lambda/utils.py"; exit 1; }
# lambda/utils.py
import json
import logging
import boto3
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_client = boto3.client('ssm')

def add_cors_headers(response):
    response['headers'] = {
        'Access-Control-Allow-Origin': 'https://chat.pandoracloud.net',
        'Access-Control-Allow-Headers': 'Content-Type,Authorization',
        'Access-Control-Allow-Methods': 'OPTIONS,POST,GET'
    }
    return response

def get_ssm_param(name):
    ssm_prefix = os.environ.get('SSM_PREFIX', '/chatbot-mvp')
    param = ssm_client.get_parameter(Name=f"{ssm_prefix}/{name}", WithDecryption=True)
    return param['Parameter']['Value']

def validate_input(body):
    if 'message' not in body or len(body['message']) > 1000:
        raise ValueError("Message must be provided and less than 1000 characters")
EOF

# auth_handler Directory
cat << 'EOF' > lambda/auth_handler/requirements.txt || { echo "Failed to create lambda/auth_handler/requirements.txt"; exit 1; }
# lambda/auth_handler/requirements.txt
boto3
EOF

cat << 'EOF' > lambda/auth_handler/auth_handler.py || { echo "Failed to create lambda/auth_handler/auth_handler.py"; exit 1; }
# lambda/auth_handler/auth_handler.py
import boto3
import json
import os
from utils import add_cors_headers, get_ssm_param, logger

cognito_client = boto3.client('cognito-idp')

def handler(event, context):
    try:
        body = json.loads(event.get('body', '{}'))
        path = event['path']
        
        user_pool_id = get_ssm_param('cognito-user-pool-id')
        client_id = get_ssm_param('cognito-client-id')
        
        if path == '/auth/login':
            response = cognito_client.initiate_auth(
                AuthFlow='USER_PASSWORD_AUTH',
                AuthParameters={
                    'USERNAME': body['email'],
                    'PASSWORD': body['password']
                },
                ClientId=client_id
            )
            logger.info(f"User {body['email']} logged in")
            return add_cors_headers({
                'statusCode': 200,
                'body': json.dumps(response['AuthenticationResult'])
            })
        
        elif path == '/auth/register':
            response = cognito_client.sign_up(
                ClientId=client_id,
                Username=body['email'],
                Password=body['password'],
                UserAttributes=[{'Name': 'email', 'Value': body['email']}]
            )
            logger.info(f"User {body['email']} registered")
            return add_cors_headers({
                'statusCode': 200,
                'body': json.dumps({'message': 'User registered, confirmation needed'})
            })
        
        elif path == '/auth/reset-password':
            response = cognito_client.forgot_password(
                ClientId=client_id,
                Username=body['email']
            )
            logger.info(f"Password reset initiated for {body['email']}")
            return add_cors_headers({
                'statusCode': 200,
                'body': json.dumps({'message': 'Password reset initiated'})
            })
        
        elif path == '/auth/update-password':
            response = cognito_client.change_password(
                PreviousPassword=body['old_password'],
                ProposedPassword=body['new_password'],
                AccessToken=event['headers']['Authorization'].split(' ')[1]
            )
            logger.info("Password updated")
            return add_cors_headers({
                'statusCode': 200,
                'body': json.dumps({'message': 'Password updated'})
            })
        
        elif path == '/auth/logout':
            response = cognito_client.global_sign_out(
                AccessToken=event['headers']['Authorization'].split(' ')[1]
            )
            logger.info("User logged out")
            return add_cors_headers({
                'statusCode': 200,
                'body': json.dumps({'message': 'Logged out'})
            })
        
        return add_cors_headers({
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid path'})
        })
    
    except Exception as e:
        logger.error(f"Error in auth_handler: {str(e)}")
        return add_cors_headers({
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        })
EOF

# chat_processor Directory
cat << 'EOF' > lambda/chat_processor/requirements.txt || { echo "Failed to create lambda/chat_processor/requirements.txt"; exit 1; }
# lambda/chat_processor/requirements.txt
boto3
pybreaker
EOF

cat << 'EOF' > lambda/chat_processor/llm_config.py || { echo "Failed to create lambda/chat_processor/llm_config.py"; exit 1; }
# lambda/chat_processor/llm_config.py
LLM_CONFIG = {
    "titan-text-express-v1": {
        "model_id": "amazon.titan-text-express-v1",
        "provider": "bedrock"
    }
}

def get_llm_model(llm_key):
    return LLM_CONFIG.get(llm_key, LLM_CONFIG["titan-text-express-v1"])
EOF

cat << 'EOF' > lambda/chat_processor/chat_processor.py || { echo "Failed to create lambda/chat_processor/chat_processor.py"; exit 1; }
# lambda/chat_processor/chat_processor.py
import boto3
import json
import uuid
import time
import os
import pybreaker
from botocore.config import Config
from llm_config import get_llm_model
from utils import add_cors_headers, validate_input, logger

dynamodb = boto3.resource('dynamodb')
bedrock = boto3.client('bedrock-runtime', config=Config(retries={'max_attempts': 3, 'mode': 'standard'}))
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])
breaker = pybreaker.CircuitBreaker(fail_max=5, reset_timeout=60)

@breaker
def invoke_bedrock(message, llm_config):
    response = bedrock.invoke_model(
        modelId=llm_config['model_id'],
        body=json.dumps({'inputText': message})
    )
    return json.loads(response['body'].read())['outputText']

def get_context(user_id, session_id):
    response = table.query(
        KeyConditionExpression='userId = :uid AND sessionId = :sid',
        ExpressionAttributeValues={':uid': user_id, ':sid': session_id}
    )
    return [item['message'] for item in response['Items']][-5:]

def handler(event, context):
    try:
        user_id = event['requestContext']['authorizer']['claims']['sub']
        body = json.loads(event['body'])
        validate_input(body)
        
        session_id = body.get('sessionId', str(uuid.uuid4()))
        llm_key = body.get('llm', 'titan-text-express-v1')
        llm_config = get_llm_model(llm_key)
        
        context = get_context(user_id, session_id)
        message_with_context = f"Previous: {' '.join(context)}\nCurrent: {body['message']}"
        llm_output = invoke_bedrock(message_with_context, llm_config)
        
        item = {
            'userId': user_id,
            'sessionId': session_id,
            'title': body.get('title', 'Untitled Chat'),
            'createdAt': int(time.time()) if not context else None,
            'messages': [{'message': body['message'], 'response': llm_output, 'timestamp': int(time.time())}]
        }
        table.put_item(Item=item)
        
        logger.info(f"Chat processed for user {user_id}, session {session_id}")
        return add_cors_headers({
            'statusCode': 200,
            'body': json.dumps({'response': llm_output, 'sessionId': session_id})
        })
    
    except pybreaker.CircuitBreakerError:
        logger.error("Bedrock circuit breaker tripped")
        return add_cors_headers({
            'statusCode': 503,
            'body': json.dumps({'error': 'Service temporarily unavailable'})
        })
    except Exception as e:
        logger.error(f"Error in chat_processor: {str(e)}")
        if "ThrottlingException" in str(e):
            return add_cors_headers({
                'statusCode': 429,
                'body': json.dumps({'error': 'Too many requests'})
            })
        return add_cors_headers({
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        })
EOF

# history_manager Directory
cat << 'EOF' > lambda/history_manager/requirements.txt || { echo "Failed to create lambda/history_manager/requirements.txt"; exit 1; }
# lambda/history_manager/requirements.txt
boto3
EOF

cat << 'EOF' > lambda/history_manager/history_manager.py || { echo "Failed to create lambda/history_manager/history_manager.py"; exit 1; }
# lambda/history_manager/history_manager.py
import boto3
import json
import os
from utils import add_cors_headers, logger

dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DYNAMODB_TABLE'])

def handler(event, context):
    try:
        user_id = event['requestContext']['authorizer']['claims']['sub']
        response = table.query(
            KeyConditionExpression='userId = :uid',
            ExpressionAttributeValues={':uid': user_id}
        )
        logger.info(f"History retrieved for user {user_id}")
        return add_cors_headers({
            'statusCode': 200,
            'body': json.dumps(response['Items'])
        })
    
    except Exception as e:
        logger.error(f"Error in history_manager: {str(e)}")
        return add_cors_headers({
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        })
EOF

# Updated backend_deploy.sh
cat << 'EOF' > lambda/backend_deploy.sh || { echo "Failed to create lambda/backend_deploy.sh"; exit 1; }
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
EOF

# Make backend_deploy.sh executable
chmod +x lambda/backend_deploy.sh || { echo "Failed to make lambda/backend_deploy.sh executable"; exit 1; }

echo "Lambda components installed and configured successfully with self-contained directories!"
