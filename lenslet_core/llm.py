import requests


def summarize(text):

    response = requests.post(
        "http://localhost:11434/api/generate",
        json={
            "model": "qwen3:8b",
            "prompt": f"""
You are Lenslet.

Summarize this captured content.
Extract key ideas.
Explain important concepts.

Content:

{text}
""",
            "stream": False
        }
    )

    return response.json()["response"]