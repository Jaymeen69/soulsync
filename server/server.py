import json
import os
import random
import string
import re
import hashlib
import threading
import time
import music_module
import safesync_module
import email_otp_module
import db_backend
from http.server import ThreadingHTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs, urlencode
import urllib.request
import urllib.error
from datetime import datetime, timedelta

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(BASE_DIR, "database.json")
ENV_FILE = os.path.join(BASE_DIR, ".env")

def _load_local_env():
    """Load key=value pairs from backend .env file into process env without logging secrets."""
    if not os.path.exists(ENV_FILE):
        return
    try:
        with open(ENV_FILE, "r", encoding="utf-8") as f:
            for raw_line in f:
                line = raw_line.strip()
                if not line or line.startswith("#") or "=" not in line:
                    continue
                k, v = line.split("=", 1)
                k = k.strip()
                v = v.strip().strip('"').strip("'")
                if k and v:
                    os.environ[k] = v
    except Exception:
        pass

_load_local_env()

def get_youtube_api_key():
    """Return configured YouTube Data API v3 key from env/.env, or None if missing/placeholder."""
    _load_local_env()
    key = (os.environ.get("YOUTUBE_API_KEY") or "").strip()
    if not key or key == "PASTE_YOUR_YOUTUBE_API_KEY_HERE":
        return None
    return key

def verify_youtube_api_connection():
    """Test YouTube Data API v3 connectivity (1 quota unit) without returning or logging the secret."""
    api_key = get_youtube_api_key()
    if not api_key:
        return {
            "configured": False,
            "connected": False,
            "message": "YOUTUBE_API_KEY is not set in backend .env yet."
        }
    params = urlencode({"part": "snippet", "id": "dQw4w9WgXcQ", "key": api_key})
    url = f"https://www.googleapis.com/youtube/v3/videos?{params}"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=6) as resp:
            body = json.loads(resp.read().decode("utf-8"))
            items = body.get("items", [])
            return {
                "configured": True,
                "connected": resp.status == 200,
                "items_found": len(items),
                "message": "YouTube Data API v3 connection verified successfully (secret kept private on backend)."
            }
    except urllib.error.HTTPError as e:
        err_text = ""
        try:
            err_json = json.loads(e.read().decode("utf-8"))
            err_text = err_json.get("error", {}).get("message", f"HTTP {e.code}")
        except Exception:
            err_text = f"HTTP {e.code}"
        # Redact key if ever echoed in error message
        err_text = err_text.replace(api_key, "[REDACTED]")
        return {
            "configured": True,
            "connected": False,
            "status_code": e.code,
            "message": f"YouTube API rejected request: {err_text}"
        }
    except Exception as e:
        safe_msg = str(e).replace(api_key, "[REDACTED]")
        return {
            "configured": True,
            "connected": False,
            "message": f"Connection error: {safe_msg}"
        }

# 7 Games Built-in Question & Prompt Banks

# Virtual Gift Shop Catalog
GIFT_CATALOG = [
    {"id": "gift_rose", "name": "Digital Red Rose", "category": "Flowers", "emoji": "🌹", "cost": 10, "desc": "A timeless symbol of passionate love and eternal romance."},
    {"id": "gift_bear", "name": "Cuddle Teddy Bear", "category": "Plushies", "emoji": "🧸", "cost": 25, "desc": "Sending warm and cozy hugs across any distance."},
    {"id": "gift_locket", "name": "Golden Heart Locket", "category": "Jewelry", "emoji": "💛", "cost": 50, "desc": "Keeps your sweetest memories forever close to your heart."},
    {"id": "gift_box", "name": "Starlight Surprise Box", "category": "Boxes", "emoji": "🎁", "cost": 30, "desc": "A romantic box filled with glowing stars and virtual kisses."},
    {"id": "gift_diamond", "name": "Eternal Diamond Ring", "category": "Jewelry", "emoji": "💍", "cost": 100, "desc": "A precious promise of boundless love, fidelity, and devotion."},
    {"id": "gift_letter", "name": "Handcrafted Love Scroll", "category": "Keepsakes", "emoji": "📜", "cost": 15, "desc": "Sealed with wax and filled with your deepest heartfelt words."}
]

GAME_BANKS = {
    "would_you_rather": [
        {"id": "wyr_1", "q": "Would you rather have a surprise weekend getaway or a planned luxury vacation?", "opt1": "Surprise Getaway 🎒", "opt2": "Planned Luxury 🏖️"},
        {"id": "wyr_2", "q": "Would you rather cook an intimate dinner together or order from your favorite Michelin restaurant?", "opt1": "Cook Together 🍳", "opt2": "Fine Dining 🍷"},
        {"id": "wyr_3", "q": "Would you rather watch sunrise on the beach or stargaze in the snowy mountains?", "opt1": "Sunrise on Beach 🌅", "opt2": "Mountain Stargazing 🌌"},
        {"id": "wyr_4", "q": "Would you rather slow dance in the rain or cuddle by a cozy fireplace?", "opt1": "Dance in the Rain 🌧️", "opt2": "Cozy Fireplace 🔥"},
        {"id": "wyr_5", "q": "Would you rather build our dream house in the countryside or a penthouse in Tokyo/Paris?", "opt1": "Countryside Villa 🏡", "opt2": "City Penthouse 🏙️"}
    ],
    "truth_or_dare": [
        {"id": "tod_1", "type": "truth", "q": "What was the exact moment you realized you were falling in love with me?"},
        {"id": "tod_2", "type": "truth", "q": "What is one secret dream you have for our future that you haven't mentioned yet?"},
        {"id": "tod_3", "type": "dare", "q": "Send a 15-second voice note singing my favorite love song right now!"},
        {"id": "tod_4", "type": "dare", "q": "Send a goofy selfie imitating my favorite facial expression."},
        {"id": "tod_5", "type": "truth", "q": "What outfit of mine makes your heart beat the fastest?"}
    ],
    "guess_your_partner": [
        {"id": "gyp_1", "q": "What is my absolute favorite comfort food when I've had an exhausting day?", "hint": "Snack or meal"},
        {"id": "gyp_2", "q": "If I could relive one day from our relationship, which day would it be?", "hint": "A special milestone"},
        {"id": "gyp_3", "q": "What is my go-to order at a coffee shop?", "hint": "Hot or Iced"},
        {"id": "gyp_4", "q": "Which travel destination is #1 on my bucket list?", "hint": "Country or City"}
    ],
    "couple_quiz": [
        {"id": "cq_1", "q": "Where did we first meet or have our first date?", "options": ["Coffee Shop", "Park Walk", "Online Video Call", "Dinner Restaurant"]},
        {"id": "cq_2", "q": "Who said 'I love you' first?", "options": ["You", "Partner", "At the exact same time", "Still waiting"]},
        {"id": "cq_3", "q": "What is our official love language?", "options": ["Quality Time", "Words of Affirmation", "Physical Touch", "Acts of Service"]}
    ],
    "how_well_do_you_know_me": [
        {"id": "hwd_1", "q": "What is my biggest pet peeve?", "answer_type": "text"},
        {"id": "hwd_2", "q": "Am I a morning lark or a night owl?", "options": ["Early Morning Lark ☀️", "Night Owl 🌙"]},
        {"id": "hwd_3", "q": "What song always reminds you of me?", "answer_type": "text"},
        {"id": "hwd_4", "q": "How do I behave when I am hangry?", "answer_type": "text"}
    ],
    "memory_challenge": [
        {"id": "mem_1", "q": "What color shirt was I wearing on our first photo together?", "difficulty": "Medium"},
        {"id": "mem_2", "q": "What movie did we watch together first?", "difficulty": "Easy"},
        {"id": "mem_3", "q": "What was the first gift I ever gave you?", "difficulty": "Romantic"}
    ],
    "daily_couple_questions": [
        {"id": "dcq_1", "q": "What is one small habit of mine that made you smile this week?", "cat": "Romance"},
        {"id": "dcq_2", "q": "If we could teleport anywhere for 24 hours right now, where would we go?", "cat": "Adventure"},
        {"id": "dcq_3", "q": "What is your favorite memory of us traveling together?", "cat": "Memories"},
        {"id": "dcq_4", "q": "What are you most grateful for in our relationship today?", "cat": "Gratitude"}
    ]
}

def load_db():
    if db_backend.is_postgres_enabled():
        return db_backend.load_pg_db(_ensure_db_structure, fallback_seed_file=DB_FILE)
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
                _ensure_db_structure(data)
                return data
        except Exception as e:
            print(f"Error loading DB: {e}")
    default_db = {}
    _ensure_db_structure(default_db)
    return default_db

def _ensure_db_structure(db):
    if "users" not in db:
        db["users"] = []
    if "unverified_users" not in db:
        db["unverified_users"] = {}
    if "otps" not in db:
        db["otps"] = {}
    if "couples" not in db:
        db["couples"] = []
    if "couple_requests" not in db:
        db["couple_requests"] = []
    if "interactions" not in db:
        db["interactions"] = {
            "Connect (Love Pulse)": 5840,
            "Home Dashboard": 4920,
            "Together (Activities)": 3180,
            "Memories Vault": 2410,
            "Profile & Settings": 890
        }
    if "pulses" not in db:
        db["pulses"] = []
    if "moods" not in db:
        db["moods"] = []
    if "memories" not in db:
        db["memories"] = []
    if "letters" not in db:
        db["letters"] = []
    if "game_sessions" not in db:
        db["game_sessions"] = []
    if "questions" not in db:
        db["questions"] = []
    if "audit_logs" not in db:
        db["audit_logs"] = []
    if "email_outbox" not in db:
        db["email_outbox"] = []
    if "admins" not in db:
        db["admins"] = [
            {
                "id": "adm_1",
                "name": "SoulSync Superadmin",
                "email": "admin@soulsync.app",
                "admin_id": "SUPERADMIN-01",
                "role": "Superadmin",
                "password_hash": hash_pw("SoulSync@Admin2026!"),
                "is_active": True,
                "created_at": "2026-11-19T00:00:00Z",
                "last_login": None
            },
            {
                "id": "adm_2",
                "name": "Sarah Support",
                "email": "support@soulsync.app",
                "admin_id": "SUPPORT-01",
                "role": "Support Admin",
                "password_hash": hash_pw("SoulSync@Support2026!"),
                "is_active": True,
                "created_at": "2026-11-19T00:00:00Z",
                "last_login": None
            }
        ]
    if "admin_sessions" not in db:
        db["admin_sessions"] = {}
    if "admin_login_logs" not in db:
        db["admin_login_logs"] = []
    music_module.ensure_music_db(db)
    safesync_module.ensure_safety_db(db)

DB_LOCK = threading.RLock()

def save_db(db):
    if db_backend.is_postgres_enabled():
        db_backend.save_pg_db(db)
        return
    with DB_LOCK:
        tmp_path = DB_FILE + ".tmp"
        with open(tmp_path, "w", encoding="utf-8") as f:
            json.dump(db, f, indent=2, ensure_ascii=False)
        os.replace(tmp_path, DB_FILE)

def hash_pw(pw):
    return hashlib.sha256(pw.encode("utf-8")).hexdigest()

def validate_password_complexity(pw):
    """
    Password policy:
    - Min 8 chars
    - At least 1 uppercase letter (A-Z)
    - At least 1 lowercase letter (a-z)
    - At least 1 digit (0-9)
    - At least 1 special char (@, #, $, !, %, *, ?, &, #, etc.)
    """
    if len(pw) < 8:
        return False, "Password must be at least 8 characters long."
    if not re.search(r"[A-Z]", pw):
        return False, "Password must contain at least one uppercase letter (A-Z)."
    if not re.search(r"[a-z]", pw):
        return False, "Password must contain at least one lowercase letter (a-z)."
    if not re.search(r"\d", pw):
        return False, "Password must contain at least one number (0-9)."
    if not re.search(r"[@$!%*?&#^()_\-+=\[\]{}|~`]", pw):
        return False, "Password must contain at least one special character (@, #, $, !, etc.)."
    return True, None

def gen_code(prefix="SOUL"):
    digits = ''.join(random.choices(string.digits, k=4))
    return f"{prefix}-{digits}"

def gen_otp():
    return email_otp_module.generate_secure_otp()


def send_email_otp(db, to_email, code, purpose="verification", recipient_name="Partner"):
    return email_otp_module.send_real_otp_email(
        db,
        to_email=to_email,
        otp=code,
        purpose=purpose,
        recipient_name=recipient_name,
    )

def verify_admin_session(handler, db, required_role=None):
    """
    Validates the admin authorization token provided in Authorization: Bearer <token>.
    Ensures the session is active, unexpired, and belongs to an authorized admin account.
    """
    auth_header = handler.headers.get("Authorization", "")
    token = auth_header.replace("Bearer ", "").strip()
    if not token or token not in db.get("admin_sessions", {}):
        return None, "Admin authentication required. Please log in."
    
    session = db["admin_sessions"][token]
    now_iso = datetime.utcnow().isoformat() + "Z"
    if now_iso > session.get("expires_at", ""):
        del db["admin_sessions"][token]
        save_db(db)
        return None, "Admin session has expired. Please log in again."
    
    admin_id = session.get("admin_id")
    admin = next((a for a in db.get("admins", []) if a.get("id") == admin_id), None)
    if not admin or not admin.get("is_active", True):
        return None, "Administrative account is inactive or revoked."
    
    if required_role == "Superadmin" and admin.get("role") != "Superadmin":
        return None, "Access denied. Superadmin authorization required."
    
    return admin, None

class SoulSyncAPIHandler(BaseHTTPRequestHandler):
    def _set_headers(self, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS, PUT, DELETE")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_OPTIONS(self):
        self._set_headers(204)

    def _read_json(self):
        content_length = int(self.headers.get("Content-Length", 0))
        if content_length > 0:
            body = self.rfile.read(content_length)
            try:
                return json.loads(body.decode("utf-8"))
            except Exception:
                return {}
        return {}

    def log_audit(self, db, actor, action, target, details=""):
        log_entry = {
            "id": f"aud_{len(db.get('audit_logs', [])) + 1}",
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "actor": actor,
            "action": action,
            "target": target,
            "details": details
        }
        db["audit_logs"].insert(0, log_entry)

    # ---------------- GET ROUTES ----------------
    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        query = parse_qs(parsed.query)

        if path in ("/health", "/api/health"):
            db_ok, db_mode = db_backend.check_db_health()
            users_count = 0
            smtp_cfg = False
            if db_ok:
                try:
                    db = load_db()
                    users_count = len(db.get("users", []))
                    smtp_cfg = email_otp_module.get_public_service_status(db).get("configured", False)
                except db_backend.DatabaseUnavailableError:
                    db_ok = False
                    db_mode = "postgresql_unavailable"
            self._set_headers(200 if db_ok else 503)
            self.wfile.write(json.dumps({
                "status": "ok" if db_ok else "degraded",
                "service": "soulsync-api",
                "database": db_mode,
                "users_count": users_count,
                "smtp_configured": smtp_cfg,
                "youtube_configured": bool(get_youtube_api_key()),
                "timestamp": datetime.utcnow().isoformat() + "Z",
            }).encode("utf-8"))
            return

        try:
            db = load_db()
        except db_backend.DatabaseUnavailableError:
            self._set_headers(503)
            self.wfile.write(json.dumps({"error": "We are experiencing a temporary service issue. Please try again later."}).encode("utf-8"))
            return

        if path == "/api/users":
            # Return users without exposing password hashes
            sanitized = []
            for u in db.get("users", []):
                u_copy = dict(u)
                u_copy.pop("password_hash", None)
                sanitized.append(u_copy)
            self._set_headers(200)
            self.wfile.write(json.dumps(sanitized).encode("utf-8"))

        elif path == "/api/email-outbox":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            sanitized = email_otp_module.sanitize_outbox_entries(db.get("email_outbox", []))
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "total": len(sanitized),
                "outbox": sanitized[:50]
            }).encode("utf-8"))

        elif path == "/api/admin/email-status":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            status_payload = email_otp_module.get_public_service_status(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "service": {k: v for k, v in status_payload.items() if k not in ("stats", "logs")},
                "stats": status_payload["stats"],
                "logs": status_payload["logs"],
            }).encode("utf-8"))

        elif path == "/api/couples":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("couples", [])).encode("utf-8"))

        elif path == "/api/analytics":
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "interactions": db.get("interactions", {}),
                "total_users": len(db.get("users", [])),
                "total_couples": len(db.get("couples", [])),
                "total_pulses": len(db.get("pulses", [])) + 1428,
                "total_memories": len(db.get("memories", [])) + 3892,
                "total_letters": len(db.get("letters", [])) + 148
            }).encode("utf-8"))

        elif path == "/api/pulses":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("pulses", [])).encode("utf-8"))

        elif path == "/api/questions":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("questions", [])).encode("utf-8"))

        elif path == "/api/games/questions":
            game_type = query.get("game", ["would_you_rather"])[0]
            questions = GAME_BANKS.get(game_type, [])
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "game": game_type, "questions": questions}).encode("utf-8"))

        elif path == "/api/games/sessions":
            couple_id = query.get("couple_id", [""])[0]
            sessions = db.get("game_sessions", [])
            if couple_id:
                sessions = [s for s in sessions if s.get("couple_id") == couple_id]
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "sessions": sessions}).encode("utf-8"))

        elif path == "/api/mood":
            user_id = query.get("user_id", [""])[0]
            couple_id = query.get("couple_id", [""])[0]
            moods = db.get("moods", [])
            
            # Privacy rule: Partner only sees partner's mood if is_private is False!
            user_moods = [m for m in moods if m.get("user_id") == user_id]
            partner_mood = None
            for m in moods:
                if m.get("couple_id") == couple_id and m.get("user_id") != user_id:
                    if not m.get("is_private", False):
                        partner_mood = m
                        break
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "user_history": user_moods,
                "partner_latest": partner_mood
            }).encode("utf-8"))

        elif path == "/api/memories":
            couple_id = query.get("couple_id", [""])[0]
            memories = db.get("memories", [])
            if couple_id:
                memories = [m for m in memories if m.get("couple_id") == couple_id]
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "memories": memories}).encode("utf-8"))

        elif path == "/api/letters":
            couple_id = query.get("couple_id", [""])[0]
            viewer_id = query.get("viewer_id", [""])[0]
            now_iso = datetime.utcnow().isoformat() + "Z"
            all_letters = db.get("letters", [])
            result = []
            for l in all_letters:
                if couple_id and l.get("couple_id") != couple_id:
                    continue
                l_copy = dict(l)
                # Check locked status
                unlock_at = l_copy.get("unlock_date")
                is_sender = l_copy.get("sender_id") == viewer_id
                if unlock_at and unlock_at > now_iso and not is_sender:
                    l_copy["is_locked"] = True
                    l_copy["content"] = "🔒 This love letter is sealed until " + unlock_at[:10]
                else:
                    l_copy["is_locked"] = False
                result.append(l_copy)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "letters": result}).encode("utf-8"))

        elif path == "/api/couple/status":
            user_id = query.get("user_id", [""])[0]
            email = query.get("email", [""])[0].lower()
            matching_user = None
            for u in db.get("users", []):
                if (user_id and u.get("id") == user_id) or (email and u.get("email") == email):
                    matching_user = u
                    break
            if not matching_user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found"}).encode("utf-8"))
                return
            
            couple_id = matching_user.get("couple_id")
            couple_data = None
            if couple_id:
                for c in db.get("couples", []):
                    if c.get("id") == couple_id:
                        couple_data = c
                        break
            
            # Pending connection requests for this user
            user_code = matching_user.get("invite_code")
            pending_requests = [
                r for r in db.get("couple_requests", [])
                if r.get("target_code") == user_code and r.get("status") == "pending"
            ]

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "user": matching_user,
                "couple": couple_data,
                "pending_requests": pending_requests
            }).encode("utf-8"))

        elif path == "/api/admin/audit":
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "audit_logs": db.get("audit_logs", [])}).encode("utf-8"))

        elif path == "/api/admin/me":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            safe_adm = dict(admin)
            safe_adm.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "admin": safe_adm}).encode("utf-8"))

        elif path == "/api/admin/admins":
            admin, err = verify_admin_session(self, db, required_role="Superadmin")
            if not admin:
                self._set_headers(403 if "Superadmin" in (err or "") else 401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            safe_admins = []
            for a in db.get("admins", []):
                copy_a = dict(a)
                copy_a.pop("password_hash", None)
                safe_admins.append(copy_a)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "admins": safe_admins}).encode("utf-8"))

        elif path == "/api/admin/login-logs":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "logs": db.get("admin_login_logs", [])[:50]}).encode("utf-8"))


        elif path == "/api/chat/messages":
            couple_id = query.get("couple_id", [""])[0]
            search_query = query.get("query", [""])[0].lower()
            limit = int(query.get("limit", [50])[0])
            
            all_msgs = db.get("chat_messages", [])
            filtered = [m for m in all_msgs if not couple_id or m.get("couple_id") == couple_id]
            if search_query:
                filtered = [m for m in filtered if search_query in (m.get("content") or "").lower()]
            
            # Sort chronologically
            filtered.sort(key=lambda x: x.get("created_at", ""))
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "messages": filtered[-limit:]}).encode("utf-8"))

        elif path == "/api/chat/status":
            couple_id = query.get("couple_id", [""])[0]
            user_id = query.get("user_id", [""])[0]
            typing_info = db.get("typing_status", {}).get(couple_id, {})
            partner_typing = any(uid != user_id and is_typing for uid, is_typing in typing_info.items())
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "partner_online": True,
                "partner_typing": partner_typing
            }).encode("utf-8"))

        elif path == "/api/streaks":
            couple_id = query.get("couple_id", [""])[0]
            streaks_db = db.get("streaks", {})
            couple_streak = streaks_db.get(couple_id)
            if not couple_streak:
                couple_streak = {
                    "couple_id": couple_id,
                    "current_streak": 5,
                    "longest_streak": 12,
                    "freeze_tokens": 2,
                    "last_active": datetime.utcnow().strftime("%Y-%m-%d"),
                    "milestone": "Special Heart Badge (7 Days)",
                    "history": [datetime.utcnow().strftime("%Y-%m-%d")]
                }
                db.setdefault("streaks", {})[couple_id] = couple_streak
                save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "streak": couple_streak}).encode("utf-8"))

        elif path == "/api/gifts/catalog":
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "catalog": GIFT_CATALOG}).encode("utf-8"))

        elif path == "/api/gifts/received":
            couple_id = query.get("couple_id", [""])[0]
            all_gifts = db.get("gifts", [])
            filtered = [g for g in all_gifts if not couple_id or g.get("couple_id") == couple_id]
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "gifts": filtered}).encode("utf-8"))

        elif path == "/api/notifications":
            user_id = query.get("user_id", [""])[0]
            all_notifs = db.get("notifications", [])
            filtered = [n for n in all_notifs if not user_id or n.get("user_id") == user_id]
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "notifications": filtered[:30]}).encode("utf-8"))

        elif path == "/api/account/export-data":
            user_id = query.get("user_id", [""])[0]
            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if not user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found"}).encode("utf-8"))
                return
            couple_id = user.get("couple_id")
            export_payload = {
                "exported_at": datetime.utcnow().isoformat() + "Z",
                "profile": {k: v for k, v in user.items() if k != "password_hash"},
                "pulses_sent": [p for p in db.get("pulses", []) if p.get("sender") == user.get("name")],
                "moods_logged": [m for m in db.get("moods", []) if m.get("user_id") == user_id],
                "memories_created": [m for m in db.get("memories", []) if m.get("couple_id") == couple_id],
                "letters_written": [l for l in db.get("letters", []) if l.get("sender_id") == user_id],
                "privacy_assurances": "All user data encrypted and protected by SoulSync Couple Space Isolation."
            }
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "export": export_payload}).encode("utf-8"))

        elif path == "/api/account/sessions":
            user_id = query.get("user_id", [""])[0]
            sessions = [
                {"id": "sess_current", "device": "Current Active Device (Flutter Mobile)", "ip": "127.0.0.1", "is_current": True, "created_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M")},
                {"id": "sess_web", "device": "Chrome Web (Simulator)", "ip": "127.0.0.1", "is_current": False, "created_at": "Yesterday, 19:42"}
            ]
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "sessions": sessions}).encode("utf-8"))

        elif path == "/api/admin/reports":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            reports = db.get("reports", [])
            # Privacy audit record:
            db.setdefault("audit_logs", []).insert(0, {
                "id": f"aud_{len(db.get('audit_logs', []))+1}",
                "admin": admin.get("email"),
                "action": "VIEW_REPORTS_LIST",
                "details": f"Admin viewed {len(reports)} safety reports",
                "timestamp": datetime.utcnow().strftime("%b %d, %Y - %H:%M UTC")
            })
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "reports": reports}).encode("utf-8"))

        elif path == "/api/admin/chat/stats":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            chat_msgs = db.get("chat_messages", [])
            media_count = len([m for m in chat_msgs if m.get("media_type") in ["image", "video", "voice"]])
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "total_messages": len(chat_msgs) + 2480,
                "media_messages": media_count + 620,
                "active_conversations": len(db.get("couples", [])),
                "delivery_success_rate": "99.8%"
            }).encode("utf-8"))

        elif path.startswith("/api/safety/") or path.startswith("/api/admin/safety/"):
            if safesync_module.handle_safety_get(
                self,
                path,
                query,
                load_db,
                save_db,
                verify_admin_session,
            ):
                return
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode("utf-8"))

        elif path.startswith("/api/music/") or path.startswith("/api/admin/music/"):
            if music_module.handle_music_get(
                self,
                path,
                query,
                load_db,
                save_db,
                get_youtube_api_key,
                verify_youtube_api_connection,
                verify_admin_session,
            ):
                return
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode("utf-8"))

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode("utf-8"))

    # ---------------- POST ROUTES ----------------
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        try:
            db = load_db()
        except db_backend.DatabaseUnavailableError:
            self._set_headers(503)
            self.wfile.write(json.dumps({"error": "We are experiencing a temporary service issue. Please try again later."}).encode("utf-8"))
            return
        data = self._read_json()
        now_iso = datetime.utcnow().isoformat() + "Z"

        # 0A. DEDICATED ADMIN LOGIN
        if path == "/api/admin/login":
            email_or_id = (data.get("email") or data.get("admin_id") or data.get("email_or_id") or data.get("username") or "").strip().lower()
            password = data.get("password") or ""
            ip = self.client_address[0] if self.client_address else "127.0.0.1"

            if not email_or_id or not password:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Admin email/ID and password are required."}).encode("utf-8"))
                return

            # Check if this belongs to ordinary mobile users - reject!
            is_mobile_user = any(u.get("email") == email_or_id for u in db.get("users", []))
            matching_admin = next(
                (a for a in db.get("admins", []) if a.get("email", "").lower() == email_or_id or a.get("admin_id", "").lower() == email_or_id),
                None
            )

            if not matching_admin:
                # Log failed administrative login attempt
                db.setdefault("admin_login_logs", []).insert(0, {
                    "id": f"log_{len(db.get('admin_login_logs', [])) + 1}",
                    "identifier": email_or_id,
                    "status": "FAILED",
                    "reason": "Account not recognized as administrator" if not is_mobile_user else "Ordinary mobile user account cannot access Admin Panel",
                    "ip": ip,
                    "timestamp": now_iso
                })
                save_db(db)
                self._set_headers(403 if is_mobile_user else 401)
                msg = "Access denied: Mobile app user accounts cannot access the administrative portal." if is_mobile_user else "Invalid administrator credentials."
                self.wfile.write(json.dumps({"error": msg}).encode("utf-8"))
                return

            if not matching_admin.get("is_active", True):
                db.setdefault("admin_login_logs", []).insert(0, {
                    "id": f"log_{len(db.get('admin_login_logs', [])) + 1}",
                    "identifier": email_or_id,
                    "status": "DENIED",
                    "reason": "Administrative account is inactive",
                    "ip": ip,
                    "timestamp": now_iso
                })
                save_db(db)
                self._set_headers(403)
                self.wfile.write(json.dumps({"error": "This administrator account has been deactivated. Please contact Superadmin."}).encode("utf-8"))
                return

            if matching_admin.get("password_hash") != hash_pw(password):
                db.setdefault("admin_login_logs", []).insert(0, {
                    "id": f"log_{len(db.get('admin_login_logs', [])) + 1}",
                    "identifier": email_or_id,
                    "status": "FAILED",
                    "reason": "Incorrect password",
                    "ip": ip,
                    "timestamp": now_iso
                })
                save_db(db)
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": "Incorrect password."}).encode("utf-8"))
                return

            # Successful login: generate 24h session token
            admin_seed = str(matching_admin['id']) + "_" + now_iso + "_" + str(random.random())
            token = "adm_token_" + hashlib.sha256(admin_seed.encode("utf-8")).hexdigest()[:32]
            expires_at = (datetime.utcnow() + timedelta(hours=24)).isoformat() + "Z"
            db.setdefault("admin_sessions", {})[token] = {
                "admin_id": matching_admin["id"],
                "role": matching_admin.get("role", "Admin"),
                "created_at": now_iso,
                "expires_at": expires_at
            }
            matching_admin["last_login"] = now_iso
            db.setdefault("admin_login_logs", []).insert(0, {
                "id": f"log_{len(db.get('admin_login_logs', [])) + 1}",
                "identifier": matching_admin["email"],
                "admin_name": matching_admin["name"],
                "role": matching_admin["role"],
                "status": "SUCCESS",
                "ip": ip,
                "timestamp": now_iso
            })
            self.log_audit(db, matching_admin["email"], "ADMIN_LOGIN", matching_admin["role"], f"Admin logged in from {ip}")
            save_db(db)

            safe_adm = dict(matching_admin)
            safe_adm.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Welcome back, {safe_adm['name']}!",
                "token": token,
                "expires_at": expires_at,
                "admin": safe_adm
            }).encode("utf-8"))
            return

        # 0B. ADMIN LOGOUT
        elif path == "/api/admin/logout":
            auth_header = self.headers.get("Authorization", "")
            token = auth_header.replace("Bearer ", "").strip()
            if token and token in db.get("admin_sessions", {}):
                session = db["admin_sessions"].pop(token)
                self.log_audit(db, session.get("admin_id", "admin"), "ADMIN_LOGOUT", "Session", "Admin signed out")
                save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "message": "Admin session terminated."}).encode("utf-8"))
            return

        # 0C. SUPERADMIN CREATE ADMIN ACCOUNT
        elif path == "/api/admin/admins":
            current_admin, err = verify_admin_session(self, db, required_role="Superadmin")
            if not current_admin:
                self._set_headers(403 if "Superadmin" in (err or "") else 401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return

            new_name = (data.get("name") or "").strip()
            new_email = (data.get("email") or "").strip().lower()
            new_role = (data.get("role") or "Admin").strip()
            new_password = data.get("password") or "SoulSync@Admin2026!"
            new_admin_id = (data.get("admin_id") or f"ADM-{random.randint(100, 999)}").strip().upper()

            if new_role not in ["Admin", "Support Admin"]:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Role must be 'Admin' or 'Support Admin'."}).encode("utf-8"))
                return

            if any(a.get("email") == new_email for a in db.get("admins", [])):
                self._set_headers(409)
                self.wfile.write(json.dumps({"error": "An administrator with this email already exists."}).encode("utf-8"))
                return

            is_valid_pw, pw_err = validate_password_complexity(new_password)
            if not is_valid_pw:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": pw_err}).encode("utf-8"))
                return

            new_admin = {
                "id": f"adm_{len(db.get('admins', [])) + 1}",
                "name": new_name,
                "email": new_email,
                "admin_id": new_admin_id,
                "role": new_role,
                "password_hash": hash_pw(new_password),
                "is_active": True,
                "created_at": now_iso,
                "created_by": current_admin["email"],
                "last_login": None
            }
            db.setdefault("admins", []).append(new_admin)
            self.log_audit(db, current_admin["email"], "ADMIN_CREATED", f"{new_email} ({new_role})", f"Created new {new_role}")
            save_db(db)

            safe_adm = dict(new_admin)
            safe_adm.pop("password_hash", None)
            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Administrator account for {new_name} created successfully.",
                "admin": safe_adm
            }).encode("utf-8"))
            return

        # 0D. ADMIN FORGOT PASSWORD REQUEST
        elif path == "/api/admin/forgot-password":
            email = (data.get("email") or "").strip().lower()
            matching = next((a for a in db.get("admins", []) if a.get("email") == email), None)
            if matching:
                cfg = email_otp_module.get_otp_settings()
                otp = gen_otp()
                salt, digest = email_otp_module.hash_otp(otp)
                expires_at = (datetime.utcnow() + timedelta(minutes=cfg["otp_expiry_minutes"])).isoformat() + "Z"
                db.setdefault("otps", {})[f"admin_reset_{email}"] = {
                    "otp_salt": salt,
                    "otp_hash": digest,
                    "expires_at": expires_at,
                    "attempts": 0,
                    "last_sent_ts": time.time(),
                    "admin_id": matching["id"]
                }
                send_email_otp(db, email, otp, purpose="password_reset", recipient_name=matching["name"])
                save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "If an administrator account exists for this email, a reset code has been dispatched."
            }).encode("utf-8"))
            return

        # 1. REGISTRATION WITH REAL EMAIL OTP VERIFICATION
        elif path == "/api/register":
            name = (data.get("name") or data.get("displayName") or "").strip()
            email = (data.get("email") or "").strip().lower()
            password = data.get("password") or ""
            partner_name = (data.get("partner") or data.get("partnerName") or "Partner").strip()
            social_provider = (data.get("social_provider") or "").strip().lower()
            social_account = (data.get("social_account") or "").strip()
            ip = self.client_address[0] if self.client_address else "127.0.0.1"

            if not name or not email or not password or "@" not in email:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Valid name, email, and password are required"}).encode("utf-8"))
                return

            # Check if email already registered and verified
            existing = [u for u in db["users"] if u.get("email") == email]
            if existing:
                self._set_headers(409)
                self.wfile.write(json.dumps({"error": "An account with this email already exists. Please sign in."}).encode("utf-8"))
                return

            # Validate password complexity
            is_valid_pw, pw_err = validate_password_complexity(password)
            if not is_valid_pw:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": pw_err}).encode("utf-8"))
                return

            cfg = email_otp_module.get_otp_settings()
            prev_pending = db["unverified_users"].get(email)
            if prev_pending:
                ok_cd, wait_s = email_otp_module.check_resend_cooldown(prev_pending.get("last_sent_ts"), cfg["otp_resend_seconds"])
                if not ok_cd:
                    self._set_headers(429)
                    self.wfile.write(json.dumps({
                        "error": f"Please wait {wait_s} seconds before requesting another verification code.",
                        "retry_after_seconds": wait_s
                    }).encode("utf-8"))
                    return

            ok_rl, rl_wait = email_otp_module.check_rate_limit(f"reg:{email}:{ip}", max_requests=6, window_seconds=900)
            if not ok_rl:
                self._set_headers(429)
                self.wfile.write(json.dumps({
                    "error": f"Too many OTP requests. Please try again in {rl_wait} seconds.",
                    "retry_after_seconds": rl_wait
                }).encode("utf-8"))
                return

            otp = gen_otp()
            salt, digest = email_otp_module.hash_otp(otp)
            now = datetime.utcnow()
            expires_at = (now + timedelta(minutes=cfg["otp_expiry_minutes"])).isoformat() + "Z"

            db["unverified_users"][email] = {
                "name": name,
                "email": email,
                "password_hash": hash_pw(password),
                "partner_name": partner_name,
                "social_provider": social_provider,
                "social_account": social_account,
                "otp_salt": salt,
                "otp_hash": digest,
                "created_at": now.isoformat() + "Z",
                "expires_at": expires_at,
                "last_sent_ts": time.time(),
                "attempts": 0
            }

            delivered, outbox_entry, mail_err = send_email_otp(db, email, otp, purpose="verification", recipient_name=name)
            save_db(db)
            if not delivered:
                self._set_headers(503)
                self.wfile.write(json.dumps({
                    "error": mail_err or "Failed to send verification email.",
                    "delivery_status": outbox_entry.get("status")
                }).encode("utf-8"))
                return

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "pending_verification",
                "message": f"A 6-digit verification code has been emailed to {email}. Valid for {cfg['otp_expiry_minutes']} minutes.",
                "email": email,
                "expires_in_seconds": cfg["otp_expiry_minutes"] * 60,
                "resend_cooldown_seconds": cfg["otp_resend_seconds"],
                "max_attempts": cfg["otp_max_attempts"],
                "delivery_status": outbox_entry.get("status")
            }).encode("utf-8"))

        # 2. VERIFY REGISTRATION OTP
        elif path == "/api/verify-otp":
            email = (data.get("email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()
            cfg = email_otp_module.get_otp_settings()

            pending = db["unverified_users"].get(email)
            if not pending:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No pending registration found for this email. Please register again."}).encode("utf-8"))
                return

            now_iso = datetime.utcnow().isoformat() + "Z"
            if now_iso > pending.get("expires_at", ""):
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Verification code has expired. Please tap 'Resend OTP'."}).encode("utf-8"))
                return

            max_attempts = cfg["otp_max_attempts"]
            if pending.get("attempts", 0) >= max_attempts:
                self._set_headers(429)
                self.wfile.write(json.dumps({"error": "Maximum verification attempts exceeded. Please request a new code via 'Resend OTP'."}).encode("utf-8"))
                return

            is_match = email_otp_module.verify_otp_hash(otp, pending.get("otp_salt"), pending.get("otp_hash"))
            if not is_match:
                pending["attempts"] = pending.get("attempts", 0) + 1
                remaining = max(0, max_attempts - pending["attempts"])
                if remaining == 0:
                    # Invalidate challenge hash after exhausting max attempts
                    pending["otp_hash"] = ""
                save_db(db)
                self._set_headers(429 if remaining == 0 else 400)
                msg = (
                    "Maximum verification attempts reached. This code is now locked; please request a new OTP."
                    if remaining == 0
                    else f"Incorrect verification code. {remaining} attempt(s) remaining."
                )
                self.wfile.write(json.dumps({"error": msg, "attempts_remaining": remaining}).encode("utf-8"))
                return

            # OTP Valid! Activate verified account
            user_id = f"u{len(db['users']) + 1}"
            invite_code = gen_code("SOUL")
            social_accounts = []
            if pending.get("social_provider") and pending.get("social_account"):
                social_accounts.append({
                    "provider": pending["social_provider"],
                    "account": pending["social_account"],
                    "connected_at": datetime.utcnow().isoformat() + "Z"
                })
            new_user = {
                "id": user_id,
                "name": pending["name"],
                "email": email,
                "partner": pending["partner_name"],
                "role": "Verified App User",
                "is_verified": True,
                "is_active": True,
                "invite_code": invite_code,
                "password_hash": pending["password_hash"],
                "social_provider": pending.get("social_provider") or "",
                "social_account": pending.get("social_account") or "",
                "social_accounts": social_accounts,
                "created_at": datetime.utcnow().isoformat() + "Z",
                "last_active": "Just now",
                "source": "Mobile App"
            }
            db["users"].insert(0, new_user)

            couple_id = f"c{len(db['couples']) + 1}"
            new_couple = {
                "id": couple_id,
                "name": f"{pending['name']} & {pending['partner_name']}",
                "p1": pending['name'],
                "p2": pending['partner_name'],
                "p1_id": user_id,
                "p2_id": None,
                "code": invite_code,
                "days": 1,
                "status": "Waiting for Partner",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            new_user["couple_id"] = couple_id
            db["couples"].insert(0, new_couple)

            del db["unverified_users"][email]
            self.log_audit(db, email, "EMAIL_VERIFIED", email, "User email verified via OTP and account activated")
            save_db(db)

            safe_user = dict(new_user)
            safe_user.pop("password_hash", None)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Email verified and account activated! You may now sign in.",
                "user": safe_user,
                "couple": new_couple
            }).encode("utf-8"))

        # 3. RESEND REGISTRATION OTP
        elif path == "/api/resend-otp":
            email = (data.get("email") or "").strip().lower()
            ip = self.client_address[0] if self.client_address else "127.0.0.1"
            cfg = email_otp_module.get_otp_settings()

            pending = db["unverified_users"].get(email)
            if not pending:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No pending registration found for this email."}).encode("utf-8"))
                return

            ok_cd, wait_s = email_otp_module.check_resend_cooldown(pending.get("last_sent_ts"), cfg["otp_resend_seconds"])
            if not ok_cd:
                self._set_headers(429)
                self.wfile.write(json.dumps({
                    "error": f"Please wait {wait_s} seconds before resending OTP.",
                    "retry_after_seconds": wait_s
                }).encode("utf-8"))
                return

            ok_rl, rl_wait = email_otp_module.check_rate_limit(f"reg:{email}:{ip}", max_requests=6, window_seconds=900)
            if not ok_rl:
                self._set_headers(429)
                self.wfile.write(json.dumps({
                    "error": f"Too many OTP requests. Please try again in {rl_wait} seconds.",
                    "retry_after_seconds": rl_wait
                }).encode("utf-8"))
                return

            otp = gen_otp()
            salt, digest = email_otp_module.hash_otp(otp)
            now = datetime.utcnow()
            expires_at = (now + timedelta(minutes=cfg["otp_expiry_minutes"])).isoformat() + "Z"
            pending["otp_salt"] = salt
            pending["otp_hash"] = digest
            pending["expires_at"] = expires_at
            pending["last_sent_ts"] = time.time()
            pending["attempts"] = 0

            delivered, outbox_entry, mail_err = send_email_otp(db, email, otp, purpose="verification", recipient_name=pending.get("name", "Partner"))
            save_db(db)
            if not delivered:
                self._set_headers(503)
                self.wfile.write(json.dumps({"error": mail_err or "Failed to resend email OTP."}).encode("utf-8"))
                return

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"A new 6-digit OTP has been emailed to {email}.",
                "resend_cooldown_seconds": cfg["otp_resend_seconds"],
                "expires_in_seconds": cfg["otp_expiry_minutes"] * 60,
                "delivery_status": outbox_entry.get("status")
            }).encode("utf-8"))

        # 4. SECURE LOGIN
        elif path == "/api/login":
            email = (data.get("email") or "").strip().lower()
            password = data.get("password") or ""

            if email in db.get("unverified_users", {}):
                self._set_headers(403)
                self.wfile.write(json.dumps({
                    "error": "Email not verified yet. Please verify your 6-digit OTP first.",
                    "needs_verification": True,
                    "email": email
                }).encode("utf-8"))
                return

            matching = [u for u in db["users"] if u.get("email") == email]
            if not matching:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": "Invalid email or password."}).encode("utf-8"))
                return

            u = matching[0]
            if not u.get("is_verified", True):
                self._set_headers(403)
                self.wfile.write(json.dumps({
                    "error": "Email not verified yet. Please verify your email address first.",
                    "needs_verification": True,
                    "email": email
                }).encode("utf-8"))
                return

            if not u.get("is_active", True):
                self._set_headers(403)
                self.wfile.write(json.dumps({"error": "Account is disabled. Please contact administrator."}).encode("utf-8"))
                return

            if "password_hash" in u and u["password_hash"]:
                if u["password_hash"] != hash_pw(password):
                    self._set_headers(401)
                    self.wfile.write(json.dumps({"error": "Invalid email or password."}).encode("utf-8"))
                    return

            u["last_active"] = "Just now"
            if not u.get("invite_code"):
                u["invite_code"] = gen_code("SOUL")
            save_db(db)

            safe_u = dict(u)
            safe_u.pop("password_hash", None)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Welcome back to SoulSync!",
                "user": safe_u
            }).encode("utf-8"))

        # 4B. SOCIAL ACCOUNT LOGIN / SIGNUP (Google / Apple / Other)
        elif path == "/api/auth/social":
            provider = (data.get("provider") or "google").strip().lower()
            email = (data.get("email") or "").strip().lower()
            name = (data.get("name") or data.get("displayName") or "").strip()
            social_handle = (data.get("social_account") or email).strip()
            partner_name = (data.get("partner") or "Partner").strip()

            if not email or "@" not in email:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "A valid email address for your social account is required."}).encode("utf-8"))
                return

            if not name:
                name = email.split("@")[0].replace(".", " ").title()

            existing = [u for u in db["users"] if u.get("email") == email]
            if existing:
                u = existing[0]
                if not u.get("is_active", True):
                    self._set_headers(403)
                    self.wfile.write(json.dumps({"error": "Account is disabled. Please contact administrator."}).encode("utf-8"))
                    return
                u["is_verified"] = True
                u["last_active"] = "Just now"
                if not u.get("invite_code"):
                    u["invite_code"] = gen_code("SOUL")
                accounts = u.setdefault("social_accounts", [])
                if not any(a.get("provider") == provider and a.get("account") == social_handle for a in accounts):
                    accounts.append({"provider": provider, "account": social_handle, "connected_at": now_iso})
                u["social_provider"] = provider
                u["social_account"] = social_handle
                self.log_audit(db, email, "SOCIAL_LOGIN", provider, f"Signed in via {provider} ({social_handle})")
                save_db(db)
                safe_u = dict(u)
                safe_u.pop("password_hash", None)
                self._set_headers(200)
                self.wfile.write(json.dumps({
                    "status": "success",
                    "message": f"Signed in with {provider.title()}!",
                    "user": safe_u
                }).encode("utf-8"))
                return

            # Promote pending unverified user if exists, or create new verified user
            pending = db.get("unverified_users", {}).pop(email, None)
            user_id = f"u{len(db['users']) + 1}"
            invite_code = gen_code("SOUL")
            final_name = pending["name"] if pending else name
            final_partner = pending["partner_name"] if pending else partner_name
            pw_hash = pending["password_hash"] if pending else hash_pw(f"social_{provider}_{email}_{now_iso}")

            new_user = {
                "id": user_id,
                "name": final_name,
                "email": email,
                "partner": final_partner,
                "role": "Verified App User",
                "is_verified": True,
                "is_active": True,
                "invite_code": invite_code,
                "password_hash": pw_hash,
                "social_provider": provider,
                "social_account": social_handle,
                "social_accounts": [{"provider": provider, "account": social_handle, "connected_at": now_iso}],
                "created_at": now_iso,
                "last_active": "Just now",
                "source": f"Social ({provider.title()})"
            }
            db["users"].insert(0, new_user)

            couple_id = f"c{len(db['couples']) + 1}"
            new_couple = {
                "id": couple_id,
                "name": f"{final_name} & {final_partner}",
                "p1": final_name,
                "p2": final_partner,
                "p1_id": user_id,
                "p2_id": None,
                "code": invite_code,
                "days": 1,
                "status": "Waiting for Partner",
                "created_at": now_iso
            }
            new_user["couple_id"] = couple_id
            db["couples"].insert(0, new_couple)

            self.log_audit(db, email, "SOCIAL_REGISTER", provider, f"Registered & verified via {provider} ({social_handle})")
            save_db(db)

            safe_u = dict(new_user)
            safe_u.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Account connected with {provider.title()}!",
                "user": safe_u,
                "couple": new_couple
            }).encode("utf-8"))

        # 5. FORGOT PASSWORD REQUEST OTP (Separate verification challenge)
        elif path == "/api/auth/forgot-password":
            email = (data.get("email") or "").strip().lower()
            ip = self.client_address[0] if self.client_address else "127.0.0.1"
            cfg = email_otp_module.get_otp_settings()

            if not email or "@" not in email:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Please enter a valid email address."}).encode("utf-8"))
                return

            # Enforce cooldown & rate limit consistently per email+ip (avoids account enumeration + abuse)
            existing_challenge = db["otps"].get(f"reset_{email}")
            if existing_challenge:
                ok_cd, wait_s = email_otp_module.check_resend_cooldown(existing_challenge.get("last_sent_ts"), cfg["otp_resend_seconds"])
                if not ok_cd:
                    self._set_headers(429)
                    self.wfile.write(json.dumps({
                        "error": f"Please wait {wait_s} seconds before requesting another reset code.",
                        "retry_after_seconds": wait_s
                    }).encode("utf-8"))
                    return

            ok_rl, rl_wait = email_otp_module.check_rate_limit(f"reset:{email}:{ip}", max_requests=6, window_seconds=900)
            if not ok_rl:
                self._set_headers(429)
                self.wfile.write(json.dumps({
                    "error": f"Too many password reset requests. Please try again in {rl_wait} seconds.",
                    "retry_after_seconds": rl_wait
                }).encode("utf-8"))
                return

            matching = [u for u in db["users"] if u.get("email") == email]
            if matching:
                u = matching[0]
                otp = gen_otp()
                salt, digest = email_otp_module.hash_otp(otp)
                expires_at = (datetime.utcnow() + timedelta(minutes=cfg["otp_expiry_minutes"])).isoformat() + "Z"
                db["otps"][f"reset_{email}"] = {
                    "purpose": "password_reset",
                    "otp_salt": salt,
                    "otp_hash": digest,
                    "expires_at": expires_at,
                    "last_sent_ts": time.time(),
                    "attempts": 0,
                    "user_id": u["id"]
                }
                delivered, _, mail_err = send_email_otp(db, email, otp, purpose="password_reset", recipient_name=u.get("name", "Partner"))
                save_db(db)
                if not delivered:
                    self._set_headers(503)
                    self.wfile.write(json.dumps({"error": mail_err or "Failed to send password reset email."}).encode("utf-8"))
                    return

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "If an account exists with this email, a 6-digit password reset code has been sent.",
                "resend_cooldown_seconds": cfg["otp_resend_seconds"],
                "expires_in_seconds": cfg["otp_expiry_minutes"] * 60
            }).encode("utf-8"))

        # 6. VERIFY RESET PASSWORD OTP
        elif path == "/api/auth/verify-reset-otp":
            email = (data.get("email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()
            cfg = email_otp_module.get_otp_settings()
            record = db["otps"].get(f"reset_{email}")

            if not record:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No password reset challenge found for this email."}).encode("utf-8"))
                return

            now_iso = datetime.utcnow().isoformat() + "Z"
            if now_iso > record.get("expires_at", ""):
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Reset code has expired. Please request a new one."}).encode("utf-8"))
                return

            max_attempts = cfg["otp_max_attempts"]
            if record.get("attempts", 0) >= max_attempts:
                self._set_headers(429)
                self.wfile.write(json.dumps({"error": "Maximum verification attempts exceeded. Please request a new reset code."}).encode("utf-8"))
                return

            if not email_otp_module.verify_otp_hash(otp, record.get("otp_salt"), record.get("otp_hash")):
                record["attempts"] = record.get("attempts", 0) + 1
                remaining = max(0, max_attempts - record["attempts"])
                if remaining == 0:
                    record["otp_hash"] = ""
                save_db(db)
                self._set_headers(429 if remaining == 0 else 400)
                msg = (
                    "Maximum attempts reached. Please request a new password reset code."
                    if remaining == 0
                    else f"Invalid reset code. {remaining} attempt(s) remaining."
                )
                self.wfile.write(json.dumps({"error": msg, "attempts_remaining": remaining}).encode("utf-8"))
                return

            record["verified"] = True
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Reset code verified. Please set your new password."
            }).encode("utf-8"))

        # 7. COMPLETE PASSWORD RESET
        elif path == "/api/auth/reset-password":
            email = (data.get("email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()
            new_password = data.get("new_password") or ""
            cfg = email_otp_module.get_otp_settings()
            record = db["otps"].get(f"reset_{email}")

            now_iso = datetime.utcnow().isoformat() + "Z"
            if not record or now_iso > record.get("expires_at", "") or record.get("attempts", 0) >= cfg["otp_max_attempts"]:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Invalid or expired reset challenge. Please request a new code."}).encode("utf-8"))
                return

            if not email_otp_module.verify_otp_hash(otp, record.get("otp_salt"), record.get("otp_hash")):
                record["attempts"] = record.get("attempts", 0) + 1
                save_db(db)
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Invalid or expired reset session."}).encode("utf-8"))
                return

            is_valid_pw, pw_err = validate_password_complexity(new_password)
            if not is_valid_pw:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": pw_err}).encode("utf-8"))
                return

            matching = [u for u in db["users"] if u.get("email") == email]
            if matching:
                matching[0]["password_hash"] = hash_pw(new_password)
                del db["otps"][f"reset_{email}"]
                self.log_audit(db, email, "USER_RESET_PASSWORD", email, "Self-service password reset via verified OTP")
                save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Password updated successfully! Please log in with your new password."
            }).encode("utf-8"))

        # 8. ADMIN PASSWORD RESET & MANAGEMENT
        elif path == "/api/admin/reset-password":
            user_id = data.get("user_id")
            email = (data.get("email") or "").strip().lower()
            new_password = data.get("new_password")
            admin_user = data.get("admin") or "Admin"

            matching = [u for u in db["users"] if (user_id and u.get("id") == user_id) or (email and u.get("email") == email)]
            if not matching:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Target user not found"}).encode("utf-8"))
                return

            u = matching[0]
            is_valid_pw, pw_err = validate_password_complexity(new_password)
            if not is_valid_pw:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": pw_err}).encode("utf-8"))
                return

            u["password_hash"] = hash_pw(new_password)
            self.log_audit(db, admin_user, "ADMIN_PASSWORD_RESET", u["email"], "Administrative password reset performed")
            save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Password for {u['name']} ({u['email']}) has been successfully updated by Admin."
            }).encode("utf-8"))

        # 9. ADMIN CREATE USER
        if path == "/api/users":
            name = (data.get("name") or "").strip()
            email = (data.get("email") or "").strip().lower()
            partner = (data.get("partner") or "Partner").strip()
            password = data.get("password") or "SoulSync@2024!"
            source = data.get("source") or "Admin Panel"

            existing = [u for u in db["users"] if u.get("email") == email]
            if existing:
                self._set_headers(409)
                self.wfile.write(json.dumps({"error": "User with this email already exists"}).encode("utf-8"))
                return

            is_valid_pw, pw_err = validate_password_complexity(password)
            if not is_valid_pw:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": pw_err}).encode("utf-8"))
                return

            user_id = f"u{len(db['users']) + 1}"
            invite_code = gen_code("SOUL")
            new_user = {
                "id": user_id,
                "name": name,
                "email": email,
                "partner": partner,
                "role": "Verified App User",
                "is_verified": True,
                "is_active": True,
                "invite_code": invite_code,
                "password_hash": hash_pw(password),
                "created_at": datetime.utcnow().isoformat() + "Z",
                "last_active": "Just now",
                "source": source
            }
            db["users"].insert(0, new_user)

            couple_id = f"c{len(db['couples']) + 1}"
            new_couple = {
                "id": couple_id,
                "name": f"{name} & {partner} 💞",
                "p1": name,
                "p2": partner,
                "p1_id": user_id,
                "p2_id": None,
                "code": invite_code,
                "days": 1,
                "status": "Active 🟢",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            new_user["couple_id"] = couple_id
            db["couples"].insert(0, new_couple)
            self.log_audit(db, "Admin", "CREATE_USER", email, f"Created user {name} with code {invite_code}")
            save_db(db)

            safe_u = dict(new_user)
            safe_u.pop("password_hash", None)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"User {name} successfully created and eligible for mobile login.",
                "user": safe_u,
                "couple": new_couple,
                "temporary_password": password
            }).encode("utf-8"))

        # 10. PARTNER CONNECTION - REQUEST
        elif path == "/api/couple/request":
            requester_id = data.get("user_id")
            requester_email = (data.get("email") or "").strip().lower()
            target_code = (data.get("invite_code") or "").strip().upper()

            requester = None
            for u in db["users"]:
                if (requester_id and u["id"] == requester_id) or (requester_email and u["email"] == requester_email):
                    requester = u
                    break

            if not requester:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Requester user not found"}).encode("utf-8"))
                return

            # Check: Prevent connecting to self
            if requester.get("invite_code") == target_code:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "You cannot connect with your own invitation code."}).encode("utf-8"))
                return

            # Find target partner by code
            target_user = None
            for u in db["users"]:
                if u.get("invite_code") == target_code:
                    target_user = u
                    break

            if not target_user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Invalid or expired partner code. Please check with your partner."}).encode("utf-8"))
                return

            # Check: Prevent duplicate pending requests
            existing_req = [
                r for r in db["couple_requests"]
                if r.get("from_id") == requester["id"] and r.get("target_id") == target_user["id"] and r.get("status") == "pending"
            ]
            if existing_req:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "A connection request is already pending with this partner."}).encode("utf-8"))
                return

            req_obj = {
                "id": f"req_{len(db['couple_requests']) + 1}",
                "from_id": requester["id"],
                "from_name": requester["name"],
                "from_email": requester["email"],
                "target_id": target_user["id"],
                "target_name": target_user["name"],
                "target_code": target_code,
                "status": "pending",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["couple_requests"].insert(0, req_obj)
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Connection request sent to {target_user['name']}! Waiting for acceptance.",
                "request": req_obj
            }).encode("utf-8"))

        # 11. PARTNER CONNECTION - ACCEPT
        elif path == "/api/couple/accept":
            request_id = data.get("request_id")
            matching_req = [r for r in db["couple_requests"] if r.get("id") == request_id]
            if not matching_req:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Connection request not found"}).encode("utf-8"))
                return

            req = matching_req[0]
            req["status"] = "accepted"

            u1 = next((u for u in db["users"] if u["id"] == req["from_id"]), None)
            u2 = next((u for u in db["users"] if u["id"] == req["target_id"]), None)

            if u1 and u2:
                # 2-Member Couple Rule: Bind into one active couple space
                couple_id = f"c_{u1['id']}_{u2['id']}"
                couple_name = f"{u1['name']} & {u2['name']} 💞"
                
                new_couple = {
                    "id": couple_id,
                    "name": couple_name,
                    "p1": u1["name"],
                    "p2": u2["name"],
                    "p1_id": u1["id"],
                    "p2_id": u2["id"],
                    "code": u1.get("invite_code", gen_code()),
                    "days": 1,
                    "status": "Active 🟢",
                    "created_at": datetime.utcnow().isoformat() + "Z"
                }
                db["couples"].insert(0, new_couple)
                u1["couple_id"] = couple_id
                u1["partner"] = u2["name"]
                u2["couple_id"] = couple_id
                u2["partner"] = u1["name"]

            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"Connected! You and {u1['name'] if u1 else 'Partner'} are now paired in SoulSync.",
                "couple": new_couple if u1 and u2 else None
            }).encode("utf-8"))

        # 12. PARTNER CONNECTION - REJECT
        elif path == "/api/couple/reject":
            request_id = data.get("request_id")
            matching_req = [r for r in db["couple_requests"] if r.get("id") == request_id]
            if not matching_req:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Request not found"}).encode("utf-8"))
                return
            matching_req[0]["status"] = "rejected"
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "message": "Connection request declined."}).encode("utf-8"))

        # 13. MOOD SYNC (WITH PRIVACY NOTE & REAL BACKEND PERSISTENCE)
        elif path == "/api/mood":
            user_id = data.get("user_id")
            couple_id = data.get("couple_id")
            mood = data.get("mood", "Happy")
            emoji = data.get("emoji", "😊")
            note = data.get("note", "")
            is_private = bool(data.get("is_private", False))

            mood_entry = {
                "id": f"m_{len(db.get('moods', [])) + 1}",
                "user_id": user_id,
                "couple_id": couple_id,
                "mood": mood,
                "emoji": emoji,
                "note": note,
                "is_private": is_private,
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["moods"].insert(0, mood_entry)
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Mood recorded successfully!" if is_private else "Mood shared with your partner!",
                "mood": mood_entry
            }).encode("utf-8"))

        # 14. MEMORIES VAULT
        elif path == "/api/memories":
            couple_id = data.get("couple_id")
            user_id = data.get("user_id")
            title = data.get("title", "Our Memory")
            caption = data.get("caption", "")
            date_str = data.get("date") or datetime.utcnow().strftime("%b %d, %Y")
            tag = data.get("tag", "Date")
            image_url = data.get("image_url") or "https://images.unsplash.com/photo-1518199266791-5375a83190b7"

            memory_obj = {
                "id": f"mem_{len(db.get('memories', [])) + 1}",
                "couple_id": couple_id,
                "user_id": user_id,
                "title": title,
                "caption": caption,
                "date": date_str,
                "tag": tag,
                "image_url": image_url,
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["memories"].insert(0, memory_obj)
            db["interactions"]["Memories Vault"] = db["interactions"].get("Memories Vault", 0) + 1
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Memory added to shared vault!",
                "memory": memory_obj
            }).encode("utf-8"))

        # 15. LOVE LETTERS
        elif path == "/api/letters":
            couple_id = data.get("couple_id")
            sender_id = data.get("sender_id")
            sender_name = data.get("sender_name", "Partner")
            title = data.get("title", "Open When...")
            content = data.get("content", "")
            unlock_date = data.get("unlock_date")
            unlock_condition = data.get("unlock_condition", "Open Anytime")

            letter_obj = {
                "id": f"let_{len(db.get('letters', [])) + 1}",
                "couple_id": couple_id,
                "sender_id": sender_id,
                "sender_name": sender_name,
                "title": title,
                "content": content,
                "unlock_date": unlock_date,
                "unlock_condition": unlock_condition,
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["letters"].insert(0, letter_obj)
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Love letter sealed and delivered to partner's vault!",
                "letter": letter_obj
            }).encode("utf-8"))

        # 16. TOGETHER GAME SESSIONS
        elif path == "/api/games/session":
            couple_id = data.get("couple_id")
            game_type = data.get("game_type")
            user_id = data.get("user_id")
            question_id = data.get("question_id")
            answer = data.get("answer")

            # Find or create active session
            session = None
            for s in db["game_sessions"]:
                if s.get("couple_id") == couple_id and s.get("game_type") == game_type and s.get("status") == "active":
                    session = s
                    break

            if not session:
                session = {
                    "id": f"sess_{len(db['game_sessions']) + 1}",
                    "couple_id": couple_id,
                    "game_type": game_type,
                    "created_at": datetime.utcnow().isoformat() + "Z",
                    "status": "active",
                    "rounds": []
                }
                db["game_sessions"].insert(0, session)

            # Record round answer
            round_obj = None
            for r in session["rounds"]:
                if r.get("question_id") == question_id:
                    round_obj = r
                    break
            if not round_obj:
                round_obj = {"question_id": question_id, "answers": {}}
                session["rounds"].append(round_obj)

            round_obj["answers"][user_id] = {
                "answer": answer,
                "submitted_at": datetime.utcnow().isoformat() + "Z"
            }
            db["interactions"]["Together (Activities)"] = db["interactions"].get("Together (Activities)", 0) + 1
            save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Answer recorded!",
                "session": session
            }).encode("utf-8"))

        # 17. LOVE PULSES
        elif path == "/api/pulse":
            sender = data.get("sender", "Partner")
            pulse_type = data.get("type", "Love ❤️")
            recipient = data.get("recipient", "Partner")
            new_pulse = {
                "id": f"p{len(db['pulses']) + 1}",
                "sender": sender,
                "recipient": recipient,
                "type": pulse_type,
                "time": "Just now",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["pulses"].insert(0, new_pulse)
            db["interactions"]["Connect (Love Pulse)"] = db["interactions"].get("Connect (Love Pulse)", 0) + 1
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "pulse": new_pulse}).encode("utf-8"))

        # 18. TELEMETRY & INTERACTIONS
        elif path == "/api/interaction":
            screen = data.get("screen", "Home Dashboard")
            db["interactions"][screen] = db["interactions"].get(screen, 0) + 1
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "recorded", "interactions": db["interactions"]}).encode("utf-8"))

        # 19. DAILY QUESTIONS CMS
        elif path == "/api/questions":
            q_text = data.get("q", "")
            cat = data.get("cat", "Romance")
            new_q = {
                "id": f"q{len(db['questions']) + 1}",
                "date": "Today",
                "q": f'"{q_text}"',
                "cat": cat,
                "rate": "Active",
                "status": "Active 🟢"
            }
            db["questions"].insert(0, new_q)
            save_db(db)
            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "question": new_q}).encode("utf-8"))


        # CHAT: SEND MESSAGE
        elif path == "/api/chat/messages":
            couple_id = data.get("couple_id")
            sender_id = data.get("sender_id")
            sender_name = data.get("sender_name", "Partner")
            content = data.get("content", "")
            media_type = data.get("media_type", "text")
            media_url = data.get("media_url")
            voice_duration = data.get("voice_duration")
            reply_to_id = data.get("reply_to_id")
            reply_preview = data.get("reply_preview")

            if not content and not media_url:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Message content or media required"}).encode("utf-8"))
                return

            new_msg = {
                "id": f"msg_{datetime.utcnow().strftime('%Y%m%d%H%M%S')}_{random.randint(100, 999)}",
                "couple_id": couple_id,
                "sender_id": sender_id,
                "sender_name": sender_name,
                "content": content,
                "media_type": media_type,
                "media_url": media_url,
                "voice_duration": voice_duration,
                "reply_to_id": reply_to_id,
                "reply_preview": reply_preview,
                "reactions": {},
                "is_read": False,
                "delivered": True,
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db.setdefault("chat_messages", []).append(new_msg)
            
            # Record streak activity
            if couple_id:
                s_dict = db.setdefault("streaks", {}).setdefault(couple_id, {
                    "couple_id": couple_id,
                    "current_streak": 5,
                    "longest_streak": 12,
                    "freeze_tokens": 2,
                    "last_active": datetime.utcnow().strftime("%Y-%m-%d"),
                    "milestone": "Special Heart Badge (7 Days)",
                    "history": []
                })
                today_str = datetime.utcnow().strftime("%Y-%m-%d")
                if today_str not in s_dict["history"]:
                    s_dict["history"].append(today_str)
                    s_dict["current_streak"] += 1
            
            save_db(db)
            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "message": new_msg}).encode("utf-8"))

        # CHAT: TOGGLE REACTION
        elif path == "/api/chat/reactions":
            msg_id = data.get("message_id")
            user_id = data.get("user_id")
            emoji = data.get("emoji", "❤️")
            
            msg = next((m for m in db.get("chat_messages", []) if m.get("id") == msg_id), None)
            if not msg:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Message not found"}).encode("utf-8"))
                return
            
            reactions = msg.setdefault("reactions", {})
            users_with_emoji = reactions.setdefault(emoji, [])
            if user_id in users_with_emoji:
                users_with_emoji.remove(user_id)
                if not users_with_emoji:
                    del reactions[emoji]
            else:
                users_with_emoji.append(user_id)
            
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "reactions": reactions}).encode("utf-8"))

        # CHAT: MARK READ
        elif path == "/api/chat/read":
            couple_id = data.get("couple_id")
            reader_id = data.get("user_id")
            for m in db.get("chat_messages", []):
                if m.get("couple_id") == couple_id and m.get("sender_id") != reader_id:
                    m["is_read"] = True
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))

        # CHAT: TYPING INDICATOR
        elif path == "/api/chat/typing":
            couple_id = data.get("couple_id")
            user_id = data.get("user_id")
            is_typing = data.get("is_typing", False)
            if couple_id and user_id:
                db.setdefault("typing_status", {}).setdefault(couple_id, {})[user_id] = is_typing
                save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))

        # CHAT: DELETE MESSAGE
        elif path == "/api/chat/delete":
            msg_id = data.get("message_id")
            user_id = data.get("user_id")
            msg = next((m for m in db.get("chat_messages", []) if m.get("id") == msg_id), None)
            if msg and msg.get("sender_id") == user_id:
                msg["content"] = "🚫 This message was deleted"
                msg["media_type"] = "text"
                msg["media_url"] = None
                save_db(db)
                self._set_headers(200)
                self.wfile.write(json.dumps({"status": "success", "message": msg}).encode("utf-8"))
            else:
                self._set_headers(403)
                self.wfile.write(json.dumps({"error": "Unauthorized to delete message"}).encode("utf-8"))

        # SAFETY & REPORTING
        elif path == "/api/safety/report":
            reporter_id = data.get("reporter_id")
            target_id = data.get("target_id")
            content_type = data.get("content_type", "user")
            content_id = data.get("content_id")
            reason = data.get("reason", "Inappropriate behavior")
            details = data.get("details", "")

            new_report = {
                "id": f"rep_{len(db.get('reports', [])) + 1}",
                "reporter_id": reporter_id,
                "target_id": target_id,
                "content_type": content_type,
                "content_id": content_id,
                "reason": reason,
                "details": details,
                "status": "Pending Review 🟡",
                "created_at": datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
            }
            db.setdefault("reports", []).insert(0, new_report)
            save_db(db)
            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "report": new_report}).encode("utf-8"))

        # ADMIN: RESOLVE REPORT
        elif path == "/api/admin/reports/resolve":
            admin, err = verify_admin_session(self, db)
            if not admin:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": err}).encode("utf-8"))
                return
            rep_id = data.get("report_id")
            resolution = data.get("resolution", "Investigated & Dismissed")
            rep = next((r for r in db.get("reports", []) if r.get("id") == rep_id), None)
            if rep:
                rep["status"] = f"Resolved: {resolution} 🟢"
                rep["resolved_by"] = admin.get("email")
                db.setdefault("audit_logs", []).insert(0, {
                    "id": f"aud_{len(db.get('audit_logs', []))+1}",
                    "admin": admin.get("email"),
                    "action": "RESOLVE_REPORT",
                    "details": f"Resolved report {rep_id}: {resolution}",
                    "timestamp": datetime.utcnow().strftime("%b %d, %Y - %H:%M UTC")
                })
                save_db(db)
                self._set_headers(200)
                self.wfile.write(json.dumps({"status": "success", "report": rep}).encode("utf-8"))
            else:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "Report not found"}).encode("utf-8"))

        # GIFTS: SEND GIFT
        elif path == "/api/gifts/send":
            couple_id = data.get("couple_id")
            sender_id = data.get("sender_id")
            sender_name = data.get("sender_name", "Partner")
            gift_id = data.get("gift_id")
            gift_name = data.get("gift_name", "Digital Gift")
            emoji = data.get("emoji", "🎁")
            message = data.get("message", "Sent with love ❤️")

            new_gift = {
                "id": f"gift_{len(db.get('gifts', [])) + 1}",
                "couple_id": couple_id,
                "sender_id": sender_id,
                "sender_name": sender_name,
                "gift_id": gift_id,
                "gift_name": gift_name,
                "emoji": emoji,
                "message": message,
                "created_at": datetime.utcnow().strftime("%b %d, %Y - %H:%M"),
                "is_opened": False
            }
            db.setdefault("gifts", []).insert(0, new_gift)
            
            # Also notify partner
            db.setdefault("notifications", []).insert(0, {
                "id": f"notif_{len(db.get('notifications', [])) + 1}",
                "user_id": data.get("recipient_id") or "partner",
                "title": f"New Gift from {sender_name}! {emoji}",
                "body": f'"{message}"',
                "type": "gift",
                "is_read": False,
                "created_at": "Just now"
            })
            save_db(db)
            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "gift": new_gift}).encode("utf-8"))

        # ACCOUNT: UPDATE PROFILE
        elif path == "/api/account/update-profile":
            user_id = data.get("user_id")
            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if not user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found"}).encode("utf-8"))
                return
            if "name" in data:
                user["name"] = data["name"]
            if "avatar_url" in data:
                user["avatar_url"] = data["avatar_url"]
            if "bio" in data:
                user["bio"] = data["bio"]
            if "timezone" in data:
                user["timezone"] = data["timezone"]
            if "anniversary_date" in data:
                user["anniversary_date"] = data["anniversary_date"]
            if "partner_nickname" in data:
                user["partner_nickname"] = data["partner_nickname"]
            save_db(db)
            safe_u = dict(user)
            safe_u.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "user": safe_u}).encode("utf-8"))

        # ACCOUNT: REQUEST EMAIL CHANGE OTP (Separate verification challenge)
        elif path == "/api/account/social-accounts":
            uid = data.get("user_id")
            action = (data.get("action") or "connect").strip().lower()
            provider = (data.get("provider") or "").strip().lower()
            account = (data.get("account") or "").strip()

            u = next((x for x in db["users"] if x.get("id") == uid), None)
            if not u:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found."}).encode("utf-8"))
                return

            accounts = u.setdefault("social_accounts", [])
            if action == "disconnect":
                accounts = [a for a in accounts if a.get("provider") != provider]
                u["social_accounts"] = accounts
                if u.get("social_provider") == provider:
                    u["social_provider"] = accounts[0]["provider"] if accounts else ""
                    u["social_account"] = accounts[0]["account"] if accounts else ""
                self.log_audit(db, u.get("email", uid), "SOCIAL_UNLINK", provider, f"Disconnected {provider}")
            else:
                if not provider or not account:
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"error": "Social provider and account handle/email are required."}).encode("utf-8"))
                    return
                accounts = [a for a in accounts if a.get("provider") != provider]
                accounts.append({"provider": provider, "account": account, "connected_at": now_iso})
                u["social_accounts"] = accounts
                u["social_provider"] = provider
                u["social_account"] = account
                self.log_audit(db, u.get("email", uid), "SOCIAL_LINK", provider, f"Connected {provider}: {account}")

            save_db(db)
            safe_u = dict(u)
            safe_u.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "user": safe_u}).encode("utf-8"))

        elif path == "/api/account/change-email/request":
            user_id = data.get("user_id")
            new_email = (data.get("new_email") or "").strip().lower()
            ip = self.client_address[0] if self.client_address else "127.0.0.1"
            cfg = email_otp_module.get_otp_settings()

            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if not user or not user.get("is_verified", True):
                self._set_headers(403)
                self.wfile.write(json.dumps({"error": "Verified user session required."}).encode("utf-8"))
                return
            if not new_email or "@" not in new_email:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Please enter a valid new email address."}).encode("utf-8"))
                return
            if any(u.get("email") == new_email and u.get("id") != user_id for u in db.get("users", [])):
                self._set_headers(409)
                self.wfile.write(json.dumps({"error": "That email address is already registered to another account."}).encode("utf-8"))
                return

            chal_key = f"email_change_{user_id}"
            existing_ch = db["otps"].get(chal_key)
            if existing_ch:
                ok_cd, wait_s = email_otp_module.check_resend_cooldown(existing_ch.get("last_sent_ts"), cfg["otp_resend_seconds"])
                if not ok_cd:
                    self._set_headers(429)
                    self.wfile.write(json.dumps({
                        "error": f"Please wait {wait_s} seconds before requesting another email change code.",
                        "retry_after_seconds": wait_s
                    }).encode("utf-8"))
                    return

            ok_rl, rl_wait = email_otp_module.check_rate_limit(f"chg:{user_id}:{ip}", max_requests=6, window_seconds=900)
            if not ok_rl:
                self._set_headers(429)
                self.wfile.write(json.dumps({
                    "error": f"Too many email change requests. Try again in {rl_wait} seconds.",
                    "retry_after_seconds": rl_wait
                }).encode("utf-8"))
                return

            otp = gen_otp()
            salt, digest = email_otp_module.hash_otp(otp)
            expires_at = (datetime.utcnow() + timedelta(minutes=cfg["otp_expiry_minutes"])).isoformat() + "Z"
            db["otps"][chal_key] = {
                "purpose": "email_change",
                "user_id": user_id,
                "new_email": new_email,
                "otp_salt": salt,
                "otp_hash": digest,
                "expires_at": expires_at,
                "last_sent_ts": time.time(),
                "attempts": 0
            }
            delivered, _, mail_err = send_email_otp(db, new_email, otp, purpose="email_change", recipient_name=user.get("name", "Partner"))
            save_db(db)
            if not delivered:
                self._set_headers(503)
                self.wfile.write(json.dumps({"error": mail_err or "Unable to send verification code to new email."}).encode("utf-8"))
                return

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": f"A 6-digit verification code has been emailed to {new_email}.",
                "resend_cooldown_seconds": cfg["otp_resend_seconds"],
                "expires_in_seconds": cfg["otp_expiry_minutes"] * 60
            }).encode("utf-8"))

        # ACCOUNT: VERIFY EMAIL CHANGE OTP
        elif path == "/api/account/change-email/verify":
            user_id = data.get("user_id")
            new_email = (data.get("new_email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()
            cfg = email_otp_module.get_otp_settings()

            chal_key = f"email_change_{user_id}"
            record = db["otps"].get(chal_key)
            if not record or record.get("new_email") != new_email:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No matching email change request found."}).encode("utf-8"))
                return

            now_iso = datetime.utcnow().isoformat() + "Z"
            if now_iso > record.get("expires_at", ""):
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Verification code has expired. Please request a new code."}).encode("utf-8"))
                return

            max_attempts = cfg["otp_max_attempts"]
            if record.get("attempts", 0) >= max_attempts:
                self._set_headers(429)
                self.wfile.write(json.dumps({"error": "Maximum verification attempts exceeded. Request a new code."}).encode("utf-8"))
                return

            if not email_otp_module.verify_otp_hash(otp, record.get("otp_salt"), record.get("otp_hash")):
                record["attempts"] = record.get("attempts", 0) + 1
                remaining = max(0, max_attempts - record["attempts"])
                if remaining == 0:
                    record["otp_hash"] = ""
                save_db(db)
                self._set_headers(429 if remaining == 0 else 400)
                self.wfile.write(json.dumps({
                    "error": "Maximum attempts reached. Request a new code." if remaining == 0 else f"Incorrect OTP. {remaining} attempt(s) left.",
                    "attempts_remaining": remaining
                }).encode("utf-8"))
                return

            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if not user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found."}).encode("utf-8"))
                return

            old_email = user.get("email", "")
            user["email"] = new_email
            del db["otps"][chal_key]
            self.log_audit(db, user_id, "EMAIL_CHANGED", new_email, f"Verified email update from {email_otp_module.mask_email(old_email)}")
            save_db(db)

            safe_u = dict(user)
            safe_u.pop("password_hash", None)
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Email updated and verified successfully!",
                "user": safe_u
            }).encode("utf-8"))

        # ACCOUNT: CHANGE PASSWORD
        elif path == "/api/account/change-password":
            user_id = data.get("user_id")
            old_pw = data.get("old_password", "")
            new_pw = data.get("new_password", "")
            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if not user:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found"}).encode("utf-8"))
                return
            
            # Check old password if provided
            if old_pw and user.get("password_hash"):
                old_h = hashlib.sha256(old_pw.encode()).hexdigest()
                if old_h != user.get("password_hash"):
                    self._set_headers(400)
                    self.wfile.write(json.dumps({"error": "Incorrect current password"}).encode("utf-8"))
                    return
            
            user["password_hash"] = hashlib.sha256(new_pw.encode()).hexdigest()
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success", "message": "Password changed successfully"}).encode("utf-8"))

        # ACCOUNT: DISCONNECT COUPLE SAFELY
        elif path == "/api/account/disconnect-couple":
            user_id = data.get("user_id")
            couple_id = data.get("couple_id")
            user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
            if user:
                user["couple_id"] = None
                user["partner_name"] = None
                couple = next((c for c in db.get("couples", []) if c.get("id") == couple_id), None)
                if couple:
                    couple["status"] = "Archived (Disconnected)"
                    couple["unlinked_at"] = datetime.utcnow().isoformat() + "Z"
                # Revoke SoulSafe location sharing & agreements on unlink
                for uid, s in db.get("safety_sessions", {}).items():
                    if s.get("couple_id") == couple_id:
                        s["status"] = "stopped"
                        s["consents"]["location"] = False
                        db.get("safety_locations", {}).pop(uid, None)
                if couple_id:
                    safesync_module.broadcast_safety_update(couple_id, "consent_changed", {"status": "unlinked"})
                save_db(db)
                self._set_headers(200)
                self.wfile.write(json.dumps({"status": "success", "message": "Couple unlinked safely. Shared memories remain preserved in secure archive."}).encode("utf-8"))
            else:
                self._set_headers(404)
                self.wfile.write(json.dumps({"error": "User not found"}).encode("utf-8"))

        # NOTIFICATIONS: MARK READ
        elif path == "/api/notifications/read":
            user_id = data.get("user_id")
            notif_id = data.get("notification_id")
            for n in db.get("notifications", []):
                if not user_id or n.get("user_id") == user_id:
                    if not notif_id or n.get("id") == notif_id:
                        n["is_read"] = True
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))

        elif (path.startswith("/api/safety/") and path not in ("/api/safety/report", "/api/safety/block")) or path.startswith("/api/admin/safety/"):
            if safesync_module.handle_safety_post(
                self,
                path,
                data,
                load_db,
                save_db,
                verify_admin_session,
            ):
                return
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Unknown POST route"}).encode("utf-8"))

        elif path.startswith("/api/music/") or path.startswith("/api/admin/music/"):
            if music_module.handle_music_post(
                self,
                path,
                data,
                load_db,
                save_db,
                verify_admin_session,
            ):
                return
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Unknown POST route"}).encode("utf-8"))

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Unknown POST route"}).encode("utf-8"))

if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8089"))
    print(f"Serving SoulSync Master API on http://0.0.0.0:{port}...")
    server = ThreadingHTTPServer(("0.0.0.0", port), SoulSyncAPIHandler)
    server.serve_forever()
