import chromadb
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
CHROMA_PATH = PROJECT_ROOT / "chroma_db"

client = chromadb.PersistentClient(path=str(CHROMA_PATH))
collection = client.get_or_create_collection(name="lenslet_memories")


def add_memory(memory_id, text, summary, path):
    collection.add(
        ids=[memory_id],
        documents=[summary + "\n\n" + text],
        metadatas=[{
            "path": str(path)
        }]
    )


def search_related(query, n_results=3):
    results = collection.query(
        query_texts=[query],
        n_results=n_results
    )

    related = []

    for i in range(len(results["ids"][0])):
        related.append({
            "id": results["ids"][0][i],
            "path": results["metadatas"][0][i]["path"],
            "distance": results["distances"][0][i],
            "text": results["documents"][0][i][:500]
        })

    return related