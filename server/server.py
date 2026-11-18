import json
import os
import random
import string
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime

DB_FILE = os.path.join(os.path.dirname(__file__), "database.json")

def load_db():
    if os.path.exists(DB_FILE):
        try:
            with open(DB_FILE, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {
        "users": [
            {
                "id": "u1",
                "name": "Alex",
                "email": "alex@example.com",
                "partner": "Jordan",
                "role": "Verified App User",
                "created_at": "2024-11-10T10:00:00Z",
                "last_active": "Just now",
                "source": "Mobile App"
            },
            {
                "id": "u2",
                "name": "Jordan",
                "email": "jordan@example.com",
                "partner": "Alex",
                "role": "Verified App User",
                "created_at": "2024-11-10T10:05:00Z",
                "last_active": "10m ago",
                "source": "Mobile App"
            }
        ],
        "couples": [
            {
                "id": "c1",
                "name": "Alex & Jordan 💞",
                "p1": "Alex",
                "p2": "Jordan",
                "code": "SOUL-8492",
                "days": 342,
                "status": "Active 🟢",
                "created_at": "2023-12-12T00:00:00Z"
            }
        ],
        "interactions": {
            "Connect (Love Pulse)": 5840,
            "Home Dashboard": 4920,
            "Together (Activities)": 3180,
            "Memories Vault": 2410,
            "Profile & Settings": 890
        },
        "pulses": [
            {"id": "p1", "sender": "Alex", "recipient": "Jordan", "type": "Love ❤️", "time": "5m ago"},
            {"id": "p2", "sender": "Jordan", "recipient": "Alex", "type": "Hug 🫂", "time": "2h ago"}
        ],
        "questions": [
            {"id": "q1", "date": "Today", "q": "\"What is your favorite memory of us traveling together?\"", "cat": "Travel", "rate": "91% (194 pairs)", "status": "Active 🟢"},
            {"id": "q2", "date": "Tomorrow", "q": "\"What is one small habit of mine that makes you smile?\"", "cat": "Romance", "rate": "Scheduled", "status": "Pending ⏳"},
            {"id": "q3", "date": "Friday", "q": "\"If we could teleport anywhere for 24 hours right now, where?\"", "cat": "Fun", "rate": "Scheduled", "status": "Pending ⏳"}
        ]
    }

def save_db(db):
    with open(DB_FILE, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2, ensure_ascii=False)

def gen_code(prefix="PAIR"):
    digits = ''.join(random.choices(string.digits, k=4))
    return f"{prefix}-{digits}"

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
            return json.loads(body.decode("utf-8"))
        return {}

    def do_GET(self):
        parsed = urlparse(self.path)
        path = parsed.path
        db = load_db()

        if path == "/api/users":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("users", [])).encode("utf-8"))
        elif path == "/api/couples":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("couples", [])).encode("utf-8"))
        elif path == "/api/analytics":
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "interactions": db.get("interactions", {}),
                "total_users": len(db.get("users", [])),
                "total_couples": len(db.get("couples", [])),
                "total_pulses": len(db.get("pulses", [])) + 1428
            }).encode("utf-8"))
        elif path == "/api/pulses":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("pulses", [])).encode("utf-8"))
        elif path == "/api/questions":
            self._set_headers(200)
            self.wfile.write(json.dumps(db.get("questions", [])).encode("utf-8"))
        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode("utf-8"))

    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        db = load_db()
        data = self._read_json()

        if path in ["/api/register", "/api/users"]:
            # Register user from mobile app or admin panel
            name = data.get("name") or data.get("displayName") or "New Partner"
            email = (data.get("email") or "").strip().lower()
            partner = data.get("partner") or data.get("partnerName") or "Partner"
            source = data.get("source") or "Mobile App"

            # Check if user already exists
            existing = [u for u in db["users"] if u.get("email") == email]
            if existing:
                self._set_headers(200)
                self.wfile.write(json.dumps({
                    "status": "success",
                    "message": "User logged in",
                    "user": existing[0]
                }).encode("utf-8"))
                return

            user_id = f"u{len(db['users']) + 1}"
            code = gen_code("PAIR")

            new_user = {
                "id": user_id,
                "name": name,
                "email": email,
                "partner": partner,
                "role": "Verified App User",
                "created_at": datetime.utcnow().isoformat() + "Z",
                "last_active": "Just now",
                "source": source
            }
            db["users"].insert(0, new_user)

            # Auto create/link couple space
            couple_id = f"c{len(db['couples']) + 1}"
            new_couple = {
                "id": couple_id,
                "name": f"{name} & {partner} 💞",
                "p1": name,
                "p2": partner,
                "code": code,
                "days": 1,
                "status": "Active 🟢",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            db["couples"].insert(0, new_couple)

            # Bump interactions
            db["interactions"]["Home Dashboard"] = db["interactions"].get("Home Dashboard", 0) + 1
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "User registered and reflected to Admin Panel",
                "user": new_user,
                "couple": new_couple
            }).encode("utf-8"))

        elif path == "/api/login":
            email = (data.get("email") or "").strip().lower()
            matching = [u for u in db["users"] if u.get("email") == email]
            if matching:
                u = matching[0]
                u["last_active"] = "Just now"
                save_db(db)
                self._set_headers(200)
                self.wfile.write(json.dumps({"status": "success", "user": u}).encode("utf-8"))
            else:
                # Allow instant login and add to user list
                name = email.split("@")[0].capitalize()
                user_id = f"u{len(db['users']) + 1}"
                new_user = {
                    "id": user_id,
                    "name": name,
                    "email": email,
                    "partner": "Partner",
                    "role": "Verified App User",
                    "created_at": datetime.utcnow().isoformat() + "Z",
                    "last_active": "Just now",
                    "source": "Mobile App"
                }
                db["users"].insert(0, new_user)
                save_db(db)
                self._set_headers(200)
                self.wfile.write(json.dumps({"status": "success", "user": new_user}).encode("utf-8"))

        elif path == "/api/pulse":
            sender = data.get("sender", "Partner")
            pulse_type = data.get("type", "Love ❤️")
            new_pulse = {
                "id": f"p{len(db['pulses']) + 1}",
                "sender": sender,
                "recipient": data.get("recipient", "Partner"),
                "type": pulse_type,
                "time": "Just now"
            }
            db["pulses"].insert(0, new_pulse)
            db["interactions"]["Connect (Love Pulse)"] = db["interactions"].get("Connect (Love Pulse)", 0) + 1
            save_db(db)

            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "pulse": new_pulse}).encode("utf-8"))

        elif path == "/api/interaction":
            screen = data.get("screen", "Home Dashboard")
            if screen in db["interactions"]:
                db["interactions"][screen] += 1
            else:
                db["interactions"][screen] = 1
            save_db(db)
            self._set_headers(200)
            self.wfile.write(json.dumps({"status": "recorded", "interactions": db["interactions"]}).encode("utf-8"))

        elif path == "/api/questions":
            q_text = data.get("q", "")
            cat = data.get("cat", "Romance")
            new_q = {
                "id": f"q{len(db['questions']) + 1}",
                "date": "Scheduled",
                "q": f'"{q_text}"',
                "cat": cat,
                "rate": "Pending",
                "status": "Active 🟢"
            }
            db["questions"].insert(0, new_q)
            save_db(db)
            self._set_headers(201)
            self.wfile.write(json.dumps({"status": "success", "question": new_q}).encode("utf-8"))

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Unknown POST route"}).encode("utf-8"))

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8089), SoulSyncAPIHandler)
    print("Serving SoulSync API on http://0.0.0.0:8089...")
    server.serve_forever()
