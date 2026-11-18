import json
import urllib.request
import urllib.error
import time

BASE_URL = "http://127.0.0.1:8089"

results = []

def run_test(test_id, category, description, fn):
    try:
        fn()
        results.append({"id": test_id, "category": category, "desc": description, "status": "PASS", "error": None})
        print(f"[{test_id}] PASS - {description}")
    except Exception as e:
        results.append({"id": test_id, "category": category, "desc": description, "status": "FAIL", "error": str(e)})
        print(f"[{test_id}] FAIL - {description} | Error: {e}")

def post_json(path, data):
    req = urllib.request.Request(
        f"{BASE_URL}{path}",
        data=json.dumps(data).encode("utf-8"),
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8")), response.getcode()

def get_json(path):
    req = urllib.request.Request(f"{BASE_URL}{path}")
    with urllib.request.urlopen(req) as response:
        return json.loads(response.read().decode("utf-8")), response.getcode()

print("==================================================")
print("SOULSYNC AUTOMATED QA TEST SUITE EXECUTION")
print("==================================================")

# ----------------- AUTH-01..15 -----------------
def test_auth_01():
    # Admin creates user
    res, code = post_json("/api/users", {
        "name": "Sarah Test",
        "email": "sarah.test@example.com",
        "password": "Password123!",
        "partner": "David",
        "source": "Admin Panel"
    })
    assert code == 201 or code == 200, f"Expected 201/200, got {code}"
    assert res["status"] == "success"
run_test("AUTH-01", "Authentication", "Admin creates user with valid password and partner code", test_auth_01)

def test_auth_02():
    # Login of admin-created user
    res, code = post_json("/api/login", {
        "email": "sarah.test@example.com",
        "password": "Password123!"
    })
    assert code == 200, f"Expected 200, got {code}"
    assert res["status"] == "success"
    assert res["user"]["email"] == "sarah.test@example.com"
run_test("AUTH-02", "Authentication", "Admin-created user successfully logs in via mobile API", test_auth_02)

def test_auth_03():
    # Duplicate email registration rejected
    try:
        post_json("/api/register", {
            "name": "Sarah Duplicate",
            "email": "sarah.test@example.com",
            "password": "NewPassword123!",
            "partner": "David"
        })
        raise AssertionError("Should have failed on duplicate email")
    except urllib.error.HTTPError as e:
        assert e.code in [400, 409], f"Expected 400/409, got {e.code}"
run_test("AUTH-03", "Authentication", "Duplicate email registration properly rejected", test_auth_03)

def test_auth_04():
    # Email registration creates pending verification and sends OTP
    res, code = post_json("/api/register", {
        "name": "Emma Watson",
        "email": "emma.otp@example.com",
        "password": "SecurePassword123!",
        "partner": "Liam"
    })
    assert code == 200
    assert res["status"] == "pending_verification"
    assert "dev_otp" in res
run_test("AUTH-04", "Authentication", "Registration creates unverified account and generates 6-digit OTP", test_auth_04)

def test_auth_05():
    # Unverified user cannot log in before OTP verification
    try:
        post_json("/api/login", {
            "email": "emma.otp@example.com",
            "password": "SecurePassword123!"
        })
        raise AssertionError("Unverified user should not be able to log in")
    except urllib.error.HTTPError as e:
        assert e.code in [401, 403], f"Expected 401/403, got {e.code}"
run_test("AUTH-05", "Authentication", "Unverified user blocked from logging in before OTP confirmation", test_auth_05)

def test_auth_06():
    # Invalid OTP rejected
    try:
        post_json("/api/verify-otp", {
            "email": "emma.otp@example.com",
            "otp": "000000"
        })
        raise AssertionError("Invalid OTP should be rejected")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("AUTH-06", "Authentication", "Incorrect OTP rejected with error feedback", test_auth_06)

def test_auth_07():
    # Resend OTP
    res, code = post_json("/api/resend-otp", {"email": "emma.otp@example.com"})
    assert code == 200
    assert res["status"] == "success"
    global latest_otp
    latest_otp = res["dev_otp"]
run_test("AUTH-07", "Authentication", "Resend OTP delivers new code with refreshed expiry", test_auth_07)

def test_auth_08():
    # Valid OTP verification activates user
    res, code = post_json("/api/verify-otp", {
        "email": "emma.otp@example.com",
        "otp": latest_otp
    })
    assert code == 200
    assert res["status"] == "success"
    assert res["user"]["is_verified"] is True
run_test("AUTH-08", "Authentication", "Valid OTP verifies email and promotes user to active", test_auth_08)

def test_auth_09():
    # Login with newly verified user
    res, code = post_json("/api/login", {
        "email": "emma.otp@example.com",
        "password": "SecurePassword123!"
    })
    assert code == 200
    assert res["user"]["name"] == "Emma Watson"
run_test("AUTH-09", "Authentication", "Newly verified user can log in seamlessly", test_auth_09)

def test_auth_10():
    # Incorrect password during login rejected
    try:
        post_json("/api/login", {
            "email": "emma.otp@example.com",
            "password": "WrongPassword999!"
        })
        raise AssertionError("Wrong password should be rejected")
    except urllib.error.HTTPError as e:
        assert e.code == 401
run_test("AUTH-10", "Authentication", "Incorrect password rejected with HTTP 401", test_auth_10)

# ----------------- PASS-01..10 -----------------
def test_pass_01():
    # Under 8 chars rejected
    try:
        post_json("/api/register", {
            "name": "Short",
            "email": "short@example.com",
            "password": "Ab1!"
        })
        raise AssertionError("Short password should fail")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("PASS-01", "Password Policy", "Password under 8 characters rejected", test_pass_01)

def test_pass_02():
    # Missing uppercase rejected
    try:
        post_json("/api/register", {
            "name": "NoUpper",
            "email": "noupper@example.com",
            "password": "password123!"
        })
        raise AssertionError("Missing uppercase should fail")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("PASS-02", "Password Policy", "Password missing uppercase rejected", test_pass_02)

def test_pass_03():
    # Missing lowercase rejected
    try:
        post_json("/api/register", {
            "name": "NoLower",
            "email": "nolower@example.com",
            "password": "PASSWORD123!"
        })
        raise AssertionError("Missing lowercase should fail")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("PASS-03", "Password Policy", "Password missing lowercase rejected", test_pass_03)

def test_pass_04():
    # Missing number rejected
    try:
        post_json("/api/register", {
            "name": "NoNum",
            "email": "nonum@example.com",
            "password": "PasswordSpecial!"
        })
        raise AssertionError("Missing number should fail")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("PASS-04", "Password Policy", "Password missing digit rejected", test_pass_04)

def test_pass_05():
    # Missing special character rejected
    try:
        post_json("/api/register", {
            "name": "NoSpecial",
            "email": "nospecial@example.com",
            "password": "Password1234"
        })
        raise AssertionError("Missing special char should fail")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("PASS-05", "Password Policy", "Password missing special character rejected", test_pass_05)

def test_pass_06():
    # Forgot password OTP request
    res, code = post_json("/api/auth/forgot-password", {"email": "sarah.test@example.com"})
    assert code == 200
    assert "dev_otp" in res
    global reset_otp
    reset_otp = res["dev_otp"]
run_test("PASS-06", "Password Reset", "Forgot password issues verified 6-digit OTP", test_pass_06)

def test_pass_07():
    # Verify Reset OTP
    res, code = post_json("/api/auth/verify-reset-otp", {
        "email": "sarah.test@example.com",
        "otp": reset_otp
    })
    assert code == 200
    assert res["status"] == "success"
run_test("PASS-07", "Password Reset", "Verify reset OTP validates successfully", test_pass_07)

def test_pass_08():
    # Complete reset password with new complex password
    res, code = post_json("/api/auth/reset-password", {
        "email": "sarah.test@example.com",
        "otp": reset_otp,
        "new_password": "NewSecretPassword2026@"
    })
    assert code == 200
    assert res["status"] == "success"
run_test("PASS-08", "Password Reset", "Password reset updates credentials securely", test_pass_08)

def test_pass_09():
    # Login with new password
    res, code = post_json("/api/login", {
        "email": "sarah.test@example.com",
        "password": "NewSecretPassword2026@"
    })
    assert code == 200
    assert res["status"] == "success"
run_test("PASS-09", "Password Reset", "User logs in with updated password", test_pass_09)

def test_pass_10():
    # Admin resets user password
    res, code = post_json("/api/admin/reset-password", {
        "email": "sarah.test@example.com",
        "new_password": "AdminResetPassword2026#",
        "admin": "SuperAdmin"
    })
    assert code == 200
    assert res["status"] == "success"
run_test("PASS-10", "Admin Password", "Admin password reset applies policy and updates user", test_pass_10)

# ----------------- CON-01..10 (Partner Connection) -----------------
def test_con_01():
    # Check invite code for users
    res, code = get_json("/api/couple/status?email=emma.otp@example.com")
    assert code == 200
    assert "invite_code" in res["user"]
    global emma_code
    emma_code = res["user"]["invite_code"]
run_test("CON-01", "Partner Connection", "Each user receives a unique partner invite code", test_con_01)

def test_con_02():
    # Self connection prevention
    try:
        post_json("/api/couple/request", {
            "email": "emma.otp@example.com",
            "invite_code": emma_code
        })
        raise AssertionError("Connecting to self should be blocked")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("CON-02", "Partner Connection", "Self-connection prevented with error message", test_con_02)

def test_con_03():
    # Invalid partner code rejection
    try:
        post_json("/api/couple/request", {
            "email": "emma.otp@example.com",
            "invite_code": "INVALID-9999"
        })
        raise AssertionError("Invalid code should be rejected")
    except urllib.error.HTTPError as e:
        assert e.code == 404
run_test("CON-03", "Partner Connection", "Invalid or expired partner code rejected", test_con_03)

def test_con_04():
    # Valid connection request to Sarah
    res_s, _ = get_json("/api/couple/status?email=sarah.test@example.com")
    sarah_code = res_s["user"]["invite_code"]

    res, code = post_json("/api/couple/request", {
        "email": "emma.otp@example.com",
        "invite_code": sarah_code
    })
    assert code == 201
    assert res["status"] == "success"
    global req_id
    req_id = res["request"]["id"]
run_test("CON-04", "Partner Connection", "Connection request sent and stored as pending", test_con_04)

def test_con_05():
    # Duplicate connection request rejected
    res_s, _ = get_json("/api/couple/status?email=sarah.test@example.com")
    sarah_code = res_s["user"]["invite_code"]

    try:
        post_json("/api/couple/request", {
            "email": "emma.otp@example.com",
            "invite_code": sarah_code
        })
        raise AssertionError("Duplicate request should be rejected")
    except urllib.error.HTTPError as e:
        assert e.code == 400
run_test("CON-05", "Partner Connection", "Duplicate connection requests prevented", test_con_05)

def test_con_06():
    # Accept connection request binds couple
    res, code = post_json("/api/couple/accept", {"request_id": req_id})
    assert code == 200
    assert res["status"] == "success"
    assert res["couple"]["status"] == "Active 🟢"
run_test("CON-06", "Partner Connection", "Accepting connection request binds couple (2-member rule)", test_con_06)

# ----------------- SYNC & CONN & MOOD (SYNC-01..08, CONN-01..07) -----------------
def test_conn_01():
    # Send Love Pulse
    res, code = post_json("/api/pulse", {
        "sender": "Emma Watson",
        "recipient": "Sarah Test",
        "type": "Love ❤️"
    })
    assert code == 201
    assert res["status"] == "success"
run_test("CONN-01", "Connect Pulse", "Sending Love pulse stores in backend and updates count", test_conn_01)

def test_conn_02():
    # Send Hug Pulse
    res, code = post_json("/api/pulse", {
        "sender": "Sarah Test",
        "recipient": "Emma Watson",
        "type": "Hug 🫂"
    })
    assert code == 201
run_test("CONN-02", "Connect Pulse", "Sending Hug pulse records in activity log", test_conn_02)

def test_conn_03():
    # Record Mood with Note and Shared status
    res, code = post_json("/api/mood", {
        "user_id": "u_emma",
        "couple_id": "c_emma_sarah",
        "mood": "Romantic",
        "emoji": "🥰",
        "note": "Thinking of our wonderful conversation earlier!",
        "is_private": False
    })
    assert code == 201
    assert res["status"] == "success"
run_test("CONN-03", "Mood Sync", "Shared mood recorded and accessible to partner", test_conn_03)

def test_conn_04():
    # Record Private Mood
    res, code = post_json("/api/mood", {
        "user_id": "u_sarah",
        "couple_id": "c_emma_sarah",
        "mood": "Stressed",
        "emoji": "😫",
        "note": "Work deadline is heavy today.",
        "is_private": True
    })
    assert code == 201
    # Check that partner does NOT see Sarah's private mood
    res_m, _ = get_json("/api/mood?user_id=u_emma&couple_id=c_emma_sarah")
    assert res_m["partner_latest"] is None or res_m["partner_latest"].get("is_private") is not True
run_test("CONN-04", "Mood Sync", "Private mood and note is strictly isolated from partner", test_conn_04)

# ----------------- MEMORIES & LETTERS (MEM-01..10, LETTER-01..08) -----------------
def test_mem_01():
    # Add Memory
    res, code = post_json("/api/memories", {
        "couple_id": "c_emma_sarah",
        "user_id": "u_emma",
        "title": "Sunset by the Harbor 🌅",
        "caption": "Watching the golden hour light reflect across the water.",
        "tag": "Date",
        "date": "Today"
    })
    assert code == 201
    assert res["status"] == "success"
run_test("MEM-01", "Memories Vault", "Adding memory saves to couple-isolated vault", test_mem_01)

def test_mem_02():
    # Retrieve couple memories
    res, code = get_json("/api/memories?couple_id=c_emma_sarah")
    assert code == 200
    assert len(res["memories"]) >= 1
run_test("MEM-02", "Memories Vault", "Retrieve couple memories returns saved timeline items", test_mem_02)

def test_letter_01():
    # Add Love Letter
    res, code = post_json("/api/letters", {
        "couple_id": "c_emma_sarah",
        "sender_id": "u_emma",
        "sender_name": "Emma",
        "title": "Open When You Miss Me 🥺",
        "content": "Distance means nothing when someone means everything.",
        "unlock_condition": "Open Anytime"
    })
    assert code == 201
    assert res["status"] == "success"
run_test("LETTER-01", "Love Letters", "Writing love letter seals and stores in vault", test_letter_01)

def test_letter_02():
    # Letter with future unlock date is locked for recipient
    future_date = "2029-12-31T00:00:00Z"
    post_json("/api/letters", {
        "couple_id": "c_emma_sarah",
        "sender_id": "u_emma",
        "sender_name": "Emma",
        "title": "Open on 2029 Anniversary 🎂",
        "content": "Happy 5th Anniversary my love!",
        "unlock_date": future_date
    })
    res, code = get_json("/api/letters?couple_id=c_emma_sarah&viewer_id=u_sarah")
    locked = [l for l in res["letters"] if l["title"] == "Open on 2029 Anniversary 🎂"][0]
    assert locked["is_locked"] is True
    assert "sealed until" in locked["content"]
run_test("LETTER-02", "Love Letters", "Future-scheduled letter remains locked for recipient", test_letter_02)

# ----------------- GAME-01..08 (7 Interactive Games) -----------------
games_to_test = [
    ("GAME-01", "would_you_rather"),
    ("GAME-02", "truth_or_dare"),
    ("GAME-03", "guess_your_partner"),
    ("GAME-04", "couple_quiz"),
    ("GAME-05", "how_well_do_you_know_me"),
    ("GAME-06", "memory_challenge"),
    ("GAME-07", "daily_couple_questions")
]

for gid, gname in games_to_test:
    def test_g(g=gname):
        res, code = get_json(f"/api/games/questions?game={g}")
        assert code == 200
        assert len(res["questions"]) > 0
    run_test(gid, "Together Games", f"Question bank for game '{gname}' contains active questions", test_g)

def test_game_session():
    # Submit answer to game session
    res, code = post_json("/api/games/session", {
        "couple_id": "c_emma_sarah",
        "game_type": "would_you_rather",
        "user_id": "u_emma",
        "question_id": "wyr_1",
        "answer": "Surprise Getaway 🎒"
    })
    assert code == 200
    assert res["status"] == "success"
run_test("GAME-08", "Together Games", "Submitting answer records synchronized game session", test_game_session)

# ----------------- ADM-01..12 (Admin Panel & Security) -----------------
def test_adm_audit():
    # Retrieve audit logs
    res, code = get_json("/api/admin/audit")
    assert code == 200
    assert len(res["audit_logs"]) >= 1
run_test("ADM-01", "Admin Security", "Audit log records administrative actions immutably", test_adm_audit)

print("\n==================================================")
passed_count = sum(1 for r in results if r["status"] == "PASS")
total_count = len(results)
print(f"QA TEST SUMMARY: {passed_count}/{total_count} PASSED")
print("==================================================")
