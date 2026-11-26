import hashlib
import hmac
import json
import os
import secrets
import smtplib
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta
from email.mime.image import MIMEImage
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr

EMAIL_LOCK = threading.RLock()
OTP_SEND_HISTORY = {}  # key -> list of epoch timestamps for sliding window rate limit

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
LOGO_CANDIDATES = [
    os.path.abspath(os.path.join(BASE_DIR, "..", "soulsync_admin", "admin_logo.png")),
    os.path.abspath(os.path.join(BASE_DIR, "..", "soulsync", "assets", "images", "app_logo.png")),
    os.path.abspath(os.path.join(BASE_DIR, "..", "assets", "images", "app_logo.png")),
]


def _env_clean(key, default=""):
    val = (os.environ.get(key) or "").strip()
    if val in ("[SENSITIVE]", "PASTE_YOUR_GMAIL_APP_PASSWORD_HERE"):
        return default
    return val or default


def _env_int(key, default_val):
    raw = _env_clean(key, "")
    if not raw:
        return default_val
    try:
        return int(raw)
    except Exception:
        return default_val


def get_otp_settings():
    """Return active SMTP + OTP policy configuration from environment variables (no secrets returned)."""
    host = _env_clean("SMTP_HOST") or _env_clean("SOULSYNC_SMTP_HOST") or "smtp.gmail.com"
    port = _env_int("SMTP_PORT", _env_int("SOULSYNC_SMTP_PORT", 587))
    secure_raw = _env_clean("SMTP_SECURE", "false").lower()
    tls_raw = _env_clean("SMTP_REQUIRE_TLS", "true").lower()
    user = _env_clean("SMTP_USER") or _env_clean("SOULSYNC_SMTP_USER")
    password = _env_clean("SMTP_PASS") or _env_clean("SOULSYNC_SMTP_PASS")
    from_name = _env_clean("MAIL_FROM_NAME", "SoulSync")
    from_email = _env_clean("MAIL_FROM_EMAIL") or user or "pateljaymin1234567890@gmail.com"
    vercel_url = _env_clean("SOULSYNC_VERCEL_MAILER_URL")
    vercel_key = _env_clean("SOULSYNC_MAILER_KEY")

    expiry_minutes = max(1, _env_int("OTP_EXPIRY_MINUTES", 5))
    resend_seconds = max(10, _env_int("OTP_RESEND_SECONDS", 60))
    max_attempts = max(1, _env_int("OTP_MAX_ATTEMPTS", 5))

    return {
        "host": host,
        "port": port,
        "secure": secure_raw in ("true", "1", "yes") or port == 465,
        "require_tls": tls_raw not in ("false", "0", "no"),
        "user": user,
        "has_password": bool(password),
        "password": password,
        "vercel_url": vercel_url,
        "vercel_key": vercel_key,
        "has_vercel_bridge": bool(vercel_url and vercel_key),
        "from_name": from_name,
        "from_email": from_email,
        "otp_expiry_minutes": expiry_minutes,
        "otp_resend_seconds": resend_seconds,
        "otp_max_attempts": max_attempts,
    }


def generate_secure_otp():
    """Cryptographically random 6-digit OTP."""
    return f"{secrets.randbelow(1000000):06d}"


def hash_otp(otp, salt=None):
    """Hash OTP with per-challenge random salt so plaintext codes are never persisted."""
    salt = salt or secrets.token_hex(16)
    digest = hashlib.sha256(f"{salt}:{otp}".encode("utf-8")).hexdigest()
    return salt, digest


def verify_otp_hash(otp, salt, expected_digest):
    """Constant-time OTP hash check."""
    if not otp or not salt or not expected_digest:
        return False
    actual = hashlib.sha256(f"{salt}:{otp.strip()}".encode("utf-8")).hexdigest()
    return hmac.compare_digest(actual, expected_digest)


def mask_email(email):
    """Partially mask email for privacy-safe admin diagnostics."""
    s = (email or "").strip()
    if "@" not in s:
        return "***"
    local, domain = s.split("@", 1)
    if len(local) <= 2:
        masked = local[0] + "*"
    else:
        masked = local[:2] + ("*" * min(5, max(2, len(local) - 2)))
    return f"{masked}@{domain}"


def check_rate_limit(key, max_requests=6, window_seconds=900):
    """Sliding-window rate limiter returning (allowed, retry_after_seconds)."""
    now = time.time()
    with EMAIL_LOCK:
        hist = [t for t in OTP_SEND_HISTORY.get(key, []) if (now - t) < window_seconds]
        if len(hist) >= max_requests:
            retry_after = int(max(1, window_seconds - (now - hist[0])))
            OTP_SEND_HISTORY[key] = hist
            return False, retry_after
        hist.append(now)
        OTP_SEND_HISTORY[key] = hist
        return True, 0


def check_resend_cooldown(last_sent_ts, cooldown_seconds=None):
    """Return (allowed, retry_after_seconds) for resend cooldown."""
    if cooldown_seconds is None:
        cooldown_seconds = get_otp_settings()["otp_resend_seconds"]
    if not last_sent_ts:
        return True, 0
    elapsed = time.time() - float(last_sent_ts)
    if elapsed < cooldown_seconds:
        return False, int(max(1, cooldown_seconds - elapsed + 0.999))
    return True, 0


def _find_logo_bytes():
    for path in LOGO_CANDIDATES:
        if os.path.exists(path):
            try:
                with open(path, "rb") as f:
                    return f.read()
            except Exception:
                pass
    return None


def build_otp_email_html(otp, purpose="verification", recipient_name="Partner", expiry_minutes=5, has_logo_cid=True):
    """Build premium romantic SoulSync pink/purple HTML email with original SoulSync logo."""
    safe_name = "".join(c for c in (recipient_name or "Partner") if c not in "<>\"'")[:60]

    if purpose == "verification":
        heading = f"Welcome to SoulSync, {safe_name}!"
        subtitle = "Confirm your email address with the 6-digit verification code below to activate your private couple space."
        badge = "Account Registration Verification"
    elif purpose == "password_reset":
        heading = "Reset Your SoulSync Password"
        subtitle = f"Hi {safe_name}, enter the 6-digit security code below to verify your identity and choose a new password."
        badge = "Password Recovery Request"
    elif purpose == "email_change":
        heading = "Verify Your New Email Address"
        subtitle = f"Hi {safe_name}, confirm ownership of this new email address for your SoulSync account using the code below."
        badge = "Email Change Verification"
    else:
        heading = "SoulSync Security Verification"
        subtitle = f"Hi {safe_name}, use the verification code below to complete your security action."
        badge = "Security Verification"

    logo_block = (
        '<img src="cid:soulsync_logo" alt="SoulSync Logo" '
        'style="width:76px;height:76px;border-radius:50%;border:3px solid rgba(255,255,255,0.85);'
        'box-shadow:0 8px 20px rgba(26,16,51,0.28);display:block;margin:0 auto 12px auto;object-fit:cover;" />'
        if has_logo_cid
        else ""
    )

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1.0">
  <title>{heading}</title>
</head>
<body style="margin:0;padding:24px 12px;background-color:#F8F4FF;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Nunito,Arial,sans-serif;color:#1A1033;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0">
    <tr>
      <td align="center">
        <table role="presentation" width="500" cellspacing="0" cellpadding="0" style="max-width:500px;width:100%;background:#FFFFFF;border-radius:24px;overflow:hidden;border:1px solid #EADDFB;box-shadow:0 16px 36px rgba(108,62,188,0.14);">
          <tr>
            <td style="background:linear-gradient(135deg,#6C3EBC 0%,#B43CA4 52%,#E8498A 100%);padding:34px 24px 28px 24px;text-align:center;color:#FFFFFF;">
              {logo_block}
              <div style="font-size:28px;font-weight:800;letter-spacing:-0.5px;margin:0;">SoulSync</div>
              <div style="font-size:12px;letter-spacing:1.4px;text-transform:uppercase;opacity:0.92;margin-top:4px;font-weight:700;">Two Hearts • One Private Space</div>
            </td>
          </tr>
          <tr>
            <td style="padding:32px 28px 28px 28px;text-align:center;">
              <span style="display:inline-block;padding:6px 14px;border-radius:999px;background:#FFF0F6;border:1px solid #F9C6DC;color:#C0245E;font-size:11px;font-weight:700;letter-spacing:0.6px;text-transform:uppercase;margin-bottom:14px;">{badge}</span>
              <h1 style="margin:0 0 12px 0;font-size:22px;line-height:1.3;color:#1A1033;font-weight:800;">{heading}</h1>
              <p style="margin:0 0 22px 0;font-size:14.5px;line-height:1.65;color:#564D70;">{subtitle}</p>
              <div style="background:linear-gradient(135deg,#FAF5FF 0%,#FFF2F7 100%);border:2px dashed #E8498A;border-radius:18px;padding:20px 18px;margin:0 auto 22px auto;max-width:290px;">
                <div style="font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:1.2px;color:#6C3EBC;margin-bottom:6px;">Your 6-Digit Verification Code</div>
                <div style="font-size:38px;font-weight:900;letter-spacing:9px;color:#1A1033;font-family:'Courier New',Courier,monospace;margin:0;">{otp}</div>
                <div style="font-size:12.5px;color:#C0245E;font-weight:700;margin-top:8px;">Valid for {expiry_minutes} minutes only</div>
              </div>
              <p style="margin:0;font-size:12px;line-height:1.55;color:#6E658C;">
                Never share this code with anyone. If you did not request this verification, you can safely ignore this email.
              </p>
            </td>
          </tr>
          <tr>
            <td style="background:#FAF8FF;padding:18px 24px;text-align:center;border-top:1px solid #EFE7FA;font-size:11.5px;color:#6E658C;">
              Sent securely by <strong style="color:#6C3EBC;">SoulSync</strong> • Private Couple Space Security
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>"""


def send_real_otp_email(db, to_email, otp, purpose="verification", recipient_name="Partner"):
    """
    Deliver a real OTP email via configured Gmail SMTP credentials.
    Returns (success: bool, outbox_entry: dict, error_msg: str|None).
    Never stores raw OTP codes in db['email_outbox'] or logs!
    """
    cfg = get_otp_settings()
    now_iso = datetime.utcnow().isoformat() + "Z"
    clean_to = (to_email or "").strip().lower()

    if purpose == "verification":
        subject = "SoulSync Email Verification Code"
    elif purpose == "password_reset":
        subject = "SoulSync Password Reset Code"
    elif purpose == "email_change":
        subject = "SoulSync Email Change Verification"
    else:
        subject = "SoulSync Security Code"

    logo_bytes = _find_logo_bytes()
    html_content = build_otp_email_html(
        otp,
        purpose=purpose,
        recipient_name=recipient_name,
        expiry_minutes=cfg["otp_expiry_minutes"],
        has_logo_cid=bool(logo_bytes),
    )
    text_content = (
        f"SoulSync Verification\n\n"
        f"Your 6-digit verification code is: {otp}\n"
        f"Valid for {cfg['otp_expiry_minutes']} minutes.\n\n"
        f"If you did not request this, ignore this email."
    )

    if not (cfg["host"] and cfg["user"] and cfg["password"]):
        if cfg["has_vercel_bridge"]:
            try:
                payload = json.dumps({
                    "to": clean_to,
                    "otp": otp,
                    "purpose": purpose,
                    "recipient_name": recipient_name,
                }).encode("utf-8")
                vreq = urllib.request.Request(
                    cfg["vercel_url"],
                    data=payload,
                    headers={
                        "Content-Type": "application/json",
                        "Authorization": f"Bearer {cfg['vercel_key']}",
                    },
                    method="POST",
                )
                with urllib.request.urlopen(vreq, timeout=15) as vresp:
                    vbody = json.loads(vresp.read().decode("utf-8"))
                    if vresp.status == 200 and vbody.get("status") == "delivered":
                        entry = _record_sanitized_log(
                            db,
                            to_email=clean_to,
                            purpose=purpose,
                            subject=subject,
                            status="delivered",
                            note="Delivered via Gmail SMTP (Vercel Production mailer)",
                            now_iso=now_iso,
                        )
                        print(f"[SoulSync Mailer] Delivered {purpose} email via Vercel Gmail SMTP to {mask_email(clean_to)}")
                        return True, entry, None
            except urllib.error.HTTPError as e:
                err_txt = ""
                try:
                    err_txt = json.loads(e.read().decode("utf-8")).get("error", f"HTTP {e.code}")
                except Exception:
                    err_txt = f"HTTP {e.code}"
                entry = _record_sanitized_log(
                    db,
                    to_email=clean_to,
                    purpose=purpose,
                    subject=subject,
                    status="failed",
                    note=f"Mailer relay error: {err_txt[:160]}",
                    now_iso=now_iso,
                )
                return False, entry, "Unable to send verification email right now. Please try again shortly."
            except Exception as err:
                entry = _record_sanitized_log(
                    db,
                    to_email=clean_to,
                    purpose=purpose,
                    subject=subject,
                    status="failed",
                    note=f"Mailer connection error: {str(err)[:160]}",
                    now_iso=now_iso,
                )
                return False, entry, "Unable to reach email service right now."

        entry = _record_sanitized_log(
            db,
            to_email=clean_to,
            purpose=purpose,
            subject=subject,
            status="smtp_unconfigured",
            note="SMTP credentials missing on backend environment.",
            now_iso=now_iso,
        )
        return False, entry, "Email service is not configured on backend server."

    try:
        root_msg = MIMEMultipart("related")
        root_msg["Subject"] = subject
        root_msg["From"] = formataddr((cfg["from_name"], cfg["from_email"]))
        root_msg["To"] = clean_to

        alt_msg = MIMEMultipart("alternative")
        alt_msg.attach(MIMEText(text_content, "plain", "utf-8"))
        alt_msg.attach(MIMEText(html_content, "html", "utf-8"))
        root_msg.attach(alt_msg)

        if logo_bytes:
            img = MIMEImage(logo_bytes, _subtype="png")
            img.add_header("Content-ID", "<soulsync_logo>")
            img.add_header("Content-Disposition", "inline", filename="soulsync_logo.png")
            root_msg.attach(img)

        if cfg["secure"] or cfg["port"] == 465:
            with smtplib.SMTP_SSL(cfg["host"], cfg["port"], timeout=12) as server:
                server.login(cfg["user"], cfg["password"])
                server.sendmail(cfg["from_email"], [clean_to], root_msg.as_string())
        else:
            with smtplib.SMTP(cfg["host"], cfg["port"], timeout=12) as server:
                server.ehlo()
                if cfg["require_tls"]:
                    server.starttls()
                    server.ehlo()
                server.login(cfg["user"], cfg["password"])
                server.sendmail(cfg["from_email"], [clean_to], root_msg.as_string())

        entry = _record_sanitized_log(
            db,
            to_email=clean_to,
            purpose=purpose,
            subject=subject,
            status="delivered",
            note=f"Delivered via {cfg['host']}:{cfg['port']}",
            now_iso=now_iso,
        )
        print(f"[SoulSync Mailer] Delivered {purpose} email to {mask_email(clean_to)}")
        return True, entry, None
    except Exception as err:
        safe_err = str(err)
        if cfg["password"]:
            safe_err = safe_err.replace(cfg["password"], "[REDACTED]")
        entry = _record_sanitized_log(
            db,
            to_email=clean_to,
            purpose=purpose,
            subject=subject,
            status="failed",
            note=f"Delivery error: {safe_err[:180]}",
            now_iso=now_iso,
        )
        print(f"[SoulSync Mailer] Delivery failed for {mask_email(clean_to)}: {safe_err[:120]}")
        return False, entry, "Unable to send verification email right now. Please try again shortly."


def _record_sanitized_log(db, to_email, purpose, subject, status, note, now_iso):
    outbox = db.setdefault("email_outbox", [])
    entry = {
        "id": f"mail_{int(time.time() * 1000)}_{secrets.token_hex(2)}",
        "to_masked": mask_email(to_email),
        "purpose": purpose,
        "subject": subject,
        "status": status,
        "note": note,
        "timestamp": now_iso,
    }
    outbox.insert(0, entry)
    if len(outbox) > 100:
        db["email_outbox"] = outbox[:100]
    return entry


def sanitize_outbox_entries(raw_entries):
    """Strip any legacy code fields and return admin-safe email logs."""
    out = []
    for e in raw_entries or []:
        to_val = e.get("to_masked") or mask_email(e.get("to", ""))
        out.append({
            "id": e.get("id", ""),
            "to_masked": to_val,
            "purpose": e.get("purpose", "verification"),
            "subject": e.get("subject", "SoulSync Verification"),
            "status": e.get("status", "unknown"),
            "note": e.get("note", ""),
            "timestamp": e.get("timestamp", ""),
        })
    return out


def get_public_service_status(db):
    """Return non-secret SMTP service config + delivery counts for Admin Panel."""
    cfg = get_otp_settings()
    logs = sanitize_outbox_entries(db.get("email_outbox", []))
    delivered = sum(1 for l in logs if l.get("status") == "delivered")
    failed = sum(1 for l in logs if l.get("status") in ("failed", "smtp_error", "smtp_unconfigured"))
    configured = bool((cfg["host"] and cfg["user"] and cfg["has_password"]) or cfg["has_vercel_bridge"])
    return {
        "configured": configured,
        "provider": "Gmail SMTP" if "gmail" in cfg["host"].lower() else (cfg["host"] or "Unconfigured"),
        "smtp_host": cfg["host"] or "Not configured",
        "smtp_port": cfg["port"],
        "tls_enabled": cfg["secure"] or cfg["require_tls"],
        "from_name": cfg["from_name"],
        "from_email": cfg["from_email"],
        "otp_expiry_minutes": cfg["otp_expiry_minutes"],
        "otp_resend_seconds": cfg["otp_resend_seconds"],
        "otp_max_attempts": cfg["otp_max_attempts"],
        "stats": {
            "total": len(logs),
            "delivered": delivered,
            "failed": failed,
        },
        "logs": logs[:50],
    }
