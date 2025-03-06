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
