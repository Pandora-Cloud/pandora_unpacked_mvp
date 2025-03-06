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
