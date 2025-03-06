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
