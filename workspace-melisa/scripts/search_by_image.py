"""
Search by Image — CLIP encoder + Qdrant vector search
Klienti dergon foto → CLIP enkodon → Qdrant gjen produkte te ngjashme

Model: sentence-transformers/clip-ViT-B-32 (512-dim, cached)
Qdrant: localhost:6333, collection "items", cosine similarity
"""
import sys
import os
import json
import tempfile
import urllib.request

# Lazy-loaded globals
_model = None
_qdrant = None

QDRANT_HOST = os.environ.get("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.environ.get("QDRANT_PORT", "6333"))
COLLECTION = "items"
MODEL_NAME = "sentence-transformers/clip-ViT-B-32"


def _get_model():
    """Lazy-load CLIP model (ngarkohet 1 here, qendron ne memorie)."""
    global _model
    if _model is None:
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer(MODEL_NAME)
    return _model


def _get_qdrant():
    """Lazy-load Qdrant client."""
    global _qdrant
    if _qdrant is None:
        from qdrant_client import QdrantClient
        _qdrant = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=10)
    return _qdrant


def encode_image(image_source):
    """
    Enkodon foto ne vektor 512-dim me CLIP.

    Args:
        image_source: file path ose URL

    Returns:
        list[float] — 512-dim vector
    """
    from PIL import Image

    if image_source.startswith("http://") or image_source.startswith("https://"):
        tmp = tempfile.NamedTemporaryFile(suffix=".jpg", delete=False)
        try:
            req = urllib.request.Request(image_source, headers={"User-Agent": "MelisaBot/1.0"})
            with urllib.request.urlopen(req, timeout=15) as resp:
                tmp.write(resp.read())
            tmp.flush()
            img = Image.open(tmp.name).convert("RGB")
        finally:
            tmp.close()
            os.unlink(tmp.name)
    else:
        img = Image.open(image_source).convert("RGB")

    model = _get_model()
    vector = model.encode(img).tolist()
    return vector


def find_similar(image_source, top_k=8, threshold=0.20):
    """
    Gjen produkte te ngjashme me foton e dhene.

    Args:
        image_source: file path ose URL e fotos
        top_k: sa rezultate max
        threshold: score min (cosine similarity)

    Returns:
        list[dict] — secili ka: item_id, name, score, rate, category_name,
                     image_url, image_url_full, cf_group, sku
    """
    vector = encode_image(image_source)
    client = _get_qdrant()

    from qdrant_client.models import models
    results = client.query_points(
        collection_name=COLLECTION,
        query=vector,
        limit=top_k,
        score_threshold=threshold,
    )

    items = []
    for hit in results.points:
        p = hit.payload or {}
        items.append({
            "item_id": p.get("item_id"),
            "name": p.get("name", ""),
            "score": round(hit.score, 3),
            "rate": p.get("rate", 0),
            "category_name": p.get("category_name", ""),
            "cf_stili": p.get("cf_stili", ""),
            "image_url": p.get("image_url", ""),
            "image_url_full": p.get("image_url_full", ""),
            "cf_group": p.get("cf_group", ""),
            "sku": p.get("sku", ""),
        })

    return items


# CLI: python3 search_by_image.py <foto_path_or_url> [top_k]
if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Perdorim: python3 search_by_image.py <foto> [top_k]")
        print("  foto: file path ose URL")
        print("  top_k: sa rezultate (default 5)")
        sys.exit(1)

    source = sys.argv[1]
    top_k = int(sys.argv[2]) if len(sys.argv) > 2 else 5

    print(f"Kerkoj produkte te ngjashme me: {source}")
    print(f"Ngarkoj CLIP model...")
    results = find_similar(source, top_k=top_k)

    if not results:
        print("Asnje produkt i ngjashem nuk u gjet.")
    else:
        print(f"\n{len(results)} produkte te ngjashme:")
        for i, r in enumerate(results, 1):
            match = "MATCH" if r["score"] >= 0.65 else "ngjashem" if r["score"] >= 0.40 else "i dobet"
            print(f"  {i}. {r['name']} — {r['rate']} L (score: {r['score']} {match})")
            print(f"     Kategori: {r['category_name']} | SKU: {r['sku']}")
            if r["image_url"]:
                print(f"     Foto: {r['image_url']}")
