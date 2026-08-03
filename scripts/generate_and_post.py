import os
import requests
from google import genai

# 1. Initialize Gemini with Vertex AI on GCP
client = genai.Client(
    api_key=os.environ["GEMINI_API_KEY"],
    vertexai=True,
    project="project-cce03172-d052-4459-b4d",
    location="us-central1"
)

# 2. Prompt Gemini for social content
prompt = """
You are the social media manager for MyPocketPOS (https://mypocketpos.in/), an offline-first Point of Sale & billing app for retail and Kirana stores in India.

Write a short, engaging social media post (under 180 words) highlighting ONE of these benefits:
- Offline billing & digital GST receipts
- Multi-counter inventory management & stock alerts
- Customer credit (Udhar) ledger management

Include 2-3 relevant hashtags (e.g., #RetailTech, #POS, #KiranaBusiness) and a CTA to visit https://mypocketpos.in/.
"""

response = client.models.generate_content(
    model="gemini-2.5-flash",
    contents=prompt
)

post_text = response.text.strip()
print("--- Generated Social Post ---")
print(post_text)

# 3. Publish to Buffer across all configured channels
buffer_token = os.environ["BUFFER_ACCESS_TOKEN"]
raw_channels = os.environ.get("BUFFER_CHANNEL_ID", "")
channel_ids = [c.strip() for c in raw_channels.split(",") if c.strip()]

graphql_query = """
mutation CreatePost($input: CreatePostInput!) {
  createPost(input: $input) {
    post {
      id
      status
    }
  }
}
"""

headers = {
    "Authorization": f"Bearer {buffer_token}",
    "Content-Type": "application/json"
}

for channel_id in channel_ids:
    variables = {
        "input": {
            "channelId": channel_id,
            "text": post_text,
            "schedulingOption": "ADD_TO_QUEUE"
        }
    }
    
    res = requests.post(
        "https://api.buffer.com",
        json={"query": graphql_query, "variables": variables},
        headers=headers
    )
    print(f"Channel {channel_id} Status ({res.status_code}):", res.json())