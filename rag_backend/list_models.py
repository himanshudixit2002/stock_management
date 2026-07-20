import google.genai as genai
import os
from dotenv import load_dotenv

load_dotenv()
client = genai.Client()
for model in client.models.list():
    if 'gemini' in model.name:
        print(model.name)
