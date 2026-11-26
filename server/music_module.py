import json
import os
import queue
import random
import re
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime
from urllib.parse import parse_qs, urlencode, urlparse

MUSIC_LOCK = threading.Lock()
MUSIC_SUBSCRIBERS = {}  # couple_id -> set of queue.Queue
RECENT_COMMANDS = {}    # couple_id -> list of recent command_ids (max 50)
REACTION_COOLDOWN = {}  # user_id -> last reaction epoch sec


def extract_youtube_video_id(text):
    """Extract an 11-char YouTube video ID if text is a valid YouTube URL."""
    s = (text or "").strip()
    if not s or " " in s:
        return None
    if re.match(r"^[A-Za-z0-9_-]{11}$", s):
        return s
    try:
        parsed = urlparse(s if "://" in s else "https://" + s)
        host = (parsed.netloc or "").lower()
        if "youtu.be" in host:
            cand = parsed.path.strip("/").split("/")[0]
            return cand if re.match(r"^[A-Za-z0-9_-]{11}$", cand) else None
        if "youtube.com" in host or "youtube-nocookie.com" in host:
            qs = parse_qs(parsed.query)
            if "v" in qs and re.match(r"^[A-Za-z0-9_-]{11}$", qs["v"][0]):
                return qs["v"][0]
            parts = [p for p in parsed.path.split("/") if p]
            if len(parts) >= 2 and parts[0] in ("shorts", "embed", "live", "v"):
                cand = parts[1]
                return cand if re.match(r"^[A-Za-z0-9_-]{11}$", cand) else None
    except Exception:
        return None
    return None


def parse_iso8601_duration(dur_str):
    """Convert YouTube ISO-8601 duration (e.g., PT3M45S) into integer seconds."""
    if not dur_str:
        return 0
    m = re.match(r"^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$", dur_str)
    if not m:
        return 0
    hours = int(m.group(1) or 0)
    minutes = int(m.group(2) or 0)
    seconds = int(m.group(3) or 0)
    return hours * 3600 + minutes * 60 + seconds


def sanitize_text(val, max_len=280):
    s = re.sub(r"[<>]", "", str(val or "")).strip()
    return s[:max_len]


def ensure_music_db(db):
    """Ensure all Listen Together collections exist without altering existing data."""
    today_str = datetime.utcnow().strftime("%Y-%m-%d")
    db.setdefault("music_rooms", {})
    db.setdefault("music_playlists", [])
    db.setdefault("music_likes", {})           # user_id -> list of tracks
    db.setdefault("music_like_consents", {})   # user_id -> bool (private by default)
    db.setdefault("music_dedications", [])     # private couple song dedications
    db.setdefault("music_memories", [])        # private musical memories CRUD
    db.setdefault("music_search_history", {})  # user_id -> list of queries
    db.setdefault("music_playback_events", [])
    db.setdefault("music_session_history", [])
    db.setdefault("music_error_logs", [])
    db.setdefault("music_reports", [])
    db.setdefault("youtube_cache", {})
    cfg = db.setdefault("music_config", {
        "enabled": True,
        "allow_together_mode": True,
        "daily_quota_limit": 10000,
        "quota_used_today": 0,
        "quota_date": today_str,
        "cache_hits": 0,
    })
    if cfg.get("quota_date") != today_str:
        cfg["quota_date"] = today_str
        cfg["quota_used_today"] = 0


def _log_music_error(db, source, message, save_fn):
    ensure_music_db(db)
    db["music_error_logs"].insert(0, {
        "id": f"merr_{int(time.time() * 1000)}",
        "source": source,
        "message": str(message)[:400],
        "timestamp": datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S UTC"),
    })
    db["music_error_logs"] = db["music_error_logs"][:100]
    save_fn(db)


def verify_couple_access(db, user_id, couple_id):
    """Enforce that user_id belongs strictly to couple_id."""
    if not user_id or not couple_id:
        return False, None, None, "user_id and couple_id are required."
    user = next((u for u in db.get("users", []) if u.get("id") == user_id), None)
    if not user:
        return False, None, None, "Unauthorized: User account not found."
    if user.get("couple_id") != couple_id:
        return False, None, None, "Forbidden: Only connected couple partners can access this private room."
    couple = next((c for c in db.get("couples", []) if c.get("id") == couple_id), None)
    if not couple:
        return False, None, None, "Couple connection not found."
    return True, user, couple, None


def get_partner_for_user(db, user, couple):
    """Find partner user record in the same couple."""
    if not couple:
        return None
    u_id = user.get("id")
    u_email = (user.get("email") or "").lower()
    p1_id = couple.get("p1_id") or couple.get("partner1_id")
    p2_id = couple.get("p2_id") or couple.get("partner2_id")
    p_id = p2_id if p1_id == u_id else p1_id
    if p_id:
        found = next((u for u in db.get("users", []) if u.get("id") == p_id), None)
        if found:
            return found
    for u in db.get("users", []):
        if u.get("couple_id") == couple.get("id") and u.get("id") != u_id and (u.get("email") or "").lower() != u_email:
            return u
    partner_label = couple.get("p2") if couple.get("p1") == user.get("name") else couple.get("p1")
    if partner_label:
        return {"id": p_id, "name": partner_label, "avatar_url": None}
    return None


def compute_room_snapshot(room):
    """Return authoritative room snapshot with live server-computed playback position & shared timer check."""
    now_ms = int(time.time() * 1000)
    pb = dict(room.get("playback", {}))

    # Enforce agreed shared sleep timer expiry
    st_timer = room.get("sleep_timer")
    if isinstance(st_timer, dict) and st_timer.get("status") == "active":
        exp_ms = int(st_timer.get("expires_at_ms") or 0)
        if exp_ms and now_ms >= exp_ms:
            if pb.get("is_playing") and pb.get("video_id"):
                elapsed = max(0.0, (exp_ms - int(pb.get("anchor_timestamp_ms", now_ms))) / 1000.0)
                pb["position_seconds"] = float(pb.get("position_seconds", 0.0)) + elapsed
                pb["is_playing"] = False
                pb["anchor_timestamp_ms"] = now_ms
                pb["event_seq"] = int(pb.get("event_seq", 0)) + 1
                room["playback"] = pb
            st_timer["status"] = "expired"

    pos = float(pb.get("position_seconds", 0.0))
    dur = float(pb.get("duration_seconds", 0.0))
    rate = float(pb.get("playback_rate", 1.0))
    is_playing = bool(pb.get("is_playing", False))
    anchor_ms = int(pb.get("anchor_timestamp_ms", now_ms))

    if is_playing and pb.get("video_id"):
        elapsed = max(0.0, (now_ms - anchor_ms) / 1000.0) * rate
        live_pos = pos + elapsed
        if dur > 0 and live_pos >= dur:
            live_pos = dur
    else:
        live_pos = pos

    pb["live_position_seconds"] = round(live_pos, 3)
    pb["server_now_ms"] = now_ms

    participants_out = {}
    for uid, pinfo in room.get("participants", {}).items():
        p_copy = dict(pinfo)
        last_hb = int(p_copy.get("last_heartbeat_ms", 0))
        if p_copy.get("online") and last_hb and (now_ms - last_hb > 25000):
            p_copy["online"] = False
            p_copy["state"] = "reconnecting"
        participants_out[uid] = p_copy

    return {
        "id": room.get("id"),
        "couple_id": room.get("couple_id"),
        "creator_id": room.get("creator_id"),
        "host_id": room.get("host_id"),
        "mode": room.get("mode", "together"),
        "created_at": room.get("created_at"),
        "participants": participants_out,
        "playback": pb,
        "queue": room.get("queue", []),
        "recently_played": room.get("recently_played", []),
        "suggestions": room.get("suggestions", []),
        "sleep_timer": room.get("sleep_timer"),
        "server_now_ms": now_ms,
    }


def broadcast_room_update(couple_id, room_snapshot, event_type="sync", extra=None):
    subs = MUSIC_SUBSCRIBERS.get(couple_id)
    if not subs:
        return
    body = {"event": event_type, "room": room_snapshot}
    if extra:
        body.update(extra)
    payload = json.dumps(body)
    dead = []
    for q in list(subs):
        try:
            q.put_nowait(payload)
        except Exception:
            dead.append(q)
    for d in dead:
        subs.discard(d)


def ensure_default_playlists(db, couple_id, user_id, save_fn):
    ensure_music_db(db)
    existing = [p for p in db["music_playlists"] if p.get("couple_id") == couple_id]
    if not existing:
        db["music_playlists"].append({
            "id": f"pl_{couple_id}_our_songs",
            "couple_id": couple_id,
            "name": "Our Songs",
            "artwork_emoji": "💖",
            "artwork_color": "#E94057",
            "is_our_songs": True,
            "created_by": user_id,
            "created_at": datetime.utcnow().isoformat() + "Z",
            "songs": [],
        })
        save_fn(db)


def youtube_search(query_str, db, get_key_fn, save_fn, page_token=None, user_id=None):
    """Search YouTube songs OR resolve a direct YouTube URL (1 quota unit) with caching & quota safety."""
    ensure_music_db(db)
    cfg = db["music_config"]
    if not cfg.get("enabled", True):
        return 503, {"error": "Music feature is temporarily disabled by Administrator."}

    q_clean = (query_str or "").strip()
    if not q_clean:
        return 400, {"error": "Please enter a song name, singer, or YouTube link."}

    if user_id and not q_clean.startswith("http"):
        hist = db["music_search_history"].setdefault(user_id, [])
        hist = [h for h in hist if h.lower() != q_clean.lower()]
        hist.insert(0, q_clean)
        db["music_search_history"][user_id] = hist[:15]

    api_key = get_key_fn()
    if not api_key:
        _log_music_error(db, "youtube_search", "YOUTUBE_API_KEY missing in backend .env", save_fn)
        return 503, {"error": "YouTube API key is not configured on backend."}

    now_s = int(time.time())

    # Fast URL resolution (1 quota unit instead of 100!)
    direct_vid = extract_youtube_video_id(q_clean)
    if direct_vid:
        cache_key = f"vid:{direct_vid}"
        cached = db["youtube_cache"].get(cache_key)
        if cached and (now_s - cached.get("ts", 0)) < 3600:
            cfg["cache_hits"] = cfg.get("cache_hits", 0) + 1
            save_fn(db)
            return 200, {"status": "success", "cached": True, "resolved_url": True, "results": cached.get("results", []), "quota_used_today": cfg.get("quota_used_today", 0)}

        if cfg.get("quota_used_today", 0) + 1 > cfg.get("daily_quota_limit", 10000):
            return 429, {"error": "Daily YouTube API quota limit reached."}

        vid_params = urlencode({"part": "snippet,contentDetails,status", "id": direct_vid, "key": api_key})
        try:
            with urllib.request.urlopen(urllib.request.Request(f"https://www.googleapis.com/youtube/v3/videos?{vid_params}", method="GET"), timeout=8) as r:
                vdata = json.loads(r.read().decode("utf-8"))
            cfg["quota_used_today"] = cfg.get("quota_used_today", 0) + 1
            items = vdata.get("items", [])
            if not items:
                save_fn(db)
                return 404, {"error": "Video not found, private, or removed on YouTube."}
            it = items[0]
            if not it.get("status", {}).get("embeddable", True):
                save_fn(db)
                return 422, {"error": "Owner disabled embedding for this YouTube video."}
            sn = it.get("snippet", {})
            thumbs = sn.get("thumbnails", {})
            thumb = thumbs.get("high", {}).get("url") or thumbs.get("medium", {}).get("url") or f"https://img.youtube.com/vi/{direct_vid}/hqdefault.jpg"
            res_list = [{
                "video_id": direct_vid,
                "title": sn.get("title", "YouTube Video"),
                "artist": sn.get("channelTitle", "YouTube"),
                "thumbnail": thumb,
                "duration_seconds": parse_iso8601_duration(it.get("contentDetails", {}).get("duration", "")),
            }]
            db["youtube_cache"][cache_key] = {"ts": now_s, "results": res_list}
            save_fn(db)
            return 200, {"status": "success", "cached": False, "resolved_url": True, "results": res_list, "quota_used_today": cfg.get("quota_used_today", 0)}
        except Exception as e:
            safe = str(e).replace(api_key, "[REDACTED]")
            _log_music_error(db, "youtube_video_resolve", safe, save_fn)
            return 502, {"error": f"Unable to resolve YouTube link: {safe}"}

    cache_key = f"search:{q_clean.lower()}:{page_token or ''}"
    cached = db["youtube_cache"].get(cache_key)
    if cached and (now_s - cached.get("ts", 0)) < 3600:
        cfg["cache_hits"] = cfg.get("cache_hits", 0) + 1
        save_fn(db)
        return 200, {
            "status": "success",
            "cached": True,
            "next_page_token": cached.get("next_page_token"),
            "results": cached.get("results", []),
            "quota_used_today": cfg.get("quota_used_today", 0),
        }

    if cfg.get("quota_used_today", 0) + 101 > cfg.get("daily_quota_limit", 10000):
        _log_music_error(db, "youtube_search", "Daily quota limit reached", save_fn)
        return 429, {"error": "Daily YouTube API search quota limit reached. Try saved playlists or direct YouTube URLs."}

    sp = {
        "part": "snippet",
        "type": "video",
        "videoEmbeddable": "true",
        "maxResults": 10,
        "q": q_clean,
        "key": api_key,
    }
    if page_token:
        sp["pageToken"] = page_token
    search_url = f"https://www.googleapis.com/youtube/v3/search?{urlencode(sp)}"

    try:
        with urllib.request.urlopen(urllib.request.Request(search_url, method="GET"), timeout=8) as resp:
            search_data = json.loads(resp.read().decode("utf-8"))
        cfg["quota_used_today"] = cfg.get("quota_used_today", 0) + 100
    except urllib.error.HTTPError as e:
        err_msg = f"HTTP {e.code}"
        try:
            err_body = json.loads(e.read().decode("utf-8"))
            err_msg = err_body.get("error", {}).get("message", err_msg)
        except Exception:
            pass
        err_msg = err_msg.replace(api_key, "[REDACTED]")
        _log_music_error(db, "youtube_search", err_msg, save_fn)
        return (429 if e.code == 403 and "quota" in err_msg.lower() else 502), {"error": f"YouTube Search Error: {err_msg}"}
    except Exception as e:
        safe = str(e).replace(api_key, "[REDACTED]")
        _log_music_error(db, "youtube_search", safe, save_fn)
        return 502, {"error": f"Unable to reach YouTube API: {safe}"}

    raw_items = search_data.get("items", [])
    next_tok = search_data.get("nextPageToken")
    video_ids = []
    for it in raw_items:
        vid = it.get("id", {}).get("videoId")
        if vid and vid not in video_ids:
            video_ids.append(vid)

    if not video_ids:
        save_fn(db)
        return 200, {"status": "success", "cached": False, "results": [], "next_page_token": None}

    durations_map = {}
    embeddable_map = {}
    vid_params = urlencode({"part": "contentDetails,status", "id": ",".join(video_ids), "key": api_key})
    try:
        with urllib.request.urlopen(urllib.request.Request(f"https://www.googleapis.com/youtube/v3/videos?{vid_params}", method="GET"), timeout=8) as vresp:
            vid_data = json.loads(vresp.read().decode("utf-8"))
        cfg["quota_used_today"] = cfg.get("quota_used_today", 0) + 1
        for v in vid_data.get("items", []):
            vid = v.get("id")
            durations_map[vid] = parse_iso8601_duration(v.get("contentDetails", {}).get("duration", ""))
            embeddable_map[vid] = v.get("status", {}).get("embeddable", True)
    except Exception as e:
        safe = str(e).replace(api_key, "[REDACTED]")
        _log_music_error(db, "youtube_videos_details", safe, save_fn)

    results = []
    seen_vids = set()
    for it in raw_items:
        vid = it.get("id", {}).get("videoId")
        if not vid or vid in seen_vids or embeddable_map.get(vid, True) is False:
            continue
        seen_vids.add(vid)
        sn = it.get("snippet", {})
        thumbs = sn.get("thumbnails", {})
        thumb_url = (
            thumbs.get("high", {}).get("url")
            or thumbs.get("medium", {}).get("url")
            or thumbs.get("default", {}).get("url")
            or f"https://img.youtube.com/vi/{vid}/hqdefault.jpg"
        )
        results.append({
            "video_id": vid,
            "title": sn.get("title", "Untitled Song"),
            "artist": sn.get("channelTitle", "YouTube Artist"),
            "thumbnail": thumb_url,
            "duration_seconds": durations_map.get(vid, 0),
        })

    db["youtube_cache"][cache_key] = {"ts": now_s, "results": results, "next_page_token": next_tok}
    if len(db["youtube_cache"]) > 120:
        oldest_key = sorted(db["youtube_cache"].keys(), key=lambda k: db["youtube_cache"][k].get("ts", 0))[0]
        db["youtube_cache"].pop(oldest_key, None)

    save_fn(db)
    return 200, {
        "status": "success",
        "cached": False,
        "next_page_token": next_tok,
        "results": results,
        "quota_used_today": cfg.get("quota_used_today", 0),
    }


def _create_or_update_room(db, couple_id, user, mode="together", invite_partner=False, save_fn=None, is_create=False):
    ensure_music_db(db)
    now_iso = datetime.utcnow().isoformat() + "Z"
    now_ms = int(time.time() * 1000)
    rooms = db["music_rooms"]
    room = rooms.get(couple_id)
    if not room:
        room = {
            "id": f"room_{couple_id}",
            "couple_id": couple_id,
            "creator_id": user.get("id"),
            "host_id": user.get("id"),
            "mode": mode if mode in ("host", "together") else "together",
            "created_at": now_iso,
            "participants": {},
            "playback": {
                "video_id": None,
                "title": None,
                "artist": None,
                "thumbnail": None,
                "duration_seconds": 0,
                "is_playing": False,
                "position_seconds": 0.0,
                "playback_rate": 1.0,
                "anchor_timestamp_ms": now_ms,
                "repeat_mode": "none",
                "shuffle": False,
                "event_seq": 0,
                "updated_by": None,
            },
            "queue": [],
            "recently_played": [],
            "suggestions": [],
            "sleep_timer": None,
        }
        rooms[couple_id] = room
        db["music_session_history"].insert(0, {
            "id": f"msess_{now_ms}",
            "couple_id": couple_id,
            "started_at": now_iso,
            "creator_name": user.get("name", "Partner"),
            "mode": room["mode"],
        })
        db["music_session_history"] = db["music_session_history"][:100]
    elif is_create and mode in ("host", "together"):
        room["mode"] = mode
        if mode == "host":
            room["host_id"] = user.get("id")

    room.setdefault("suggestions", [])
    room.setdefault("sleep_timer", None)

    room["participants"][user.get("id")] = {
        "user_id": user.get("id"),
        "name": user.get("name", "Partner"),
        "avatar_url": user.get("avatar_url"),
        "online": True,
        "buffering": False,
        "state": "listening",
        "joined_at": now_iso,
        "last_heartbeat_ms": now_ms,
    }

    if invite_partner:
        couple = next((c for c in db.get("couples", []) if c.get("id") == couple_id), None)
        partner = get_partner_for_user(db, user, couple)
        if partner and partner.get("id"):
            db.setdefault("notifications", []).insert(0, {
                "id": f"notif_{now_ms}",
                "user_id": partner.get("id"),
                "title": f"{user.get('name', 'Your partner')} opened Listen Together 🎵",
                "body": "Tap to join your private couple listening room!",
                "type": "music_invite",
                "deep_link": "/music",
                "is_read": False,
                "created_at": "Just now",
            })

    if save_fn:
        save_fn(db)
    snap = compute_room_snapshot(room)
    broadcast_room_update(couple_id, snap)
    return snap


def _compute_likes_payload(db, user, couple):
    uid = user.get("id")
    my_likes = db.get("music_likes", {}).get(uid, [])
    my_consent = bool(db.get("music_like_consents", {}).get(uid, False))
    partner = get_partner_for_user(db, user, couple)
    pid = partner.get("id") if partner else None
    partner_consent = bool(pid and db.get("music_like_consents", {}).get(pid, False))
    mutual = []
    if my_consent and partner_consent and pid:
        p_likes = db.get("music_likes", {}).get(pid, [])
        p_vids = {t.get("video_id"): t for t in p_likes if t.get("video_id")}
        for ml in my_likes:
            vid = ml.get("video_id")
            if vid in p_vids:
                mutual.append(ml)
    return {
        "liked_songs": my_likes,
        "share_consent": my_consent,
        "partner_shared": partner_consent,
        "mutual_favourites": mutual,
    }


def _set_active_track(room, track, auto_play, user_name, now_iso, now_ms, position_sec=0.0):
    pb = room["playback"]
    vid = track.get("video_id")
    if pb.get("video_id") and pb.get("video_id") != vid:
        room["recently_played"] = [r for r in room.get("recently_played", []) if r.get("video_id") != pb["video_id"]]
        room["recently_played"].insert(0, {
            "video_id": pb["video_id"],
            "title": pb.get("title"),
            "artist": pb.get("artist"),
            "thumbnail": pb.get("thumbnail"),
            "duration_seconds": pb.get("duration_seconds", 0),
            "played_at": now_iso,
        })
        room["recently_played"] = room["recently_played"][:25]
    pb["video_id"] = vid
    pb["title"] = track.get("title", "Selected Song")
    pb["artist"] = track.get("artist", "YouTube")
    pb["thumbnail"] = track.get("thumbnail") or f"https://img.youtube.com/vi/{vid}/hqdefault.jpg"
    pb["duration_seconds"] = int(track.get("duration_seconds") or 0)
    pb["position_seconds"] = float(position_sec)
    pb["is_playing"] = bool(auto_play)
    pb["anchor_timestamp_ms"] = now_ms


def handle_music_get(handler, path, query, load_db_fn, save_db_fn, get_key_fn, verify_key_fn, verify_admin_fn):
    db = load_db_fn()
    ensure_music_db(db)

    if path == "/api/music/verify-key":
        result = verify_key_fn()
        cfg = db.get("music_config", {})
        result["quota_used_today"] = cfg.get("quota_used_today", 0)
        result["daily_quota_limit"] = cfg.get("daily_quota_limit", 10000)
        handler._set_headers(200 if result.get("connected") else 400 if result.get("configured") else 200)
        handler.wfile.write(json.dumps({"status": "success" if result.get("connected") else "pending", **result}).encode("utf-8"))
        return True

    if path == "/api/music/search":
        q = query.get("q", [""])[0]
        user_id = query.get("user_id", [""])[0]
        page_token = query.get("page_token", [""])[0] or None
        if user_id and not any(u.get("id") == user_id for u in db.get("users", [])):
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": "Unauthorized user"}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            code, payload = youtube_search(q, db_fresh, get_key_fn, save_db_fn, page_token=page_token, user_id=user_id or None)
        handler._set_headers(code)
        handler.wfile.write(json.dumps(payload).encode("utf-8"))
        return True

    if path == "/api/music/search-history":
        user_id = query.get("user_id", [""])[0]
        hist = db.get("music_search_history", {}).get(user_id, [])
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "history": hist}).encode("utf-8"))
        return True

    if path == "/api/music/room/state":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, user, couple, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["music_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "Listen Together is temporarily disabled by Admin."}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            room = db_fresh["music_rooms"].get(couple_id)
            partner = get_partner_for_user(db_fresh, user, couple)
            snap = compute_room_snapshot(room) if room else None
        handler._set_headers(200)
        handler.wfile.write(json.dumps({
            "status": "success",
            "room": snap,
            "partner": {
                "id": partner.get("id") if partner else None,
                "name": partner.get("name") if partner else user.get("partner_name") or "Partner",
                "avatar_url": partner.get("avatar_url") if partner else None,
            },
        }).encode("utf-8"))
        return True

    if path == "/api/music/room/stream":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True

        handler.send_response(200)
        handler.send_header("Content-Type", "text/event-stream")
        handler.send_header("Cache-Control", "no-cache")
        handler.send_header("Connection", "keep-alive")
        handler.send_header("Access-Control-Allow-Origin", "*")
        handler.end_headers()

        q = queue.Queue()
        with MUSIC_LOCK:
            MUSIC_SUBSCRIBERS.setdefault(couple_id, set()).add(q)
            room = db["music_rooms"].get(couple_id)
            if room:
                q.put_nowait(json.dumps({"event": "sync", "room": compute_room_snapshot(room)}))

        try:
            while True:
                try:
                    msg = q.get(timeout=4.0)
                    handler.wfile.write(f"data: {msg}\n\n".encode("utf-8"))
                    handler.wfile.flush()
                except queue.Empty:
                    db_hb = load_db_fn()
                    rm = db_hb.get("music_rooms", {}).get(couple_id)
                    if rm:
                        hb_msg = json.dumps({"event": "heartbeat", "room": compute_room_snapshot(rm)})
                        handler.wfile.write(f"data: {hb_msg}\n\n".encode("utf-8"))
                    else:
                        handler.wfile.write(b": ping\n\n")
                    handler.wfile.flush()
        except Exception:
            pass
        finally:
            with MUSIC_LOCK:
                subs = MUSIC_SUBSCRIBERS.get(couple_id)
                if subs:
                    subs.discard(q)
        return True

    if path == "/api/music/playlists":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, _, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_default_playlists(db_fresh, couple_id, user_id, save_db_fn)
            playlists = [p for p in db_fresh["music_playlists"] if p.get("couple_id") == couple_id]
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "playlists": playlists}).encode("utf-8"))
        return True

    if path == "/api/music/likes":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, user, couple, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", **_compute_likes_payload(db, user, couple)}).encode("utf-8"))
        return True

    if path == "/api/music/dedications":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, _, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        items = [d for d in db.get("music_dedications", []) if d.get("couple_id") == couple_id]
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "dedications": items[:50]}).encode("utf-8"))
        return True

    if path == "/api/music/memories":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, _, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        items = [m for m in db.get("music_memories", []) if m.get("couple_id") == couple_id]
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "memories": items}).encode("utf-8"))
        return True

    if path == "/api/music/recap":
        couple_id = query.get("couple_id", [""])[0]
        user_id = query.get("user_id", [""])[0]
        ok, _, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        rm = db.get("music_rooms", {}).get(couple_id, {})
        recap = {
            "shared_sessions": sum(1 for s in db.get("music_session_history", []) if s.get("couple_id") == couple_id),
            "liked_songs_count": len(db.get("music_likes", {}).get(user_id, [])),
            "playlists_count": sum(1 for p in db.get("music_playlists", []) if p.get("couple_id") == couple_id),
            "dedications_count": sum(1 for d in db.get("music_dedications", []) if d.get("couple_id") == couple_id),
            "musical_memories_count": sum(1 for m in db.get("music_memories", []) if m.get("couple_id") == couple_id),
            "recently_played_count": len(rm.get("recently_played", [])),
        }
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "recap": recap}).encode("utf-8"))
        return True

    if path == "/api/admin/music/overview":
        admin, err = verify_admin_fn(handler, db)
        if not admin:
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        cfg = db["music_config"]
        key_status = verify_key_fn()
        active_rooms = []
        for cid, rm in db.get("music_rooms", {}).items():
            pb = rm.get("playback", {})
            active_p = sum(1 for p in rm.get("participants", {}).values() if p.get("online"))
            active_rooms.append({
                "room_id": rm.get("id"),
                "couple_id": cid,
                "mode": rm.get("mode"),
                "connected_partners": active_p,
                "current_song": pb.get("title") or "Idle (No track selected)",
                "is_playing": bool(pb.get("is_playing")),
            })
        # Privacy: NEVER expose API secret, personal playlists, dedication texts, or musical memories to Admin
        handler._set_headers(200)
        handler.wfile.write(json.dumps({
            "status": "success",
            "config": cfg,
            "api_status": {
                "configured": bool(key_status.get("configured")),
                "connected": bool(key_status.get("connected")),
                "message": key_status.get("message"),
            },
            "stats": {
                "active_rooms_count": len(active_rooms),
                "total_sessions": len(db.get("music_session_history", [])),
                "total_playlists": len(db.get("music_playlists", [])),
                "total_events": len(db.get("music_playback_events", [])),
            },
            "active_rooms": active_rooms,
            "error_logs": db.get("music_error_logs", [])[:30],
            "reports": db.get("music_reports", [])[:30],
        }).encode("utf-8"))
        return True

    return False


def handle_music_post(handler, path, data, load_db_fn, save_db_fn, verify_admin_fn):
    db = load_db_fn()
    ensure_music_db(db)
    now_iso = datetime.utcnow().isoformat() + "Z"
    now_ms = int(time.time() * 1000)

    if path == "/api/music/search-history/clear":
        user_id = data.get("user_id")
        if user_id:
            with MUSIC_LOCK:
                db_fresh = load_db_fn()
                ensure_music_db(db_fresh)
                db_fresh["music_search_history"][user_id] = []
                save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))
        return True

    if path in ("/api/music/room/create", "/api/music/room/join"):
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        mode = data.get("mode", "together")
        invite_partner = bool(data.get("invite_partner", path == "/api/music/room/create"))

        ok, user, couple, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["music_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "Listen Together is currently disabled by Admin."}).encode("utf-8"))
            return True

        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_default_playlists(db_fresh, couple_id, user_id, save_db_fn)
            snap = _create_or_update_room(
                db_fresh,
                couple_id,
                user,
                mode=mode,
                invite_partner=invite_partner,
                save_fn=save_db_fn,
                is_create=(path == "/api/music/room/create"),
            )
            partner = get_partner_for_user(db_fresh, user, couple)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({
            "status": "success",
            "room": snap,
            "partner": {
                "id": partner.get("id") if partner else None,
                "name": partner.get("name") if partner else user.get("partner_name") or "Partner",
                "avatar_url": partner.get("avatar_url") if partner else None,
            },
        }).encode("utf-8"))
        return True

    if path == "/api/music/room/leave":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        ok, _, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            room = db_fresh["music_rooms"].get(couple_id)
            if room and user_id in room.get("participants", {}):
                room["participants"][user_id]["online"] = False
                room["participants"][user_id]["state"] = "left"
                room["participants"][user_id]["last_heartbeat_ms"] = now_ms
                save_db_fn(db_fresh)
                broadcast_room_update(couple_id, compute_room_snapshot(room))
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "message": "Left room while preserving playback session."}).encode("utf-8"))
        return True

    if path == "/api/music/room/reaction":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        emoji = (data.get("emoji") or "❤️")[:8]
        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        now_s = time.time()
        if now_s - REACTION_COOLDOWN.get(user_id, 0) < 1.2:
            handler._set_headers(429)
            handler.wfile.write(json.dumps({"error": "Slow down reactions slightly"}).encode("utf-8"))
            return True
        REACTION_COOLDOWN[user_id] = now_s
        rm = db.get("music_rooms", {}).get(couple_id)
        if rm:
            broadcast_room_update(
                couple_id,
                compute_room_snapshot(rm),
                event_type="reaction",
                extra={"reaction": {"emoji": emoji, "sender_id": user_id, "sender_name": user.get("name", "Partner"), "ts": now_ms}},
            )
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "emoji": emoji}).encode("utf-8"))
        return True

    if path == "/api/music/room/control":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        action = data.get("action", "")
        command_id = data.get("command_id")

        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        if not db["music_config"].get("enabled", True):
            handler._set_headers(503)
            handler.wfile.write(json.dumps({"error": "Listen Together is currently disabled by Admin."}).encode("utf-8"))
            return True

        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            room = db_fresh["music_rooms"].get(couple_id)
            if not room:
                _create_or_update_room(db_fresh, couple_id, user, save_fn=save_db_fn)
                room = db_fresh["music_rooms"][couple_id]

            room.setdefault("suggestions", [])
            room.setdefault("sleep_timer", None)

            if command_id:
                recent = RECENT_COMMANDS.setdefault(couple_id, [])
                if command_id in recent:
                    snap = compute_room_snapshot(room)
                    handler._set_headers(200)
                    handler.wfile.write(json.dumps({"status": "duplicate_ignored", "room": snap}).encode("utf-8"))
                    return True
                recent.append(command_id)
                if len(recent) > 50:
                    recent.pop(0)

            part = room["participants"].setdefault(user_id, {
                "user_id": user_id,
                "name": user.get("name", "Partner"),
                "avatar_url": user.get("avatar_url"),
            })
            part["online"] = True
            part["last_heartbeat_ms"] = now_ms
            if "buffering" in data:
                part["buffering"] = bool(data["buffering"])
            if "player_state" in data:
                part["state"] = data["player_state"]
            elif action != "heartbeat":
                part["state"] = "listening"

            if action == "heartbeat":
                save_db_fn(db_fresh)
                handler._set_headers(200)
                handler.wfile.write(json.dumps({"status": "success", "room": compute_room_snapshot(room)}).encode("utf-8"))
                return True

            # Actions allowed by non-host in Host Mode: suggest_track, sleep_timer_accept, sleep_timer_cancel
            guest_allowed = action in ("suggest_track", "sleep_timer_accept", "sleep_timer_cancel")
            playback_mutating = not guest_allowed and action not in ("heartbeat",)
            if playback_mutating and room.get("mode") == "host" and room.get("host_id") != user_id:
                handler._set_headers(403)
                handler.wfile.write(json.dumps({"error": "Host Mode is active: only the room host can control playback. Tap 'Suggest' instead!"}).encode("utf-8"))
                return True

            pb = room["playback"]
            snap_before = compute_room_snapshot(room)
            current_live_pos = snap_before["playback"]["live_position_seconds"]
            req_pos = data.get("position_seconds")

            if action == "mode":
                new_mode = data.get("mode", "together")
                if new_mode == "together" and not db_fresh["music_config"].get("allow_together_mode", True):
                    handler._set_headers(403)
                    handler.wfile.write(json.dumps({"error": "Together Mode is disabled by Admin."}).encode("utf-8"))
                    return True
                if new_mode in ("host", "together"):
                    room["mode"] = new_mode
                    if new_mode == "host":
                        room["host_id"] = user_id

            elif action == "suggest_track":
                track = data.get("track") or {}
                if track.get("video_id"):
                    room["suggestions"].insert(0, {
                        "id": f"sug_{now_ms}",
                        "suggested_by": user.get("name", "Partner"),
                        "track": track,
                        "created_at": now_iso,
                    })
                    room["suggestions"] = room["suggestions"][:10]

            elif action == "dismiss_suggestion":
                sid = data.get("suggestion_id")
                room["suggestions"] = [s for s in room["suggestions"] if s.get("id") != sid]

            elif action == "set_track":
                track = data.get("track") or {}
                if not track.get("video_id"):
                    handler._set_headers(400)
                    handler.wfile.write(json.dumps({"error": "track.video_id is required"}).encode("utf-8"))
                    return True
                _set_active_track(room, track, data.get("auto_play", True), user.get("name", user_id), now_iso, now_ms, position_sec=float(req_pos) if req_pos is not None else 0.0)

            elif action == "play_playlist":
                pl_id = data.get("playlist_id")
                pl = next((p for p in db_fresh["music_playlists"] if p.get("id") == pl_id and p.get("couple_id") == couple_id), None)
                songs = list(pl.get("songs", [])) if pl else []
                if not songs:
                    handler._set_headers(400)
                    handler.wfile.write(json.dumps({"error": "Playlist is empty."}).encode("utf-8"))
                    return True
                _set_active_track(room, songs[0], True, user.get("name", user_id), now_iso, now_ms)
                room["queue"] = [dict(s, added_by=user.get("name", "Partner")) for s in songs[1:]]

            elif action == "surprise":
                candidates = []
                for pl in db_fresh["music_playlists"]:
                    if pl.get("couple_id") == couple_id:
                        candidates.extend(pl.get("songs", []))
                candidates.extend(room.get("queue", []))
                candidates.extend(db_fresh.get("music_likes", {}).get(user_id, []))
                unique = {}
                for c in candidates:
                    v = c.get("video_id")
                    if v and v != pb.get("video_id"):
                        unique[v] = c
                if not unique:
                    handler._set_headers(400)
                    handler.wfile.write(json.dumps({"error": "Add a few songs to your playlists or likes first so Surprise Me can pick one!"}).encode("utf-8"))
                    return True
                chosen = random.choice(list(unique.values()))
                _set_active_track(room, chosen, True, user.get("name", user_id), now_iso, now_ms)

            elif action in ("play", "resume"):
                pb["position_seconds"] = float(req_pos) if req_pos is not None else current_live_pos
                pb["is_playing"] = True
                pb["anchor_timestamp_ms"] = now_ms

            elif action == "pause":
                pb["position_seconds"] = float(req_pos) if req_pos is not None else current_live_pos
                pb["is_playing"] = False
                pb["anchor_timestamp_ms"] = now_ms

            elif action == "seek":
                pb["position_seconds"] = max(0.0, float(req_pos if req_pos is not None else 0.0))
                pb["anchor_timestamp_ms"] = now_ms

            elif action == "repeat":
                pb["repeat_mode"] = data.get("repeat_mode", "none")

            elif action == "shuffle":
                new_shuf = bool(data.get("shuffle", not pb.get("shuffle", False)))
                pb["shuffle"] = new_shuf
                if new_shuf and len(room["queue"]) > 1:
                    random.shuffle(room["queue"])

            elif action == "next":
                q = room.get("queue", [])
                if q:
                    next_track = q.pop(0)
                    _set_active_track(room, next_track, True, user.get("name", user_id), now_iso, now_ms)
                elif pb.get("repeat_mode") == "all" and room.get("recently_played"):
                    replay = room["recently_played"].pop(0)
                    _set_active_track(room, replay, True, user.get("name", user_id), now_iso, now_ms)

            elif action == "prev":
                rp = room.get("recently_played", [])
                if current_live_pos > 4.0 or not rp:
                    pb["position_seconds"] = 0.0
                    pb["anchor_timestamp_ms"] = now_ms
                else:
                    prev_track = rp.pop(0)
                    if pb.get("video_id"):
                        room["queue"].insert(0, {
                            "video_id": pb["video_id"],
                            "title": pb.get("title"),
                            "artist": pb.get("artist"),
                            "thumbnail": pb.get("thumbnail"),
                            "duration_seconds": pb.get("duration_seconds", 0),
                        })
                    _set_active_track(room, prev_track, True, user.get("name", user_id), now_iso, now_ms)

            elif action == "queue_add":
                track = data.get("track") or {}
                if track.get("video_id"):
                    room["queue"].append({
                        "video_id": track.get("video_id"),
                        "title": track.get("title", "Song"),
                        "artist": track.get("artist", "YouTube"),
                        "thumbnail": track.get("thumbnail") or f"https://img.youtube.com/vi/{track.get('video_id')}/hqdefault.jpg",
                        "duration_seconds": int(track.get("duration_seconds") or 0),
                        "added_by": user.get("name", "Partner"),
                    })

            elif action == "queue_play":
                idx = data.get("index")
                if isinstance(idx, int) and 0 <= idx < len(room["queue"]):
                    chosen = room["queue"].pop(idx)
                    _set_active_track(room, chosen, True, user.get("name", user_id), now_iso, now_ms)

            elif action == "queue_remove":
                idx = data.get("index")
                if isinstance(idx, int) and 0 <= idx < len(room["queue"]):
                    room["queue"].pop(idx)

            elif action == "queue_reorder":
                old_i = data.get("old_index")
                new_i = data.get("new_index")
                q = room["queue"]
                if isinstance(old_i, int) and isinstance(new_i, int) and 0 <= old_i < len(q) and 0 <= new_i < len(q):
                    item = q.pop(old_i)
                    q.insert(new_i, item)

            elif action == "queue_clear":
                room["queue"] = []

            elif action == "clear_recent":
                room["recently_played"] = []

            elif action == "delete_recent":
                vid = data.get("video_id")
                room["recently_played"] = [r for r in room.get("recently_played", []) if r.get("video_id") != vid]

            elif action == "sleep_timer_propose":
                mins = max(1, min(240, int(data.get("minutes", 30))))
                room["sleep_timer"] = {
                    "minutes": mins,
                    "proposed_by_id": user_id,
                    "proposed_by_name": user.get("name", "Partner"),
                    "status": "pending",
                    "expires_at_ms": None,
                }

            elif action == "sleep_timer_accept":
                st_t = room.get("sleep_timer")
                if st_t and st_t.get("status") == "pending" and st_t.get("proposed_by_id") != user_id:
                    mins = int(st_t.get("minutes", 30))
                    st_t["status"] = "active"
                    st_t["accepted_by"] = user.get("name", "Partner")
                    st_t["expires_at_ms"] = now_ms + mins * 60 * 1000

            elif action == "sleep_timer_cancel":
                room["sleep_timer"] = None

            pb["event_seq"] = int(pb.get("event_seq", 0)) + 1
            pb["updated_by"] = user.get("name", user_id)

            db_fresh["music_playback_events"].insert(0, {
                "id": f"mev_{now_ms}",
                "couple_id": couple_id,
                "user_id": user_id,
                "action": action,
                "video_id": pb.get("video_id"),
                "position": pb.get("position_seconds"),
                "seq": pb["event_seq"],
                "timestamp": now_iso,
            })
            db_fresh["music_playback_events"] = db_fresh["music_playback_events"][:200]
            save_db_fn(db_fresh)
            snap = compute_room_snapshot(room)
            broadcast_room_update(couple_id, snap)

        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "room": snap}).encode("utf-8"))
        return True

    if path == "/api/music/likes":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        op = data.get("operation", "like")  # like | unlike | toggle_consent
        ok, user, couple, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            likes = db_fresh["music_likes"].setdefault(user_id, [])
            if op == "like":
                track = data.get("track") or {}
                vid = track.get("video_id") or data.get("video_id")
                if vid and not any(t.get("video_id") == vid for t in likes):
                    likes.insert(0, {
                        "video_id": vid,
                        "title": track.get("title", "Song"),
                        "artist": track.get("artist", "YouTube"),
                        "thumbnail": track.get("thumbnail") or f"https://img.youtube.com/vi/{vid}/hqdefault.jpg",
                        "duration_seconds": int(track.get("duration_seconds") or 0),
                        "liked_at": now_iso,
                    })
            elif op == "unlike":
                vid = data.get("video_id") or (data.get("track") or {}).get("video_id")
                db_fresh["music_likes"][user_id] = [t for t in likes if t.get("video_id") != vid]
            elif op == "toggle_consent":
                db_fresh["music_like_consents"][user_id] = bool(data.get("consent", not db_fresh["music_like_consents"].get(user_id, False)))
            save_db_fn(db_fresh)
            res_payload = _compute_likes_payload(db_fresh, user, couple)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", **res_payload}).encode("utf-8"))
        return True

    if path == "/api/music/playlists":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        op = data.get("operation", "create")  # create | rename | delete | artwork
        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            if op == "create":
                name = sanitize_text(data.get("name"), 60)
                if not name:
                    handler._set_headers(400)
                    handler.wfile.write(json.dumps({"error": "Playlist name is required"}).encode("utf-8"))
                    return True
                new_pl = {
                    "id": f"pl_{now_ms}",
                    "couple_id": couple_id,
                    "name": name,
                    "artwork_emoji": (data.get("artwork_emoji") or "🎶")[:4],
                    "artwork_color": data.get("artwork_color") or "#6C3EBC",
                    "is_our_songs": False,
                    "created_by": user.get("name", user_id),
                    "created_at": now_iso,
                    "songs": [],
                }
                db_fresh["music_playlists"].append(new_pl)
                save_db_fn(db_fresh)
                handler._set_headers(201)
                handler.wfile.write(json.dumps({"status": "success", "playlist": new_pl}).encode("utf-8"))
                return True
            else:
                pl_id = data.get("playlist_id")
                pl = next((p for p in db_fresh["music_playlists"] if p.get("id") == pl_id and p.get("couple_id") == couple_id), None)
                if not pl:
                    handler._set_headers(404)
                    handler.wfile.write(json.dumps({"error": "Playlist not found"}).encode("utf-8"))
                    return True
                if op == "rename":
                    new_name = sanitize_text(data.get("name"), 60)
                    if new_name:
                        pl["name"] = new_name
                elif op == "artwork":
                    if data.get("artwork_emoji"):
                        pl["artwork_emoji"] = data["artwork_emoji"][:4]
                    if data.get("artwork_color"):
                        pl["artwork_color"] = data["artwork_color"]
                elif op == "delete" and not pl.get("is_our_songs"):
                    db_fresh["music_playlists"] = [p for p in db_fresh["music_playlists"] if p.get("id") != pl_id]
                save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))
        return True

    if path == "/api/music/playlists/song":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        playlist_id = data.get("playlist_id")
        operation = data.get("operation", "add")  # add | remove | toggle_our_song | reorder
        track = data.get("track") or {}
        vid = track.get("video_id") or data.get("video_id")

        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_default_playlists(db_fresh, couple_id, user_id, save_db_fn)
            pl = next((p for p in db_fresh["music_playlists"] if p.get("id") == playlist_id and p.get("couple_id") == couple_id), None)
            if not pl and playlist_id is None:
                pl = next((p for p in db_fresh["music_playlists"] if p.get("couple_id") == couple_id), None)
            if not pl:
                handler._set_headers(404)
                handler.wfile.write(json.dumps({"error": "Playlist not found"}).encode("utf-8"))
                return True

            songs = pl.setdefault("songs", [])
            if operation == "add" and vid:
                if not any(s.get("video_id") == vid for s in songs):
                    songs.append({
                        "video_id": vid,
                        "title": track.get("title", "Song"),
                        "artist": track.get("artist", "YouTube"),
                        "thumbnail": track.get("thumbnail") or f"https://img.youtube.com/vi/{vid}/hqdefault.jpg",
                        "duration_seconds": int(track.get("duration_seconds") or 0),
                        "added_by": user.get("name", "Partner"),
                        "is_our_song": bool(data.get("is_our_song", False)),
                        "added_at": now_iso,
                    })
            elif operation == "remove" and vid:
                pl["songs"] = [s for s in songs if s.get("video_id") != vid]
            elif operation == "toggle_our_song" and vid:
                for s in songs:
                    if s.get("video_id") == vid:
                        s["is_our_song"] = not bool(s.get("is_our_song", False))
            elif operation == "reorder":
                old_i, new_i = data.get("old_index"), data.get("new_index")
                if isinstance(old_i, int) and isinstance(new_i, int) and 0 <= old_i < len(songs) and 0 <= new_i < len(songs):
                    item = songs.pop(old_i)
                    songs.insert(new_i, item)
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "playlist": pl}).encode("utf-8"))
        return True

    if path == "/api/music/dedications":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        ok, user, couple, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        track = data.get("track") or {}
        if not track.get("video_id"):
            handler._set_headers(400)
            handler.wfile.write(json.dumps({"error": "track.video_id required"}).encode("utf-8"))
            return True
        msg = sanitize_text(data.get("message") or "This song reminded me of you 💖", 240)
        emoji = (data.get("emoji") or "💌")[:4]
        partner = get_partner_for_user(db, user, couple)
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            rec = {
                "id": f"ded_{now_ms}",
                "couple_id": couple_id,
                "sender_id": user_id,
                "sender_name": user.get("name", "Partner"),
                "recipient_id": partner.get("id") if partner else None,
                "track": track,
                "message": msg,
                "emoji": emoji,
                "created_at": now_iso,
            }
            db_fresh["music_dedications"].insert(0, rec)
            db_fresh["music_dedications"] = db_fresh["music_dedications"][:100]
            if partner and partner.get("id"):
                db_fresh.setdefault("notifications", []).insert(0, {
                    "id": f"notif_{now_ms}",
                    "user_id": partner["id"],
                    "title": f"{user.get('name', 'Partner')} dedicated a song to you {emoji}",
                    "body": f"{track.get('title', 'Song')} — \"{msg}\"",
                    "type": "music_dedication",
                    "deep_link": "/music",
                    "is_read": False,
                    "created_at": "Just now",
                })
            save_db_fn(db_fresh)
        handler._set_headers(201)
        handler.wfile.write(json.dumps({"status": "success", "dedication": rec}).encode("utf-8"))
        return True

    if path == "/api/music/memories":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        op = data.get("operation", "create")  # create | edit | delete
        ok, user, _, err = verify_couple_access(db, user_id, couple_id)
        if not ok:
            handler._set_headers(403)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            if op == "create":
                track = data.get("track") or {}
                rec = {
                    "id": f"mmem_{now_ms}",
                    "couple_id": couple_id,
                    "created_by": user_id,
                    "creator_name": user.get("name", "Partner"),
                    "track": track,
                    "title": sanitize_text(data.get("title") or track.get("title") or "Our Musical Memory", 100),
                    "note": sanitize_text(data.get("note") or "", 400),
                    "occasion": sanitize_text(data.get("occasion") or "Special Moment", 40),
                    "date": sanitize_text(data.get("date") or datetime.utcnow().strftime("%Y-%m-%d"), 20),
                    "created_at": now_iso,
                }
                db_fresh["music_memories"].insert(0, rec)
                save_db_fn(db_fresh)
                handler._set_headers(201)
                handler.wfile.write(json.dumps({"status": "success", "memory": rec}).encode("utf-8"))
                return True
            mem_id = data.get("memory_id")
            if op == "edit":
                for m in db_fresh["music_memories"]:
                    if m.get("id") == mem_id and m.get("couple_id") == couple_id:
                        if "title" in data:
                            m["title"] = sanitize_text(data["title"], 100)
                        if "note" in data:
                            m["note"] = sanitize_text(data["note"], 400)
                        if "occasion" in data:
                            m["occasion"] = sanitize_text(data["occasion"], 40)
            elif op == "delete":
                db_fresh["music_memories"] = [m for m in db_fresh["music_memories"] if not (m.get("id") == mem_id and m.get("couple_id") == couple_id)]
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success"}).encode("utf-8"))
        return True

    if path == "/api/music/report":
        couple_id = data.get("couple_id")
        user_id = data.get("user_id")
        video_id = data.get("video_id", "")
        title = sanitize_text(data.get("title", "Reported Song"), 120)
        reason = sanitize_text(data.get("reason", "Inappropriate or broken track"), 240)
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            rep = {
                "id": f"mrep_{now_ms}",
                "couple_id": couple_id,
                "reporter_id": user_id,
                "video_id": video_id,
                "title": title,
                "reason": reason,
                "status": "Pending Review",
                "created_at": now_iso,
            }
            db_fresh["music_reports"].insert(0, rep)
            save_db_fn(db_fresh)
        handler._set_headers(201)
        handler.wfile.write(json.dumps({"status": "success", "report": rep}).encode("utf-8"))
        return True

    if path == "/api/admin/music/config":
        admin, err = verify_admin_fn(handler, db)
        if not admin:
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            cfg = db_fresh["music_config"]
            if "enabled" in data:
                cfg["enabled"] = bool(data["enabled"])
            if "allow_together_mode" in data:
                cfg["allow_together_mode"] = bool(data["allow_together_mode"])
            if "daily_quota_limit" in data:
                cfg["daily_quota_limit"] = int(data["daily_quota_limit"])
            db_fresh.setdefault("audit_logs", []).insert(0, {
                "id": f"aud_{now_ms}",
                "admin": admin.get("email"),
                "action": "UPDATE_MUSIC_CONFIG",
                "details": f"Music enabled={cfg['enabled']}, together_mode={cfg['allow_together_mode']}",
                "timestamp": datetime.utcnow().strftime("%b %d, %Y - %H:%M UTC"),
            })
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "config": cfg}).encode("utf-8"))
        return True

    if path == "/api/admin/music/reports/resolve":
        admin, err = verify_admin_fn(handler, db)
        if not admin:
            handler._set_headers(401)
            handler.wfile.write(json.dumps({"error": err}).encode("utf-8"))
            return True
        rep_id = data.get("report_id")
        resolution = sanitize_text(data.get("resolution", "Resolved"), 80)
        with MUSIC_LOCK:
            db_fresh = load_db_fn()
            ensure_music_db(db_fresh)
            rep = next((r for r in db_fresh["music_reports"] if r.get("id") == rep_id), None)
            if not rep:
                handler._set_headers(404)
                handler.wfile.write(json.dumps({"error": "Report not found"}).encode("utf-8"))
                return True
            rep["status"] = f"Resolved: {resolution}"
            rep["resolved_by"] = admin.get("email")
            db_fresh.setdefault("audit_logs", []).insert(0, {
                "id": f"aud_{now_ms}",
                "admin": admin.get("email"),
                "action": "RESOLVE_MUSIC_REPORT",
                "details": f"Music report {rep_id} -> {resolution}",
                "timestamp": datetime.utcnow().strftime("%b %d, %Y - %H:%M UTC"),
            })
            save_db_fn(db_fresh)
        handler._set_headers(200)
        handler.wfile.write(json.dumps({"status": "success", "report": rep}).encode("utf-8"))
        return True

    return False
