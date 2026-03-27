"""
Catalog Indexer — Sync produktesh nga zeroabsolute.com → Qdrant (CLIP vectors)

Perdorim:
  python3 catalog_indexer.py --full       # ri-indekso gjithcka
  python3 catalog_indexer.py --delta      # vetem te reja/ndryshuara
  python3 catalog_indexer.py --stats      # trego statistika

Cron: cdo dite 04:00 CET me --delta
"""
import sys
import os
import json
import time
import urllib.request

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS_DIR)

WEB_API = "https://zeroabsolute.com/api/v2/products"
PER_PAGE = 50
QDRANT_HOST = os.environ.get("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.environ.get("QDRANT_PORT", "6333"))
COLLECTION = "items"


def fetch_all_products():
    """Merr te gjitha produktet nga web API (paginim)."""
    products = []
    page = 1
    while True:
        url = f"{WEB_API}?per_page={PER_PAGE}&page={page}"
        req = urllib.request.Request(url, headers={
            "User-Agent": "MelisaBot/1.0",
            "Accept": "application/json",
        })
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.loads(resp.read().decode())

        items = data.get("data", [])
        if not items:
            break

        products.extend(items)
        meta = data.get("meta", {})
        last_page = meta.get("last_page", page)
        print(f"  Faqe {page}/{last_page} — {len(items)} produkte ({len(products)} total)")

        if page >= last_page:
            break
        page += 1
        time.sleep(0.3)  # respekto rate limits

    return products


def get_qdrant_ids():
    """Merr te gjitha point IDs ekzistuese ne Qdrant."""
    from qdrant_client import QdrantClient
    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=10)

    ids = set()
    offset = None
    while True:
        result = client.scroll(
            collection_name=COLLECTION,
            limit=500,
            offset=offset,
            with_payload=False,
            with_vectors=False,
        )
        points, next_offset = result
        for p in points:
            ids.add(p.id)
        if next_offset is None:
            break
        offset = next_offset

    return ids


def index_products(products, force=False):
    """Enkodon produktet me CLIP dhe i fut ne Qdrant."""
    from qdrant_client import QdrantClient
    from qdrant_client.models import PointStruct, VectorParams, Distance
    import search_by_image as sbi

    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=30)

    # Krijo collection nese nuk ekziston
    collections = [c.name for c in client.get_collections().collections]
    if COLLECTION not in collections:
        client.create_collection(
            collection_name=COLLECTION,
            vectors_config=VectorParams(size=512, distance=Distance.COSINE),
        )
        print(f"Collection '{COLLECTION}' krijuar")

    # Merr IDs ekzistuese per delta mode
    existing_ids = set() if force else get_qdrant_ids()

    indexed = 0
    skipped = 0
    failed = 0
    batch = []

    for i, product in enumerate(products):
        slug = product.get("group_slug", "")
        name = product.get("name", "")

        # Perdor hash te slug si point ID (int)
        point_id = abs(hash(slug)) % (2**53)

        if not force and point_id in existing_ids:
            skipped += 1
            continue

        # Merr foton kryesore
        image_url = None
        images = product.get("images", [])
        if images:
            image_url = images[0].get("url", "")
        if not image_url:
            image_url = product.get("image", "")
        if not image_url:
            skipped += 1
            continue

        # Enkodon me CLIP
        try:
            vector = sbi.encode_image(image_url)
        except Exception as e:
            print(f"  GABIM encoding {name}: {e}")
            failed += 1
            continue

        # Payload
        colors = [c.get("value", "") for c in product.get("colors", [])]
        payload = {
            "item_id": point_id,
            "name": name,
            "sku": slug,
            "rate": product.get("price", 0),
            "category_name": product.get("category", {}).get("name", "") if isinstance(product.get("category"), dict) else "",
            "cf_stili": "",
            "cf_sezoni": "",
            "cf_group": slug,
            "image_url": product.get("thumbnail", image_url),
            "image_url_full": image_url,
            "colors": colors,
            "in_stock": product.get("in_stock", False),
        }

        batch.append(PointStruct(id=point_id, vector=vector, payload=payload))
        indexed += 1

        # Upsert ne batch-e te 20
        if len(batch) >= 20:
            client.upsert(collection_name=COLLECTION, points=batch)
            batch = []
            print(f"  Indeksuar {indexed}/{len(products)} ({skipped} skipped, {failed} failed)")

    # Upsert mbetjen
    if batch:
        client.upsert(collection_name=COLLECTION, points=batch)

    print(f"\nPerfunduar: {indexed} indeksuar, {skipped} skipped, {failed} failed")
    return indexed, skipped, failed


def show_stats():
    """Trego statistika per Qdrant collection."""
    from qdrant_client import QdrantClient
    client = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=10)
    info = client.get_collection(COLLECTION)
    print(f"Collection: {COLLECTION}")
    print(f"Points: {info.points_count}")
    print(f"Vectors: {info.config.params.vectors.size}d, {info.config.params.vectors.distance}")
    print(f"Status: {info.status}")


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--stats"

    if mode == "--stats":
        show_stats()
    elif mode == "--full":
        print("MODE: Full reindex (te gjitha produktet)")
        products = fetch_all_products()
        print(f"\n{len(products)} produkte nga web API")
        print("Indeksoj me CLIP (mund te zgjase 5-10 min)...")
        index_products(products, force=True)
    elif mode == "--delta":
        print("MODE: Delta (vetem te reja)")
        products = fetch_all_products()
        print(f"\n{len(products)} produkte nga web API")
        print("Indeksoj vetem te rejat...")
        index_products(products, force=False)
    else:
        print("Perdorim: python3 catalog_indexer.py [--full|--delta|--stats]")
