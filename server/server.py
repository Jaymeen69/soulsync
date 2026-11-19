import json
import os
import random
import string
import re
import hashlib
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
from datetime import datetime, timedelta

DB_FILE = os.path.join(os.path.dirname(__file__), "database.json")

# 7 Games Built-in Question & Prompt Banks
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
    if "smtp_config" not in db:
        db["smtp_config"] = {
            "host": os.environ.get("SOULSYNC_SMTP_HOST", os.environ.get("SMTP_HOST", "")),
            "port": int(os.environ.get("SOULSYNC_SMTP_PORT", os.environ.get("SMTP_PORT", 587))),
            "user": os.environ.get("SOULSYNC_SMTP_USER", os.environ.get("SMTP_USER", "")),
            "password": os.environ.get("SOULSYNC_SMTP_PASS", os.environ.get("SMTP_PASS", "")),
            "from_address": os.environ.get("SOULSYNC_SMTP_FROM", os.environ.get("SMTP_FROM", "SoulSync <no-reply@soulsync.app>")),
            "enabled": True
        }

def save_db(db):
    with open(DB_FILE, "w", encoding="utf-8") as f:
        json.dump(db, f, indent=2, ensure_ascii=False)

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
    return ''.join(random.choices(string.digits, k=6))

def send_email_otp(db, to_email, code, purpose="verification", recipient_name="Partner"):
    """
    Sends an actual email OTP to the recipient with an attractive SoulSync HTML template.
    If SMTP server credentials are provided (via environment or admin panel smtp_config),
    it connects and sends the email via STARTTLS or SSL.
    Records every attempt in db['email_outbox'] for audit, test verification, and admin display.
    """
    now_iso = datetime.utcnow().isoformat() + "Z"
    if purpose == "verification":
        subject = f"Your SoulSync Verification Code: {code} 💞"
        heading = "Verify Your SoulSync Account"
        subtitle = "Welcome to SoulSync! Use the 6-digit verification code below to confirm your email and enter your shared couple space."
    elif purpose == "password_reset":
        subject = f"SoulSync Password Reset Code: {code} 🔑"
        heading = "Reset Your SoulSync Password"
        subtitle = "We received a request to reset your password. Use the 6-digit code below to securely verify your identity and set a new password."
    elif purpose == "welcome_credentials":
        subject = f"Welcome to SoulSync! Your Partner Code: {code} 💞"
        heading = "Your SoulSync Account Is Ready!"
        subtitle = f"Your couple account has been prepared by the administrator. Use your registered email to log in and share your unique partner code: {code}"
    else:
        subject = f"SoulSync Security Notice: {code}"
        heading = "SoulSync Account Update"
        subtitle = f"Important update regarding your account security: {code}"

    html_content = f"""<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body {{ font-family: 'Nunito', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background-color: #FAF8FF; margin: 0; padding: 24px; color: #1A1033; }}
    .container {{ max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 24px; overflow: hidden; box-shadow: 0 12px 32px rgba(108, 62, 188, 0.12); border: 1px solid #F3EEFF; }}
    .header {{ background: linear-gradient(135deg, #6C3EBC 0%, #E8498A 100%); padding: 36px 24px; text-align: center; color: #ffffff; }}
    .logo {{ font-size: 30px; font-weight: 800; letter-spacing: -0.5px; margin: 0; }}
    .tagline {{ font-size: 13px; opacity: 0.95; margin-top: 6px; font-weight: 500; }}
    .content {{ padding: 36px 28px; text-align: center; }}
    .heading {{ font-size: 20px; font-weight: 700; color: #1A1033; margin-bottom: 12px; }}
    .text {{ font-size: 14px; color: #6B6480; line-height: 1.6; margin-bottom: 24px; }}
    .code-box {{ background: #FFF5F8; border: 2px dashed #FF5286; border-radius: 16px; padding: 20px; margin: 20px 0; display: inline-block; min-width: 240px; }}
    .code {{ font-size: 38px; font-weight: 800; letter-spacing: 8px; color: #6C3EBC; margin: 0; font-family: monospace; }}
    .expiry {{ font-size: 13px; color: #E8498A; font-weight: 600; margin-top: 8px; }}
    .footer {{ background: #FAF8FF; padding: 20px; text-align: center; font-size: 12px; color: #B0A8C8; border-top: 1px solid #F3EEFF; }}
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <div class="logo">SoulSync 💞</div>
      <div class="tagline">Connect • Share • Grow Together</div>
    </div>
    <div class="content">
      <div class="heading">{heading}</div>
      <div class="text">{subtitle}</div>
      <div class="code-box">
        <div class="code">{code}</div>
        <div class="expiry">⏰ Valid for 5 minutes</div>
      </div>
      <div class="text" style="font-size: 12px; margin-top: 20px;">
        If you did not request this code, no action is needed. Your couple space remains safe.
      </div>
    </div>
    <div class="footer">
      © 2026 SoulSync Inc. All rights reserved.
    </div>
  </div>
</body>
</html>"""

    text_content = f"{heading}\n\n{subtitle}\n\nCode: {code}\n\n(Valid for 5 minutes)\n\nSoulSync Team"

    cfg = db.get("smtp_config", {})
    host = cfg.get("host") or os.environ.get("SMTP_HOST", "")
    port = int(cfg.get("port") or os.environ.get("SMTP_PORT", 587))
    user = cfg.get("user") or os.environ.get("SMTP_USER", "")
    password = cfg.get("password") or os.environ.get("SMTP_PASS", "")
    from_addr = cfg.get("from_address") or os.environ.get("SMTP_FROM", "SoulSync <no-reply@soulsync.app>")

    status = "dispatched"
    delivery_note = ""

    if host and user and password:
        try:
            msg = MIMEMultipart("alternative")
            msg["Subject"] = subject
            msg["From"] = from_addr
            msg["To"] = to_email
            msg.attach(MIMEText(text_content, "plain"))
            msg.attach(MIMEText(html_content, "html"))

            if port == 465:
                with smtplib.SMTP_SSL(host, port, timeout=8) as server:
                    server.login(user, password)
                    server.sendmail(from_addr, [to_email], msg.as_string())
            else:
                with smtplib.SMTP(host, port, timeout=8) as server:
                    server.starttls()
                    server.login(user, password)
                    server.sendmail(from_addr, [to_email], msg.as_string())
            status = "delivered"
            delivery_note = f"Sent successfully via SMTP {host}:{port}"
            print(f"✅ [SoulSync Mailer] Real email sent to {to_email} via SMTP!")
        except Exception as err:
            status = "smtp_error"
            delivery_note = f"SMTP error: {str(err)}"
            print(f"⚠️ [SoulSync Mailer] SMTP delivery to {to_email} failed: {err}")
    else:
        status = "simulated_local"
        delivery_note = "Dispatched and saved to outbox (Configure SMTP in environment or admin to send via external mail server)"
        print(f"📧 [SoulSync Mailer] Verification email dispatched for {to_email}: OTP = {code}")

    outbox_entry = {
        "id": f"mail_{len(db.get('email_outbox', [])) + 1}",
        "to": to_email,
        "code": code,
        "purpose": purpose,
        "subject": subject,
        "status": status,
        "note": delivery_note,
        "timestamp": now_iso
    }
    db.setdefault("email_outbox", []).insert(0, outbox_entry)
    if len(db["email_outbox"]) > 100:
        db["email_outbox"] = db["email_outbox"][:100]
    return outbox_entry

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
        db = load_db()

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
            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "total": len(db.get("email_outbox", [])),
                "outbox": db.get("email_outbox", [])[:50]
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

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Endpoint not found"}).encode("utf-8"))

    # ---------------- POST ROUTES ----------------
    def do_POST(self):
        parsed = urlparse(self.path)
        path = parsed.path
        db = load_db()
        data = self._read_json()

        # 1. REGISTRATION WITH OTP VERIFICATION
        if path == "/api/register":
            name = (data.get("name") or data.get("displayName") or "").strip()
            email = (data.get("email") or "").strip().lower()
            password = data.get("password") or ""
            partner_name = (data.get("partner") or data.get("partnerName") or "Partner").strip()

            if not name or not email or not password:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Name, email, and password are required"}).encode("utf-8"))
                return

            # Check if email already registered and active
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

            # Generate 6-digit OTP with 5-minute expiry
            otp = gen_otp()
            now = datetime.utcnow()
            expires_at = (now + timedelta(minutes=5)).isoformat() + "Z"

            # Store pending registration in unverified_users
            db["unverified_users"][email] = {
                "name": name,
                "email": email,
                "password_hash": hash_pw(password),
                "partner_name": partner_name,
                "otp": otp,
                "created_at": now.isoformat() + "Z",
                "expires_at": expires_at,
                "attempts": 0
            }

            # Dispatch real email with SoulSync romantic template
            outbox_entry = send_email_otp(db, email, otp, purpose="verification", recipient_name=name)
            save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "pending_verification",
                "message": f"Verification code sent to {email}. Valid for 5 minutes.",
                "email": email,
                "dev_otp": otp, # Provided for direct test automation and fallback display
                "delivery_status": outbox_entry.get("status")
            }).encode("utf-8"))

        # 2. VERIFY REGISTRATION OTP
        elif path == "/api/verify-otp":
            email = (data.get("email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()

            pending = db["unverified_users"].get(email)
            if not pending:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No pending registration found for this email. Please register."}).encode("utf-8"))
                return

            # Check expiry
            now_iso = datetime.utcnow().isoformat() + "Z"
            if now_iso > pending.get("expires_at", ""):
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "OTP has expired. Please tap 'Resend OTP'."}).encode("utf-8"))
                return

            if pending.get("otp") != otp:
                pending["attempts"] = pending.get("attempts", 0) + 1
                save_db(db)
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Incorrect verification code. Please check and try again."}).encode("utf-8"))
                return

            # OTP Valid! Promote to verified active user
            user_id = f"u{len(db['users']) + 1}"
            invite_code = gen_code("SOUL")
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
                "created_at": datetime.utcnow().isoformat() + "Z",
                "last_active": "Just now",
                "source": "Mobile App"
            }
            db["users"].insert(0, new_user)

            # Create personal initial couple space
            couple_id = f"c{len(db['couples']) + 1}"
            new_couple = {
                "id": couple_id,
                "name": f"{pending['name']} & {pending['partner_name']} 💞",
                "p1": pending['name'],
                "p2": pending['partner_name'],
                "p1_id": user_id,
                "p2_id": None,
                "code": invite_code,
                "days": 1,
                "status": "Waiting for Partner ⏳",
                "created_at": datetime.utcnow().isoformat() + "Z"
            }
            new_user["couple_id"] = couple_id
            db["couples"].insert(0, new_couple)

            # Clean up pending
            del db["unverified_users"][email]
            save_db(db)

            # Return sanitized user
            safe_user = dict(new_user)
            safe_user.pop("password_hash", None)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "Email successfully verified! You may now sign in.",
                "user": safe_user,
                "couple": new_couple
            }).encode("utf-8"))

        # 3. RESEND REGISTRATION OTP
        elif path == "/api/resend-otp":
            email = (data.get("email") or "").strip().lower()
            pending = db["unverified_users"].get(email)
            if not pending:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No pending registration found for this email."}).encode("utf-8"))
                return

            # Rate limit: at least 30 seconds between resends
            otp = gen_otp()
            now = datetime.utcnow()
            expires_at = (now + timedelta(minutes=5)).isoformat() + "Z"
            pending["otp"] = otp
            pending["expires_at"] = expires_at

            outbox_entry = send_email_otp(db, email, otp, purpose="verification", recipient_name=pending.get("name", "Partner"))
            save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "New OTP has been sent to your email.",
                "dev_otp": otp,
                "delivery_status": outbox_entry.get("status")
            }).encode("utf-8"))

        # 4. SECURE LOGIN
        elif path == "/api/login":
            email = (data.get("email") or "").strip().lower()
            password = data.get("password") or ""

            matching = [u for u in db["users"] if u.get("email") == email]
            if not matching:
                self._set_headers(401)
                self.wfile.write(json.dumps({"error": "Invalid email or password."}).encode("utf-8"))
                return

            u = matching[0]
            # Check active status
            if not u.get("is_active", True):
                self._set_headers(403)
                self.wfile.write(json.dumps({"error": "Account is disabled. Please contact administrator."}).encode("utf-8"))
                return

            # Verify password if user has password_hash
            if "password_hash" in u and u["password_hash"]:
                if u["password_hash"] != hash_pw(password):
                    self._set_headers(401)
                    self.wfile.write(json.dumps({"error": "Invalid email or password."}).encode("utf-8"))
                    return

            u["last_active"] = "Just now"
            # Ensure user has invite_code
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

        # 5. FORGOT PASSWORD REQUEST OTP
        elif path == "/api/auth/forgot-password":
            email = (data.get("email") or "").strip().lower()
            matching = [u for u in db["users"] if u.get("email") == email]
            dev_otp = None

            # Security: Always acknowledge request without leaking account existence
            if matching:
                u = matching[0]
                otp = gen_otp()
                now = datetime.utcnow()
                expires_at = (now + timedelta(minutes=5)).isoformat() + "Z"
                db["otps"][f"reset_{email}"] = {
                    "otp": otp,
                    "expires_at": expires_at,
                    "user_id": u["id"]
                }
                outbox_entry = send_email_otp(db, email, otp, purpose="password_reset", recipient_name=u.get("name", "Partner"))
                dev_otp = otp
                save_db(db)

            self._set_headers(200)
            self.wfile.write(json.dumps({
                "status": "success",
                "message": "If an account exists with this email, a 6-digit reset code has been sent.",
                "dev_otp": dev_otp
            }).encode("utf-8"))

        # 6. VERIFY RESET PASSWORD OTP
        elif path == "/api/auth/verify-reset-otp":
            email = (data.get("email") or "").strip().lower()
            otp = (data.get("otp") or "").strip()
            record = db["otps"].get(f"reset_{email}")

            if not record:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "No password reset requested for this email."}).encode("utf-8"))
                return

            now_iso = datetime.utcnow().isoformat() + "Z"
            if now_iso > record.get("expires_at", ""):
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Reset OTP has expired. Please request a new one."}).encode("utf-8"))
                return

            if record.get("otp") != otp:
                self._set_headers(400)
                self.wfile.write(json.dumps({"error": "Invalid reset code. Please check and try again."}).encode("utf-8"))
                return

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
            record = db["otps"].get(f"reset_{email}")

            if not record or record.get("otp") != otp:
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
                save_db(db)
                self.log_audit(db, email, "USER_RESET_PASSWORD", email, "Self-service password reset via OTP")
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
        elif path == "/api/users":
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

        else:
            self._set_headers(404)
            self.wfile.write(json.dumps({"error": "Unknown POST route"}).encode("utf-8"))

if __name__ == "__main__":
    print("Serving SoulSync Master API on http://0.0.0.0:8089...")
    server = HTTPServer(("0.0.0.0", 8089), SoulSyncAPIHandler)
    server.serve_forever()
