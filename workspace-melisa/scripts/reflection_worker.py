"""
Reflection Worker — Analizon bisedat e Melises per te mesuar cfare funksionoi

Pas cdo bisede te perfunduar, Claude analizon:
- Cfare funksionoi? Cfare jo?
- Cfare mund te mesoje per here tjeter?
- Cila rregull kandidate duhet krijuar?

Perdorim:
  python3 reflection_worker.py --process     # processo bisedat pa reflection
  python3 reflection_worker.py --stats       # trego statistika
  python3 reflection_worker.py --recent 3    # trego 3 reflektimet e fundit

Cron: cdo 30 min
"""
import sys
import os
import json
import time
import urllib.request
import hashlib

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, SCRIPTS_DIR)

QDRANT_HOST = os.environ.get("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.environ.get("QDRANT_PORT", "6333"))
EPISODES_COLLECTION = "melisa_episodes"
FEEDBACK_COLLECTION = "melisa_feedback"

# Anthropic API per reflection
ANTHROPIC_KEY = os.environ.get("ANTHROPIC_API_KEY", "")
if not ANTHROPIC_KEY:
    # Lexo nga .env file
    env_path = os.path.expanduser("~/.openclaw/.env")
    try:
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line.startswith("ANTHROPIC_API_KEY="):
                    ANTHROPIC_KEY = line.split("=", 1)[1].strip()
                    break
    except Exception:
        pass

REFLECTION_MODEL = "claude-sonnet-4-20250514"

# Lazy globals
_model = None
_qdrant = None


def _get_model():
    global _model
    if _model is None:
        import warnings
        warnings.filterwarnings("ignore")
        from sentence_transformers import SentenceTransformer
        _model = SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
    return _model


def _get_qdrant():
    global _qdrant
    if _qdrant is None:
        from qdrant_client import QdrantClient
        _qdrant = QdrantClient(host=QDRANT_HOST, port=QDRANT_PORT, timeout=30)
    return _qdrant


def ensure_feedback_collection():
    """Krijo melisa_feedback nese nuk ekziston."""
    from qdrant_client.models import VectorParams, Distance
    client = _get_qdrant()
    collections = [c.name for c in client.get_collections().collections]
    if FEEDBACK_COLLECTION not in collections:
        client.create_collection(
            collection_name=FEEDBACK_COLLECTION,
            vectors_config=VectorParams(size=384, distance=Distance.COSINE),
        )
        print(f"  Collection {FEEDBACK_COLLECTION} krijuar")


def call_claude(prompt, max_tokens=800):
    """Therr Claude per reflection analysis."""
    body = json.dumps({
        "model": REFLECTION_MODEL,
        "max_tokens": max_tokens,
        "messages": [{"role": "user", "content": prompt}],
    }).encode()

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "x-api-key": ANTHROPIC_KEY,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json",
        },
    )

    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read().decode())
        content = data.get("content", [])
        if content and content[0].get("type") == "text":
            return content[0]["text"]
    return ""


REFLECTION_PROMPT = """Analizon biseden e meposhtme te Melises (shitese mode per Zero Absolute).

BISEDA:
{conversation}

OUTCOME: {outcome}
MESAZHE: {message_count}

Analizo dhe kthe JSON me kete format (VETEM JSON, pa tekst tjeter):
{{
  "what_worked": ["lista e gjrave qe funksionuan mire"],
  "what_failed": ["lista e gjrave qe nuk funksionuan"],
  "customer_type": "lloji i klientit (psh: i interesuar, browser, i kthyer, i nxituar)",
  "objections": ["lista e objection-eve: price, sizing, color, shipping, etj"],
  "products_discussed": ["emrat e produkteve qe u diskutuan"],
  "new_rules": [
    {{
      "rule": "rregull e re qe duhet mesuar per here tjeter",
      "category": "ton|produkte|shitje|gabime|sizing|pricing",
      "confidence": 0.5
    }}
  ],
  "summary": "permbledhje 1-2 fjali e bisedes"
}}

RREGULLA:
- Fokusohu ne cfare mund te mesoje Melisa per here tjeter
- Nese biseda eshte shume e shkurter ose pa substanc, kthe new_rules bosh
- Confidence 0.5 per te gjitha rregullat e reja (do rritet me kohen)
- KURRE mos sugjero rregulla manipuluese ose me presion
"""


def get_unreflected_episodes():
    """Merr episodes qe nuk kane reflection ende."""
    client = _get_qdrant()
    episodes = []
    offset = None

    while True:
        result = client.scroll(
            collection_name=EPISODES_COLLECTION,
            limit=50,
            offset=offset,
            with_payload=True,
            with_vectors=False,
        )
        points, next_offset = result
        for p in points:
            payload = p.payload or {}
            if not payload.get("reflection"):
                episodes.append({"id": p.id, "payload": payload})
        if next_offset is None:
            break
        offset = next_offset

    return episodes


def reflect_on_episode(episode):
    """Gjenero reflection per nje episode."""
    payload = episode["payload"]
    summary = payload.get("summary", "")
    outcome = payload.get("outcome", "unknown")
    message_count = payload.get("message_count", 0)

    if not summary or message_count < 3:
        return None

    # Pastro summary nga metadata noise
    clean_lines = []
    for line in summary.split("\n"):
        if "untrusted metadata" in line or "openclaw-control-ui" in line:
            continue
        if line.strip().startswith("```"):
            continue
        if line.strip().startswith("{") or line.strip().startswith("}"):
            continue
        if line.strip():
            clean_lines.append(line.strip())
    clean_summary = "\n".join(clean_lines)

    if len(clean_summary) < 20:
        return None

    # Therr Claude
    prompt = REFLECTION_PROMPT.format(
        conversation=clean_summary[:3000],
        outcome=outcome,
        message_count=message_count,
    )

    try:
        response = call_claude(prompt)
        # Parse JSON
        json_start = response.find("{")
        json_end = response.rfind("}") + 1
        if json_start >= 0 and json_end > json_start:
            reflection = json.loads(response[json_start:json_end])
            return reflection
    except Exception as e:
        print(f"  Gabim reflection: {e}")

    return None


def save_reflection(episode_id, reflection):
    """Ruaj reflection ne episode payload dhe rule candidates ne feedback."""
    from qdrant_client.models import PointStruct
    client = _get_qdrant()
    model = _get_model()

    # Perditeso episode me reflection
    client.set_payload(
        collection_name=EPISODES_COLLECTION,
        payload={"reflection": reflection},
        points=[episode_id],
    )

    # Ruaj rule candidates ne feedback collection
    new_rules = reflection.get("new_rules", [])
    if new_rules:
        ensure_feedback_collection()
        points = []
        for rule in new_rules:
            rule_text = rule.get("rule", "")
            if not rule_text:
                continue
            vector = model.encode(rule_text).tolist()
            point_id = abs(int(hashlib.md5(rule_text.encode()).hexdigest()[:15], 16))
            points.append(PointStruct(
                id=point_id,
                vector=vector,
                payload={
                    "rule_text": rule_text,
                    "category": rule.get("category", ""),
                    "confidence": rule.get("confidence", 0.5),
                    "source": "reflection",
                    "source_episode": episode_id,
                    "status": "candidate",
                    "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ"),
                    "agent_id": "melisa",
                }
            ))
        if points:
            client.upsert(collection_name=FEEDBACK_COLLECTION, points=points)
            return len(points)
    return 0


def process_all():
    """Processo te gjitha episodes pa reflection."""
    print("Merr episodes pa reflection...")
    episodes = get_unreflected_episodes()
    print(f"  {len(episodes)} episodes per procesim")

    if not episodes:
        print("  Asgje per procesim.")
        return

    reflected = 0
    rules_created = 0

    for ep in episodes:
        sid = ep["payload"].get("session_id", "?")[:25]
        print(f"  Reflektoj: {sid}...")

        reflection = reflect_on_episode(ep)
        if reflection:
            n_rules = save_reflection(ep["id"], reflection)
            reflected += 1
            rules_created += n_rules
            print(f"    OK: {reflection.get('summary', '')[:100]}")
            if n_rules:
                print(f"    {n_rules} rule candidates krijuar")
        else:
            # Marko si reflected (pa substanc) per te mos e procesuar perseri
            _get_qdrant().set_payload(
                collection_name=EPISODES_COLLECTION,
                payload={"reflection": {"skipped": True, "reason": "insufficient_content"}},
                points=[ep["id"]],
            )
            print(f"    Skipped (pa substanc)")

    print(f"\nPerfunduar: {reflected} refleksione, {rules_created} rule candidates")


def show_stats():
    """Trego statistika."""
    client = _get_qdrant()

    ep_info = client.get_collection(EPISODES_COLLECTION)
    print(f"Episodes: {ep_info.points_count}")

    collections = [c.name for c in client.get_collections().collections]
    if FEEDBACK_COLLECTION in collections:
        fb_info = client.get_collection(FEEDBACK_COLLECTION)
        print(f"Feedback (rule candidates): {fb_info.points_count}")
    else:
        print("Feedback: 0 (collection nuk ekziston ende)")


def show_recent(n=3):
    """Trego reflektimet e fundit."""
    client = _get_qdrant()
    result = client.scroll(
        collection_name=EPISODES_COLLECTION,
        limit=n * 2,  # disa mund te mos kene reflection
        with_payload=True,
        with_vectors=False,
    )
    points, _ = result
    shown = 0
    for p in points:
        refl = (p.payload or {}).get("reflection", {})
        if not refl or refl.get("skipped"):
            continue

        print(f"\n--- Reflection (episode {p.id}) ---")
        print(f"  Summary: {refl.get('summary', '?')}")
        print(f"  Customer: {refl.get('customer_type', '?')}")
        print(f"  Worked: {refl.get('what_worked', [])}")
        print(f"  Failed: {refl.get('what_failed', [])}")
        print(f"  Products: {refl.get('products_discussed', [])}")
        rules = refl.get("new_rules", [])
        if rules:
            print(f"  New rules ({len(rules)}):")
            for r in rules:
                print(f"    [{r.get('category', '?')}] {r.get('rule', '?')}")
        shown += 1
        if shown >= n:
            break

    if shown == 0:
        print("Asnje reflection ende.")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--stats"

    if cmd == "--process":
        process_all()
    elif cmd == "--stats":
        show_stats()
    elif cmd == "--recent":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 3
        show_recent(n)
    else:
        print("Perdorim: python3 reflection_worker.py [--process|--stats|--recent N]")
