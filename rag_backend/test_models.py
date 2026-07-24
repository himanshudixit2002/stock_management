import os
import dotenv
dotenv.load_dotenv()

key = os.environ.get("GOOGLE_API_KEY") or os.environ.get("GEMINI_API_KEY")
print("Key present:", bool(key))

from langchain_google_genai import ChatGoogleGenerativeAI

models_to_test = ["gemini-1.5-flash", "gemini-1.5-pro", "gemini-2.0-flash-exp"]

for m in models_to_test:
    try:
        print(f"Testing {m}...")
        llm = ChatGoogleGenerativeAI(model=m, google_api_key=key, temperature=0)
        res = llm.invoke("Hello")
        print(f"SUCCESS {m}: {res.content}")
        break
    except Exception as e:
        print(f"FAILED {m}: {e}")
