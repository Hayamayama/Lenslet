from lenslet_core.capture import capture_screen
from lenslet_core.ocr import extract_text
from lenslet_core.llm import summarize
from lenslet_core.memory import save_memory
from lenslet_core.vector_memory import add_memory, search_related


print("📸 Capture something")

image = capture_screen()


print("👀 Reading...")

text = extract_text(image)

print("\n====== OCR ======")
print(text)


print("\n🧠 Thinking...")

summary = summarize(text)


print("\n====== SUMMARY ======")
print(summary)

memory_path = save_memory(
    text,
    summary
)

print(f"\n💾 Memory saved to {memory_path}")

memory_id = memory_path.stem

related = search_related(summary, n_results=3)

print("\n====== RELATED MEMORIES ======")

if not related:
    print("No related memories yet.")
else:
    for item in related:
        print(f"- {item['path']}  distance={item['distance']:.4f}")
        print(item["text"][:200])
        print()

add_memory(
    memory_id=memory_id,
    text=text,
    summary=summary,
    path=memory_path
)