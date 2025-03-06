# lambda/chat_processor/llm_config.py
LLM_CONFIG = {
    "titan-text-express-v1": {
        "model_id": "amazon.titan-text-express-v1",
        "provider": "bedrock"
    }
}

def get_llm_model(llm_key):
    return LLM_CONFIG.get(llm_key, LLM_CONFIG["titan-text-express-v1"])
