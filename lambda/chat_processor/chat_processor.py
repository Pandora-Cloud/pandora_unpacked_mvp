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
