import json
import math
import os
import queue
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timedelta

SAFETY_LOCK = threading.Lock()
SAFETY_SUBSCRIBERS = {}  # couple_id -> set of queue.Queue

ALLOWED_MODES = {"car", "bike", "walking", "stationary", "cycling", "in_vehicle", "other"}
DURATION_SECONDS = {
    "1h": 3600,
    "8h": 8 * 3600,
    "12h": 12 * 3600,
    "manual": None,
}
DEFAULT_NOTIFICATION_TEMPLATES = {
    "sharing_started": "{name} started sharing their live location.",
    "sharing_stopped": "{name} stopped sharing their live location.",
    "driving_mode_on": "{name} enabled Driving Mode.",
    "vehicle_changed": "{name} switched travel mode to {mode}.",
    "speed_exceeded": "Safety Alert: Your partner's estimated speed exceeded their agreed threshold.",
    "expiry_warning": "Location sharing expires soon.",
    "safe_checkin": "{name} tapped I Reached Safely.",
    "sos": "URGENT SOS from {name}! Tap to check details and call.",
}


def haversine_meters(lat1, lng1, lat2, lng2):
    """Return great-circle straight-line distance between two WGS84 coordinates in meters."""
    r = 6371000.0
    p1 = math.radians(lat1)
    p2 = math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2.0) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2.0) ** 2
    return 2.0 * r * math.atan2(math.sqrt(a), math.sqrt(max(0.0, 1.0 - a)))


def ensure_safety_db(db):
    """Initialize SoulSafe data collections in database.json without disturbing existing modules."""
    db.setdefault("safety_sessions", {})       # user_id -> session & consent state
    db.setdefault("safety_locations", {})      # user_id -> latest authorized fix
    db.setdefault("safety_agreements", {})     # couple_id -> { "A_to_B": {...}, "B_to_A": {...} }
    db.setdefault("safety_alerts", [])         # deduplicated alert metadata (no raw GPS trails)
    db.setdefault("safety_safe_zones", {})     # user_id -> [zones] (owner-only!)
    db.setdefault("safety_journeys", {})       # user_id -> active journey
    db.setdefault("safety_history", {})        # user_id -> optional session summaries (off by default)
    db.setdefault("safety_sos", [])            # SOS events
    db.setdefault("safety_fcm_tokens", {})     # user_id -> [tokens]
    db.setdefault("safety_notif_prefs", {})    # user_id -> dict of booleans
    db.setdefault("safety_error_logs", [])
    db.setdefault("safety_metrics", {
        "total_updates": 0,
        "total_journeys": 0,
        "total_sos": 0,
        "total_alerts": 0,
        "route_requests": 0,
    })
    db.setdefault("safety_config", {
        "enabled": True,
        "speed_alerts_enabled": True,
        "routing_enabled": True,
        "history_allowed": True,
        "allowed_durations": ["1h", "8h", "12h", "manual"],
        "min_threshold_kmh": 10,
        "max_threshold_kmh": 200,
        "alert_cooldown_seconds": 60,
        "notification_templates": dict(DEFAULT_NOTIFICATION_TEMPLATES),
    })


def _log_safety_error(db, source, message, save_fn):
    ensure_safety_db(db)
    db["safety_error_logs"].insert(0, {
        "id": f"serr_{int(time.time() * 1000)}",
        "source": source,
        "message": str(message)[:300],
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"),
    })
    db["safety_error_logs"] = db["safety_error_logs"][:100]
    save_fn(db)


def verify_user_and_couple(db, user_id, couple_id=None):
    """Server-authoritative identity & couple binding check."""
    if not user_id:
        return False, None, None, "Unauthorized: user_id is required."
    user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
    if not user:
        return False, None, None, "Unauthorized: User account not found."
    u_couple_id = user.get("couple_id")
    if couple_id and u_couple_id != couple_id:
        return False, None, None, "Forbidden: Cross-couple access denied."
    if not u_couple_id:
        return False, user, None, "Forbidden: You must be paired with a partner to use SoulSafe."
    couple = next((c for c in db.get("couples", []) if c.get("id") == u_couple_id), None)
    if not couple:
        return False, user, None, "Couple record not found."
    return True, user, couple, None


def get_partner_user(db, user, couple):
    if not couple:
        return None
    u_id = user.get("id")
    p1 = couple.get("p1_id") or couple.get("partner1_id")
    p2 = couple.get("p2_id") or couple.get("partner2_id")
    pid = p2 if p1 == u_id else p1
    if pid:
        found = next((u for u in db.get("users", []) if u.get("id") == pid), None)
        if found:
            return found
    for u in db.get("users", []):
        if u.get("couple_id") == couple.get("id") and u.get("id") != u_id:
            return u
    return None


def _default_session(user_id, couple_id):
    return {
        "user_id": user_id,
        "couple_id": couple_id,
        "session_id": None,
        "status": "stopped",  # stopped | active | paused | expired
        "duration_key": "8h",
        "daily_sharing": False,
        "started_at": None,
        "expires_at": None,
        "expires_at_ms": None,
        "travel_mode": "stationary",
        "driving_mode": False,
        "consents": {
            "location": False,
            "speed": True,
            "battery": False,
            "destination": False,
            "history": False,  # Disabled by default per privacy spec
            "safe_zones": False,
        },
        "history_retention_days": 7,
    }


def _check_session_expiry(sess, db, save_fn=None):
    now_ms = int(time.time() * 1000)
    if sess.get("status") in ("active", "paused"):
        exp_ms = sess.get("expires_at_ms")
        if exp_ms and now_ms > int(exp_ms):
            sess["status"] = "expired"
            sess["consents"]["location"] = False
            uid = sess.get("user_id")
            if uid in db.get("safety_locations", {}):
                db["safety_locations"][uid]["is_live"] = False
            if save_fn:
                save_fn(db)
            return True
    return False


def _sanitize_partner_view(db, viewer_user, partner_user, save_fn=None):
    """Build partner view strictly respecting their independent consent scopes and freshness rules."""
    if not partner_user:
        return None
    pid = partner_user.get("id")
    sess = db["safety_sessions"].get(pid)
    loc = db["safety_locations"].get(pid)
    now_ms = int(time.time() * 1000)

    if not sess:
        return {
            "user_id": pid,
            "name": partner_user.get("name", "Partner"),
            "sharing_status": "stopped",
            "is_live": False,
            "location": None,
            "travel_mode": "stationary",
            "driving_mode": False,
            "speed_kmh": None,
            "speed_available": False,
            "freshness": "unavailable",
        }

    _check_session_expiry(sess, db, save_fn)
    consents = sess.get("consents", {})
    status = sess.get("status", "stopped")
    is_sharing = status == "active" and bool(consents.get("location"))

    loc_out = None
    speed_kmh = None
    speed_available = False
    freshness = "unavailable"
    accuracy_m = None
    battery_out = None
    last_updated_at = None

    if loc and status in ("active", "paused", "expired"):
        server_rx_ms = int(loc.get("server_received_ms", 0))
        age_sec = max(0.0, (now_ms - server_rx_ms) / 1000.0) if server_rx_ms else 99999.0
        travel_mode = sess.get("travel_mode", "stationary")
        delayed_thresh = 15.0 if travel_mode in ("car", "bike", "in_vehicle", "cycling", "walking") else 120.0
        stale_thresh = 60.0 if travel_mode in ("car", "bike", "in_vehicle", "cycling", "walking") else 300.0

        if not is_sharing:
            freshness = "expired" if status == "expired" else ("paused" if status == "paused" else "stopped")
        elif age_sec > stale_thresh:
            freshness = "stale"
        elif age_sec > delayed_thresh:
            freshness = "delayed"
        else:
            freshness = "live"

        # Hide live coordinates if sharing revoked/stopped
        if is_sharing or status == "paused":
            loc_out = {
                "lat": loc.get("lat"),
                "lng": loc.get("lng"),
                "accuracy_m": loc.get("accuracy_m"),
                "bearing": loc.get("bearing"),
                "observed_at": loc.get("observed_at"),
                "server_received_at": loc.get("server_received_at"),
                "age_seconds": round(age_sec, 1),
            }
            accuracy_m = loc.get("accuracy_m")
            last_updated_at = loc.get("server_received_at")

        # Speed only exposed if speed consent granted, fix is live (not stale/paused), and accurate
        if is_sharing and consents.get("speed", True) and freshness in ("live", "delayed"):
            if loc.get("speed_available") and loc.get("speed_kmh") is not None:
                speed_kmh = round(float(loc["speed_kmh"]), 1)
                speed_available = True

        # Optional Battery status
        if is_sharing and consents.get("battery") and loc.get("battery_pct") is not None:
            battery_out = {
                "percent": loc.get("battery_pct"),
                "charging": bool(loc.get("battery_charging")),
                "updated_at": loc.get("server_received_at"),
            }

    journey = db["safety_journeys"].get(pid)
    journey_out = None
    if journey and journey.get("active") and is_sharing:
        journey_out = {
            "id": journey.get("id"),
            "travel_mode": journey.get("travel_mode"),
            "started_at": journey.get("started_at"),
            "destination": journey.get("destination") if consents.get("destination") else None,
        }

    return {
        "user_id": pid,
        "name": partner_user.get("name", "Partner"),
        "sharing_status": status,
        "is_live": is_sharing and freshness in ("live", "delayed"),
        "freshness": freshness,
        "location": loc_out,
        "travel_mode": sess.get("travel_mode", "stationary"),
        "driving_mode": bool(sess.get("driving_mode")),
        "speed_kmh": speed_kmh,
        "speed_available": speed_available,
        "accuracy_m": accuracy_m,
        "last_updated_at": last_updated_at,
        "expires_at": sess.get("expires_at"),
        "battery": battery_out,
        "journey": journey_out,
    }


def _build_couple_safety_state(db, user, couple, save_fn=None):
    ensure_safety_db(db)
    uid = user.get("id")
    cid = couple.get("id")
    my_sess = db["safety_sessions"].setdefault(uid, _default_session(uid, cid))
    _check_session_expiry(my_sess, db, save_fn)
    my_loc = db["safety_locations"].get(uid)
    partner_user = get_partner_user(db, user, couple)
    partner_view = _sanitize_partner_view(db, user, partner_user, save_fn)

    # Straight-line Haversine distance ONLY if both have authorized coordinates
    distance_km = None
    distance_is_live = False
    if (
        my_sess.get("status") == "active"
        and my_loc
        and partner_view
        and partner_view.get("location")
    ):
        d_m = haversine_meters(
            float(my_loc["lat"]),
            float(my_loc["lng"]),
            float(partner_view["location"]["lat"]),
            float(partner_view["location"]["lng"]),
        )
        distance_km = round(d_m / 1000.0, 2)
        distance_is_live = bool(partner_view.get("is_live"))

    agreements = db["safety_agreements"].get(cid, {})
    pid = partner_user.get("id") if partner_user else "partner"
    # Key agreements cleanly by target user id: for_me and for_partner
    for_me = agreements.get(f"for_{uid}")
    for_partner = agreements.get(f"for_{pid}")

    my_zones = db["safety_safe_zones"].get(uid, [])
    my_journey = db["safety_journeys"].get(uid)
    my_prefs = db["safety_notif_prefs"].get(uid, {
        "sharing_started": True,
        "sharing_stopped": True,
        "driving_mode": True,
        "vehicle_changed": True,
        "speed_exceeded": True,
        "expiry_warning": True,
        "daily_reminder": False,
        "safe_zone": True,
        "low_battery": True,
    })

    # Recent couple alerts & SOS (redacted of unrelated couples)
    recent_sos = [s for s in db.get("safety_sos", []) if s.get("couple_id") == cid][:10]
    recent_alerts = [a for a in db.get("safety_alerts", []) if a.get("couple_id") == cid][:10]

    return {
        "couple_id": cid,
        "config": {
            "enabled": db["safety_config"].get("enabled", True),
            "speed_alerts_enabled": db["safety_config"].get("speed_alerts_enabled", True),
            "allowed_durations": db["safety_config"].get("allowed_durations", ["1h", "8h", "12h", "manual"]),
            "routing_configured": bool(get_openrouteservice_key()),
        },
        "my_session": my_sess,
        "my_location": my_loc,
        "partner": partner_view,
        "distance": {
            "straight_line_km": distance_km,
            "is_live": distance_is_live,
            "label": "Straight-line Haversine distance",
        },
        "agreements": {
            "for_me": for_me,
            "for_partner": for_partner,
        },
        "my_safe_zones": my_zones,
        "my_journey": my_journey,
        "notification_prefs": my_prefs,
        "recent_sos": recent_sos,
        "recent_alerts": recent_alerts,
    }


def broadcast_safety_update(couple_id, event_name, payload=None):
    subs = SAFETY_SUBSCRIBERS.get(couple_id)
    if not subs:
        return
    msg = json.dumps({"event": event_name, "data": payload or {}, "ts": int(time.time() * 1000)})
    dead = []
    for q in list(subs):
        try:
            q.put_nowait(msg)
        except Exception:
            dead.append(q)
    for d in dead:
        subs.discard(d)


def _push_partner_notification(db, target_user_id, pref_key, title, body, deep_link="/safety"):
    prefs = db.get("safety_notif_prefs", {}).get(target_user_id, {})
    if prefs.get(pref_key, True) is False:
        return
    db.setdefault("notifications", []).insert(0, {
        "id": f"snotif_{int(time.time() * 1000)}",
        "user_id": target_user_id,
        "title": title,
        "body": body,
        "type": f"safety_{pref_key}",
        "deep_link": deep_link,
        "is_read": False,
        "created_at": "Just now",
    })


def get_openrouteservice_key():
    """Read OPENROUTESERVICE_API_KEY from backend environment without logging secrets."""
    key = (os.environ.get("OPENROUTESERVICE_API_KEY") or "").strip()
    if not key or key == "PASTE_YOUR_HEIGIT_OPENROUTESERVICE_KEY_HERE":
        return None
    return key


def proxy_heigit_route(db, origin_lat, origin_lng, dest_lat, dest_lng, travel_mode, save_fn):
    """Protected backend proxy to HeiGIT openrouteservice with graceful straight-line fallback."""
    ensure_safety_db(db)
    straight_m = haversine_meters(origin_lat, origin_lng, dest_lat, dest_lng)
    straight_km = round(straight_m / 1000.0, 2)
    api_key = get_openrouteservice_key()
    if not api_key or not db["safety_config"].get("routing_enabled", True):
        return 200, {
            "routing_available": False,
            "fallback": "straight_line",
            "straight_line_km": straight_km,
            "message": "Road routing unavailable (free HeiGIT OPENROUTESERVICE_API_KEY not configured on backend). Showing straight-line distance only.",
        }

    profile_map = {
        "car": "driving-car",
        "in_vehicle": "driving-car",
        "cycling": "cycling-regular",
        "bike": "cycling-regular",
        "walking": "foot-walking",
    }
    profile = profile_map.get(travel_mode, "driving-car")
    url = f"https://api.heigit.org/v2/directions/{profile}/geojson"
    payload = json.dumps({
        "coordinates": [[origin_lng, origin_lat], [dest_lng, dest_lat]]
    }).encode("utf-8")

    db["safety_metrics"]["route_requests"] = db["safety_metrics"].get("route_requests", 0) + 1
    try:
        req = urllib.request.Request(
            url,
            data=payload,
            method="POST",
            headers={
                "Authorization": api_key,
                "Content-Type": "application/json",
                "Accept": "application/json, application/geo+json",
            },
        )
        with urllib.request.urlopen(req, timeout=8) as resp:
            raw = json.loads(resp.read().decode("utf-8"))
        feat = (raw.get("features") or [{}])[0]
        summary = feat.get("properties", {}).get("summary", {})
        road_m = float(summary.get("distance", straight_m))
        dur_s = float(summary.get("duration", 0))
        coords = feat.get("geometry", {}).get("coordinates", [])
        save_fn(db)
        return 200, {
            "routing_available": True,
            "profile": profile,
            "straight_line_km": straight_km,
            "road_distance_km": round(road_m / 1000.0, 2),
            "eta_minutes": max(1, round(dur_s / 60.0)) if dur_s > 0 else None,
            "polyline": coords,
            "attribution": "Routing © openrouteservice.org by HeiGIT | Map data © OpenStreetMap contributors",
        }
    except urllib.error.HTTPError as e:
        err_msg = f"HTTP {e.code}"
        _log_safety_error(db, "heigit_routing", err_msg, save_fn)
        return 200, {
            "routing_available": False,
            "fallback": "straight_line",
            "straight_line_km": straight_km,
            "message": f"Road routing failed ({err_msg}). Degraded cleanly to straight-line distance.",
        }
    except Exception as e:
        safe = str(e).replace(api_key, "[REDACTED]")
        _log_safety_error(db, "heigit_routing", safe, save_fn)
        return 200, {
            "routing_available": False,
            "fallback": "straight_line",
            "straight_line_km": straight_km,
            "message": "Road routing unreachable. Degraded cleanly to straight-line distance.",
        }


def handle_safety_get(handler, path, query, load_db_fn, save_db_fn, verify_admin_fn):
    db = load_db_fn()
    ensure_safety_db(db)

    if path == "/api/safety/state":
        user_id = query.get("user_id", [""])[0]
        couple_id = query.get("couple_id", [""])[0]
        ok, user, couple, err = verify_user_and_couple(db, user_id, couple_id or None)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["safety_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "SoulSafe is globally disabled by Admin."}).encode("utf-8"))
            return True
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            state = _build_couple_safety_state(db_fresh, user, couple, save_db_fn)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "safety": state}).encode("utf-8"))
        return True

    if path == "/api/safety/history":
        user_id = query.get("user_id", [""])[0]
        ok, user, couple, err = verify_user_and_couple(db, user_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        hist = db["safety_history"].get(user_id, [])
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "history": hist}).encode("utf-8"))
        return True

    if path == "/api/safety/stream":
        user_id = query.get("user_id", [""])[0]
        couple_id = query.get("couple_id", [""])[0]
        ok, user, couple, err = verify_user_and_couple(db, user_id, couple_id or None)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        cid = couple.get("id")
        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Cache-Control", "no-cache")
        handler.send_header("Connection", "keep-alive")
        handler.send_header("Access-Control-Allow-Origin", "*")
        handler.end_headers()

        q = queue.Queue()
        with SAFETY_LOCK:
            SAFETY_SUBSCRIBERS.setdefault(cid, set()).add(q)
        try:
            while True:
                try:
                    msg = q.get(timeout=4.0)
                    handler.wfile.write(f"data: {msg}\n\n".encode("utf-8"))
                    handler.wfile.flush()
                except queue.Empty:
                    handler.wfile.write(b": ping\n\n")
                    handler.wfile.flush()
        except Exception:
            pass
        finally:
            with SAFETY_LOCK:
                subs = SAFETY_SUBSCRIBERS.get(cid)
                if subs:
                    subs.discard(q)
        return True

    if path == "/api/admin/safety/overview":
        admin, err = verify_admin_fn(handler, db)
        if not admin:
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        sessions = db.get("safety_sessions", {}).values()
        active_cnt = sum(1 for s in sessions if s.get("status") == "active")
        paused_cnt = sum(1 for s in sessions if s.get("status") == "paused")
        driving_cnt = sum(1 for s in sessions if s.get("status") == "active" and s.get("driving_mode"))
        metrics = db.get("safety_metrics", {})
        fcm_configured = bool((os.environ.get("FCM_SERVICE_ACCOUNT_PATH") or "").strip())
        # Strict privacy: ONLY aggregate counts, health & config — ZERO coordinates, ZERO speeds, ZERO histories!
        handler._set_headers(200)
        handler.wfile.write(json.dumps({
            "status": "success",
            "config": db["safety_config"],
            "stats": {
                "active_sharing_sessions": active_cnt,
                "paused_sessions": paused_cnt,
                "driving_mode_active": driving_cnt,
                "total_updates": metrics.get("total_updates", 0),
                "total_journeys": metrics.get("total_journeys", 0),
                "total_alerts": metrics.get("total_alerts", 0),
                "total_sos": metrics.get("total_sos", 0),
                "route_requests": metrics.get("route_requests", 0),
            },
            "services": {
                "maplibre_openfreemap": True,
                "routing_heigit_configured": bool(get_openrouteservice_key()),
                "fcm_configured": fcm_configured,
            },
            "error_logs": db.get("safety_error_logs", [])[:30],
        }).encode("utf-8"))
        return True

    return False


def handle_safety_post(handler, path, data, load_db_fn, save_db_fn, verify_admin_fn):
    db = load_db_fn()
    ensure_safety_db(db)
    now_iso = datetime.utcnow().isoformat() + "Z"
    now_ms = int(time.time() * 1000)

    if path == "/api/safety/consent":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["safety_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "SoulSafe is disabled by Admin."}).encode("utf-8"))
            return True

        cid = couple.get("id")
        action = data.get("action", "start")  # start | pause | resume | stop | update_consents
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            sess = db_fresh["safety_sessions"].setdefault(user_id, _default_session(user_id, cid))
            partner = get_partner_user(db_fresh, user, couple)

            if isinstance(data.get("consents"), dict):
                for ck, cv in data["consents"].items():
                    if ck in sess["consents"]:
                        sess["consents"][ck] = bool(cv)
            if "history_retention_days" in data:
                sess["history_retention_days"] = max(1, min(90, int(data["history_retention_days"])))
            if "daily_sharing" in data:
                sess["daily_sharing"] = bool(data["daily_sharing"])
            if data.get("travel_mode") in ALLOWED_MODES:
                old_mode = sess.get("travel_mode")
                sess["travel_mode"] = data["travel_mode"]
                if partner and old_mode != sess["travel_mode"] and sess.get("status") == "active":
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "vehicle_changed",
                        f"{user.get('name', 'Partner')} travel update",
                        f"{user.get('name', 'Partner')} switched travel mode to {sess['travel_mode']}.",
                    )
            if "driving_mode" in data:
                new_dm = bool(data["driving_mode"])
                old_dm = bool(sess.get("driving_mode"))
                sess["driving_mode"] = new_dm
                if partner and new_dm and not old_dm:
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "driving_mode",
                        "Driving Mode Active 🚗",
                        f"{user.get('name', 'Partner')} enabled Driving Mode.",
                    )

            if action == "start":
                dur_key = data.get("duration_key", sess.get("duration_key", "8h"))
                allowed = db_fresh["safety_config"].get("allowed_durations", ["1h", "8h", "12h", "manual"])
                if dur_key not in allowed:
                    dur_key = allowed[0] if allowed else "8h"
                dur_s = DURATION_SECONDS.get(dur_key)
                sess["session_id"] = f"ssess_{now_ms}"
                sess["status"] = "active"
                sess["duration_key"] = dur_key
                sess["started_at"] = now_iso
                sess["consents"]["location"] = True
                if dur_s:
                    exp_dt = datetime.utcnow() + timedelta(seconds=dur_s)
                    sess["expires_at"] = exp_dt.isoformat() + "Z"
                    sess["expires_at_ms"] = now_ms + dur_s * 1000
                else:
                    sess["expires_at"] = None
                    sess["expires_at_ms"] = None
                if partner:
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "sharing_started",
                        "Live Location Shared 📍",
                        f"{user.get('name', 'Partner')} started sharing their live location.",
                    )
            elif action == "pause":
                sess["status"] = "paused"
            elif action == "resume":
                if not _check_session_expiry(sess, db_fresh):
                    sess["status"] = "active"
                    sess["consents"]["location"] = True
            elif action == "stop":
                # Record optional history summary ONLY if explicit history consent is true
                if sess.get("consents", {}).get("history") and sess.get("started_at"):
                    db_fresh["safety_history"].setdefault(user_id, []).insert(0, {
                        "id": f"shist_{now_ms}",
                        "started_at": sess.get("started_at"),
                        "stopped_at": now_iso,
                        "travel_mode": sess.get("travel_mode"),
                        "duration_key": sess.get("duration_key"),
                    })
                    db_fresh["safety_history"][user_id] = db_fresh["safety_history"][user_id][:50]
                sess["status"] = "stopped"
                sess["consents"]["location"] = False
                sess["driving_mode"] = False
                sess["expires_at"] = None
                sess["expires_at_ms"] = None
                db_fresh["safety_locations"].pop(user_id, None)
                if partner:
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "sharing_stopped",
                        "Location Sharing Stopped",
                        f"{user.get('name', 'Partner')} stopped sharing their live location.",
                    )

            save_db_fn(db_fresh)
            state = _build_couple_safety_state(db_fresh, user, couple, save_db_fn)
            broadcast_safety_update(cid, "consent_changed", {"user_id": user_id, "status": sess["status"]})
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "safety": state}).encode("utf-8"))
        return True

    if path == "/api/safety/location":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["safety_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "SoulSafe is disabled by Admin."}).encode("utf-8"))
            return True

        try:
            lat = float(data["lat"])
            lng = float(data["lng"])
            acc = float(data.get("horizontal_accuracy_m", 25.0))
            seq = int(data.get("sequence", 1))
        except Exception:
            handler._set_headers(400)
            handler.wfile.write(json.dumps({"error": "Invalid coordinate or accuracy fields."}).encode("utf-8"))
            return True

        if not (-90.0 <= lat <= 90.0) or not (-180.0 <= lng <= 180.0) or math.isnan(lat) or math.isnan(lng) or acc < 0:
            handler._set_headers(400)
            handler.wfile.write(json.dumps({"error": "Out-of-range coordinates."}).encode("utf-8"))
            return True

        cid = couple.get("id")
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            sess = db_fresh["safety_sessions"].setdefault(user_id, _default_session(user_id, cid))
            _check_session_expiry(sess, db_fresh)
            if sess.get("status") != "active" or not sess.get("consents", {}).get("location"):
                handler._set_headers(403)
                handler.wfile.write(json.dumps({"error": "Location sharing consent is not active or has expired."}).encode("utf-8"))
                return True

            prev = db_fresh["safety_locations"].get(user_id)
            observed_ms = int(data.get("observed_at_ms", now_ms))
            if prev and prev.get("session_id") == sess.get("session_id"):
                if seq < int(prev.get("sequence", 0)) or observed_ms < int(prev.get("observed_at_ms", 0)):
                    handler._set_headers(200)
                    handler.wfile.write(json.dumps({"status": "ignored_stale", "reason": "Out-of-order sequence or timestamp"}).encode("utf-8"))
                    return True

            # Reject impossible GPS jumps if distance implies > 250 km/h over a valid delta
            if prev and prev.get("server_received_ms"):
                dt_s = max(0.5, (now_ms - int(prev["server_received_ms"])) / 1000.0)
                if dt_s < 30.0:
                    jump_m = haversine_meters(float(prev["lat"]), float(prev["lng"]), lat, lng)
                    if (jump_m / dt_s) * 3.6 > 280.0 and acc > 40.0:
                        handler._set_headers(200)
                        handler.wfile.write(json.dumps({"status": "ignored_jump", "reason": "Implausible GPS jump rejected"}).encode("utf-8"))
                        return True

            raw_speed_mps = data.get("speed_mps")
            speed_kmh = None
            speed_available = False
            if raw_speed_mps is not None and acc <= 50.0:
                try:
                    smps = float(raw_speed_mps)
                    if 0.0 <= smps <= 80.0 and not math.isnan(smps):
                        speed_kmh = round(smps * 3.6, 1)
                        speed_available = True
                except Exception:
                    pass

            if data.get("travel_mode") in ALLOWED_MODES:
                sess["travel_mode"] = data["travel_mode"]

            db_fresh["safety_locations"][user_id] = {
                "session_id": sess.get("session_id"),
                "sequence": seq,
                "lat": lat,
                "lng": lng,
                "accuracy_m": round(acc, 1),
                "speed_kmh": speed_kmh,
                "speed_available": speed_available,
                "bearing": data.get("bearing"),
                "observed_at_ms": observed_ms,
                "observed_at": data.get("observed_at") or now_iso,
                "server_received_ms": now_ms,
                "server_received_at": now_iso,
                "battery_pct": data.get("battery_pct") if sess.get("consents", {}).get("battery") else None,
                "battery_charging": data.get("battery_charging") if sess.get("consents", {}).get("battery") else None,
                "is_live": True,
            }
            db_fresh["safety_metrics"]["total_updates"] = db_fresh["safety_metrics"].get("total_updates", 0) + 1
            save_db_fn(db_fresh)
            broadcast_safety_update(cid, "location_updated", {"user_id": user_id})

        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "speed_kmh": speed_kmh, "speed_available": speed_available}).encode("utf-8"))
        return True

    if path == "/api/safety/agreement":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["safety_config"].get("speed_alerts_enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "Speed alerts feature is disabled by Admin."}).encode("utf-8"))
            return True

        cid = couple.get("id")
        partner = get_partner_user(db, user, couple)
        pid = partner.get("id") if partner else data.get("target_user_id")
        op = data.get("operation", "propose")  # propose | accept | reject | counter | revoke
        target_uid = data.get("target_user_id") or (pid if op == "propose" else user_id)

        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            ag_map = db_fresh["safety_agreements"].setdefault(cid, {})
            key = f"for_{target_uid}"
            rec = ag_map.setdefault(key, {
                "target_user_id": target_uid,
                "proposed_by": None,
                "active_threshold_kmh": None,
                "pending_threshold_kmh": None,
                "status": "none",  # none | pending | accepted | rejected | revoked
                "version": 0,
                "accepted_at": None,
                "unit": "km/h",
            })

            min_k = db_fresh["safety_config"].get("min_threshold_kmh", 10)
            max_k = db_fresh["safety_config"].get("max_threshold_kmh", 200)

            if op == "propose":
                try:
                    val = float(data["threshold_kmh"])
                    assert min_k <= val <= max_k and not math.isnan(val)
                except Exception:
                    handler._set_headers(400)
                    handler.wfile.write(json.dumps({"error": f"Threshold must be between {min_k} and {max_k} km/h."}).encode("utf-8"))
                    return True
                # Proposing keeps existing active_threshold_kmh intact until accepted!
                rec["pending_threshold_kmh"] = round(val, 1)
                rec["proposed_by"] = user_id
                rec["status"] = "pending"
                if partner and target_uid == partner.get("id"):
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "speed_exceeded",
                        "Speed Alert Threshold Proposal",
                        f"{user.get('name', 'Partner')} proposed a {round(val, 1)} km/h safety alert threshold for your travel.",
                    )

            elif op in ("accept", "counter"):
                if target_uid != user_id:
                    handler._set_headers(403)
                    handler.wfile.write(json.dumps({"error": "Only the affected partner can accept or counter their own threshold."}).encode("utf-8"))
                    return True
                if op == "accept":
                    if rec.get("pending_threshold_kmh") is None:
                        handler._set_headers(400)
                        handler.wfile.write(json.dumps({"error": "No pending threshold proposal to accept."}).encode("utf-8"))
                        return True
                    rec["active_threshold_kmh"] = rec["pending_threshold_kmh"]
                    rec["pending_threshold_kmh"] = None
                    rec["status"] = "accepted"
                    rec["version"] = int(rec.get("version", 0)) + 1
                    rec["accepted_at"] = now_iso
                else:
                    try:
                        cval = float(data["threshold_kmh"])
                        assert min_k <= cval <= max_k
                    except Exception:
                        handler._set_headers(400)
                        handler.wfile.write(json.dumps({"error": f"Counter threshold must be between {min_k} and {max_k} km/h."}).encode("utf-8"))
                        return True
                    rec["active_threshold_kmh"] = round(cval, 1)
                    rec["pending_threshold_kmh"] = None
                    rec["status"] = "accepted"
                    rec["version"] = int(rec.get("version", 0)) + 1
                    rec["accepted_at"] = now_iso

            elif op == "reject":
                if target_uid != user_id:
                    handler._set_headers(403)
                    handler.wfile.write(json.dumps({"error": "Only the affected partner can reject."}).encode("utf-8"))
                    return True
                rec["pending_threshold_kmh"] = None
                if rec.get("active_threshold_kmh") is not None:
                    rec["status"] = "accepted"
                else:
                    rec["status"] = "rejected"

            elif op == "revoke":
                rec["active_threshold_kmh"] = None
                rec["pending_threshold_kmh"] = None
                rec["status"] = "revoked"
                rec["version"] = int(rec.get("version", 0)) + 1

            save_db_fn(db_fresh)
            state = _build_couple_safety_state(db_fresh, user, couple, save_db_fn)
            broadcast_safety_update(cid, "agreement_updated", {"target_user_id": target_uid})
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "safety": state}).encode("utf-8"))
        return True

    if path == "/api/safety/alert":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        event_id = data.get("event_id") or f"alt_{now_ms}"
        cid = couple.get("id")
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            if any(a.get("id") == event_id for a in db_fresh["safety_alerts"]):
                handler._set_headers(200)
                handler.wfile.write(json.dumps({"status": "duplicate_ignored"}).encode("utf-8"))
                return True
            alert_rec = {
                "id": event_id,
                "couple_id": cid,
                "user_id": user_id,
                "user_name": user.get("name", "Partner"),
                "speed_kmh": round(float(data.get("speed_kmh", 0)), 1),
                "threshold_kmh": round(float(data.get("threshold_kmh", 0)), 1),
                "sustained_seconds": int(data.get("sustained_seconds", 15)),
                "timestamp": now_iso,
            }
            db_fresh["safety_alerts"].insert(0, alert_rec)
            db_fresh["safety_alerts"] = db_fresh["safety_alerts"][:100]
            db_fresh["safety_metrics"]["total_alerts"] = db_fresh["safety_metrics"].get("total_alerts", 0) + 1
            partner = get_partner_user(db_fresh, user, couple)
            if partner and data.get("notify_partner", True):
                _push_partner_notification(
                    db_fresh,
                    partner["id"],
                    "speed_exceeded",
                    "Speed Safety Notice ⚠️",
                    f"{user.get('name', 'Your partner')}'s estimated speed exceeded their agreed threshold ({alert_rec['threshold_kmh']} km/h).",
                )
            save_db_fn(db_fresh)
            broadcast_safety_update(cid, "alert", alert_rec)
        handler._set_headers(201)
        handler.wfile.write(json.dumps({"status": "success", "alert": alert_rec}).encode("utf-8"))
        return True

    if path == "/api/safety/safe-zones":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if data.get("owner_id") and data.get("owner_id") != user_id:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": "Hidden partner-created safe zones are strictly forbidden."}).encode("utf-8"))
            return True
        op = data.get("operation", "create")  # create | delete | event
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            zones = db_fresh["safety_safe_zones"].setdefault(user_id, [])
            if op == "create":
                z = {
                    "id": f"zone_{now_ms}",
                    "name": (data.get("name") or "Home").strip(),
                    "lat": float(data.get("lat", 0)),
                    "lng": float(data.get("lng", 0)),
                    "radius_m": max(50, min(2000, int(data.get("radius_m", 150)))),
                    "enabled": True,
                }
                zones.append(z)
            elif op == "delete":
                zid = data.get("zone_id")
                db_fresh["safety_safe_zones"][user_id] = [z for z in zones if z.get("id") != zid]
            elif op == "event":
                partner = get_partner_user(db_fresh, user, couple)
                zname = data.get("zone_name", "Safe Zone")
                ev_type = data.get("event_type", "arrived")
                if partner:
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "safe_zone",
                        f"Safe Zone: {zname}",
                        f"{user.get('name', 'Partner')} {ev_type} at {zname}.",
                    )
            save_db_fn(db_fresh)
            state = _build_couple_safety_state(db_fresh, user, couple, save_db_fn)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "safety": state}).encode("utf-8"))
        return True

    if path == "/api/safety/journey":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        op = data.get("operation", "start")  # start | end | reached_safely
        cid = couple.get("id")
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            partner = get_partner_user(db_fresh, user, couple)
            if op == "start":
                db_fresh["safety_journeys"][user_id] = {
                    "id": f"jrn_{now_ms}",
                    "active": True,
                    "travel_mode": data.get("travel_mode", "car"),
                    "destination": data.get("destination"),
                    "started_at": now_iso,
                }
                db_fresh["safety_metrics"]["total_journeys"] = db_fresh["safety_metrics"].get("total_journeys", 0) + 1
            elif op == "end":
                if user_id in db_fresh["safety_journeys"]:
                    db_fresh["safety_journeys"][user_id]["active"] = False
                    db_fresh["safety_journeys"][user_id]["ended_at"] = now_iso
            elif op == "reached_safely":
                if user_id in db_fresh["safety_journeys"]:
                    db_fresh["safety_journeys"][user_id]["active"] = False
                    db_fresh["safety_journeys"][user_id]["ended_at"] = now_iso
                msg = (data.get("message") or "I reached safely ❤️").strip()
                if partner:
                    _push_partner_notification(
                        db_fresh,
                        partner["id"],
                        "safe_zone",
                        f"{user.get('name', 'Partner')} Reached Safely 💚",
                        msg,
                    )
            save_db_fn(db_fresh)
            state = _build_couple_safety_state(db_fresh, user, couple, save_db_fn)
            broadcast_safety_update(cid, "journey_updated", {"user_id": user_id, "operation": op})
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "safety": state}).encode("utf-8"))
        return True

    if path == "/api/safety/route":
        user_id = data.get("user_id")
        ok, _, _, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        try:
            olat = float(data["origin_lat"])
            olng = float(data["origin_lng"])
            dlat = float(data["dest_lat"])
            dlng = float(data["dest_lng"])
        except Exception:
            handler._set_headers(400)
            handler.wfile.write(json.dumps({"error": "origin_lat, origin_lng, dest_lat, dest_lng are required."}).encode("utf-8"))
            return True
        code, res_body = proxy_heigit_route(db, olat, olng, dlat, dlng, data.get("travel_mode", "car"), save_db_fn)
        handler._set_headers(code)
        handler.wfile.write(json.dumps(res_body).encode("utf-8"))
        return True

    if path == "/api/safety/sos":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        cid = couple.get("id")
        sos_id = data.get("event_id") or f"sos_{now_ms}"
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            sos_rec = {
                "id": sos_id,
                "couple_id": cid,
                "user_id": user_id,
                "user_name": user.get("name", "Partner"),
                "message": (data.get("message") or "Emergency SOS triggered! Please check on me immediately.").strip(),
                "lat": data.get("lat") if data.get("consent_one_time_location") else None,
                "lng": data.get("lng") if data.get("consent_one_time_location") else None,
                "timestamp": now_iso,
            }
            db_fresh["safety_sos"].insert(0, sos_rec)
            db_fresh["safety_sos"] = db_fresh["safety_sos"][:50]
            db_fresh["safety_metrics"]["total_sos"] = db_fresh["safety_metrics"].get("total_sos", 0) + 1
            partner = get_partner_user(db_fresh, user, couple)
            if partner:
                db_fresh.setdefault("notifications", []).insert(0, {
                    "id": f"snotif_{now_ms}",
                    "user_id": partner["id"],
                    "title": f"🚨 URGENT SOS from {user.get('name', 'Partner')}!",
                    "body": sos_rec["message"],
                    "type": "safety_sos",
                    "deep_link": "/safety",
                    "is_read": False,
                    "created_at": "Just now",
                })
            save_db_fn(db_fresh)
            broadcast_safety_update(cid, "sos", sos_rec)
        handler._set_headers(201)
        handler.wfile.write(json.dumps({"status": "sent", "sos": sos_rec}).encode("utf-8"))
        return True

    if path == "/api/safety/history/clear":
        user_id = data.get("user_id")
        ok, _, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            db_fresh["safety_history"][user_id] = []
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "message": "Location history permanently deleted."}).encode("utf-8"))
        return True

    if path == "/api/safety/notif-prefs":
        user_id = data.get("user_id")
        ok, user, couple, err = verify_user_and_couple(db, user_id, data.get("couple_id"))
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            prefs = db_fresh["safety_notif_prefs"].setdefault(user_id, {})
            if isinstance(data.get("prefs"), dict):
                for k, v in data["prefs"].items():
                    prefs[k] = bool(v)
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "notification_prefs": prefs}).encode("utf-8"))
        return True

    if path == "/api/safety/fcm-token":
        user_id = data.get("user_id")
        token = (data.get("token") or "").strip()
        op = data.get("operation", "register")
        if not user_id:
            handler._set_headers(400)
            handler.wfile.write(json.dumps({"error": "user_id required"}).encode("utf-8"))
            return True
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            toks = db_fresh["safety_fcm_tokens"].setdefault(user_id, [])
            if op == "revoke":
                db_fresh["safety_fcm_tokens"][user_id] = [t for t in toks if t != token] if token else []
            elif token and token not in toks:
                toks.append(token)
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))
        return True

    if path == "/api/admin/safety/config":
        admin, err = verify_admin_fn(handler, db)
        if not admin:
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with SAFETY_LOCK:
            db_fresh = load_db_fn()
            ensure_safety_db(db_fresh)
            cfg = db_fresh["safety_config"]
            if "enabled" in data:
                cfg["enabled"] = bool(data["enabled"])
                if not cfg["enabled"]:
                    # Global disable immediately revokes active sessions
                    for uid, s in db_fresh["safety_sessions"].items():
                        if s.get("status") in ("active", "paused"):
                            s["status"] = "stopped"
                            s["consents"]["location"] = False
                            db_fresh["safety_locations"].pop(uid, None)
            if "speed_alerts_enabled" in data:
                cfg["speed_alerts_enabled"] = bool(data["speed_alerts_enabled"])
            if "routing_enabled" in data:
                cfg["routing_enabled"] = bool(data["routing_enabled"])
            if isinstance(data.get("allowed_durations"), list):
                cfg["allowed_durations"] = data["allowed_durations"]
            if isinstance(data.get("notification_templates"), dict):
                cfg["notification_templates"].update(data["notification_templates"])
            db_fresh.setdefault("audit_logs", []).insert(0, {
                "id": f"aud_{now_ms}",
                "admin": admin.get("email"),
                "action": "UPDATE_SOULSAFE_CONFIG",
                "details": f"SoulSafe enabled={cfg['enabled']}, speed_alerts={cfg['speed_alerts_enabled']}",
                "timestamp": datetime.utcnow().strftime("%b %d, %Y - %H:%M UTC"),
            })
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "config": cfg}).encode("utf-8"))
        return True

    return False
