"""
Conversation Logger — Ruan bisedat e Melises si episodic memory ne Qdrant

Perdorim:
  python3 conversation_logger.py --process    # processo bisedat e perfunduara
  python3 conversation_logger.py --stats      # trego statistika
  python3 conversation_logger.py --recent 5   # trego 5 episodet e fundit

Triggered: cdo 30 min via cron, ose manualisht
"""
import sys
import os
import json
import time
import subprocess
import hashlib
from datetime import datetime, timezone

SCRIPTS_DIR = os.path.dirname(os.path.abspath(__file__))
QDRANT_HOST = os.environ.get("QDRANT_HOST", "localhost")
QDRANT_PORT = int(os.environ.get("QDRANT_PORT", "6333"))
EPISODES_COLLECTION = "melisa_episodes"
PROCESSED_FILE = os.path.join(SCRIPTS_DIR, ".processed_sessions.json")

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


def get_processed_ids():
    """Merr session IDs qe jane procesuar tashme."""
    if os.path.exists(PROCESSED_FILE):
        with open(PROCESSED_FILE) as f:
            return set(json.load(f))
    return set()


def save_processed_id(session_id):
    """Shto session ID ne listen e procesuar."""
    ids = get_processed_ids()
    ids.add(session_id)
    with open(PROCESSED_FILE, "w") as f:
        json.dump(list(ids), f)


SESSIONS_DIR = os.environ.get(
    "OPENCLAW_SESSIONS_DIR",
    os.path.expanduser("~/.openclaw/agents/melisa/sessions")
)


def get_melisa_sessions():
    """Merr sessions nga JSONL files ne sessions dir."""
    sessions = []
    if not os.path.isdir(SESSIONS_DIR):
        print(f"  Sessions dir nuk ekziston: {SESSIONS_DIR}")
        return sessions

    for fname in os.listdir(SESSIONS_DIR):
        if not fname.endswith(".jsonl"):
            continue
        if ".reset." in fname:
            continue  # Skip archived sessions

        fpath = os.path.join(SESSIONS_DIR, fname)
        session_id = fname.replace(".jsonl", "")
        mtime = os.path.getmtime(fpath)
        size = os.path.getsize(fpath)

        sessions.append({
            "sessionId": session_id,
            "updatedAt": int(mtime * 1000),
            "filePath": fpath,
            "fileSize": size,
        })

    return sessions


def get_session_history(session_file):
    """Lexo mesazhet nga JSONL session file."""
    messages = []
    try:
        with open(session_file) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                entry = json.loads(line)
                if entry.get("type") != "message":
                    continue

                msg = entry.get("message", {})
                role = msg.get("role", "")
                content = msg.get("content", "")

                if isinstance(content, list):
                    texts = []
                    for c in content:
                        if isinstance(c, dict) and c.get("type") == "text" and c.get("text"):
                            texts.append(c["text"])
                    content = " ".join(texts)

                if role in ("user", "assistant") and content and len(content) > 5:
                    messages.append({"role": role, "content": content})
    except Exception as e:
        print(f"  Gabim reading {session_file}: {e}")

    return messages


def summarize_conversation(messages):
    """Krijon summary te shkurter te bisedes."""
    if not messages:
        return ""

    parts = []
    products = []
    objections = []

    for msg in messages:
        role = msg.get("role", "")
        text = msg.get("content", "")
        if isinstance(text, list):
            text = " ".join(t.get("text", "") for t in text if isinstance(t, dict))

        if role == "user":
            parts.append(f"Klient: {text[:200]}")
            # Detekto objections
            lower = text.lower()
            if any(w in lower for w in ["shtrenjte", "lire", "cmim", "zbritje", "oferte"]):
                objections.append("price")
            if any(w in lower for w in ["mase", "numer", "madhesi", "size"]):
                objections.append("sizing")
        elif role == "assistant":
            parts.append(f"Melisa: {text[:200]}")

    summary = "\n".join(parts[-10:])  # max 10 mesazhet e fundit
    return summary, list(set(objections))


def process_session(session):
    """Proceso nje session dhe ruaj si episode ne Qdrant."""
    session_id = session.get("sessionId", "")
    updated_at = session.get("updatedAt", 0)

    # Kontrollo nese eshte bisede e vjeter (>30 min pa aktivitet)
    now_ms = int(time.time() * 1000)
    age_min = (now_ms - updated_at) / 60000
    if age_min < 30:
        return False  # Ende aktive

    # Merr historine nga JSONL file
    file_path = session.get("filePath", "")
    if not file_path or not os.path.exists(file_path):
        return False

    messages = get_session_history(file_path)
    if len(messages) < 2:
        return False  # Shume e shkurter

    # Gjenero summary
    summary, objections = summarize_conversation(messages)
    if not summary:
        return False

    # Detekto outcome (heuristik baze)
    last_msgs = " ".join(m.get("content", "")[:100] for m in messages[-3:] if isinstance(m.get("content"), str))
    lower = last_msgs.lower()
    if any(w in lower for w in ["porosi", "konfirm", "emri", "telefon", "adres"]):
        outcome = "converted"
    elif any(w in lower for w in ["faleminderit", "rrofsh", "mire", "ok"]):
        outcome = "completed"
    elif any(w in lower for w in ["marjus", "ekip", "ndihme"]):
        outcome = "escalated"
    else:
        outcome = "browsing"

    # Encode summary
    model = _get_model()
    vector = model.encode(summary).tolist()

    # Krijo point ID nga session hash
    point_id = abs(int(hashlib.md5(session_id.encode()).hexdigest()[:15], 16))

    # Upsert ne Qdrant
    from qdrant_client.models import PointStruct
    client = _get_qdrant()
    client.upsert(
        collection_name=EPISODES_COLLECTION,
        points=[PointStruct(
            id=point_id,
            vector=vector,
            payload={
                "session_id": session_id,
                "timestamp": datetime.fromtimestamp(updated_at / 1000, tz=timezone.utc).isoformat(),
                "outcome": outcome,
                "objections": objections,
                "message_count": len(messages),
                "summary": summary[:1000],
                "model": session.get("model", ""),
                "tokens_used": session.get("totalTokens", 0),
                "agent_id": "melisa",
            }
        )]
    )
    return True


def process_all():
    """Proceso te gjitha bisedat e perfunduara."""
    print("Merr sessions nga OpenClaw...")
    sessions = get_melisa_sessions()
    print(f"  {len(sessions)} sessions gjetur")

    processed_ids = get_processed_ids()
    new_count = 0
    skip_count = 0

    for session in sessions:
        sid = session.get("sessionId", "")
        if sid in processed_ids:
            skip_count += 1
            continue

        if process_session(session):
            save_processed_id(sid)
            new_count += 1
            print(f"  Procesuar: {sid[:20]}...")
        else:
            skip_count += 1

    print(f"\nPerfunduar: {new_count} te reja, {skip_count} skipped")


def show_stats():
    """Trego statistika per episodes."""
    client = _get_qdrant()
    info = client.get_collection(EPISODES_COLLECTION)
    print(f"Collection: {EPISODES_COLLECTION}")
    print(f"Episodes: {info.points_count}")
    print(f"Status: {info.status}")


def show_recent(n=5):
    """Trego N episodet e fundit."""
    client = _get_qdrant()
    result = client.scroll(
        collection_name=EPISODES_COLLECTION,
        limit=n,
        with_payload=True,
        with_vectors=False,
    )
    points, _ = result
    if not points:
        print("Asnje episode ende.")
        return

    for p in points:
        pl = p.payload
        print(f"\n--- Episode {p.id} ---")
        print(f"  Session: {pl.get('session_id', '?')[:30]}...")
        print(f"  Koha: {pl.get('timestamp', '?')}")
        print(f"  Outcome: {pl.get('outcome', '?')}")
        print(f"  Mesazhe: {pl.get('message_count', '?')}")
        print(f"  Objections: {pl.get('objections', [])}")
        print(f"  Summary: {pl.get('summary', '')[:200]}")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "--stats"

    if cmd == "--process":
        process_all()
    elif cmd == "--stats":
        show_stats()
    elif cmd == "--recent":
        n = int(sys.argv[2]) if len(sys.argv) > 2 else 5
        show_recent(n)
    else:
        print("Perdorim: python3 conversation_logger.py [--process|--stats|--recent N]")
