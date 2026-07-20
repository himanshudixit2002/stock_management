import os
from google import genai
from dotenv import load_dotenv

load_dotenv()

key = os.environ.get("GOOGLE_API_KEY")

client = genai.Client(api_key=key)
print("Fetching available models for this API key...")
try:
    for model in client.models.list():
        print(model.name)
except Exception as e:
    print(f"Error fetching models: {e}")
