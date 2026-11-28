# SoulSync Production Backend Deployment Guide (Free Hosting)

## Architecture
- **Admin Panel (`soulsync_admin`)**: Static site + Vercel mailer bridge deployed on Vercel (`https://soulsync-admin.vercel.app`).
- **Backend API (`soulsync/server/server.py`)**: Long-running Python `ThreadingHTTPServer` supporting REST APIs, real-time SSE streams (`/api/music/room/stream`, `/api/safety/stream`), and Gmail SMTP OTP delivery.
- **Why a dedicated Web Service is required**: Vercel Serverless Functions cannot host persistent SSE streams or stateful `database.json` writes. **Render (Free Web Service)** natively supports Python, HTTPS, SSE, and `$PORT` binding at zero cost.

## Step-by-Step Deployment on Render (Free Tier)
1. Sign in to [https://render.com](https://render.com) with your GitHub account (`Jaymeen69`).
2. Click **New +** -> **Blueprint** (or **Web Service**) and select repository `Jaymeen69/soulsync`.
3. If using Blueprint, Render automatically detects `render.yaml` (`rootDir: server`, `startCommand: python3 server.py`, `healthCheckPath: /health`).
4. In Render **Environment Variables**, add the secret values:
   - `SMTP_PASS`: Your existing Google App Password
   - `YOUTUBE_API_KEY`: Your existing YouTube Data API v3 key
   - (Optional fallback) `SOULSYNC_VERCEL_MAILER_URL` & `SOULSYNC_MAILER_KEY`
5. Deploy and verify `https://<your-render-service>.onrender.com/health` returns `{"status": "ok"}`.
6. Build the production Android APK with your live HTTPS backend URL:
   ```bash
   ./scripts/validate_prod_build.sh
   flutter build apk --release --dart-define=APP_ENV=production --dart-define=API_BASE_URL=https://<your-render-service>.onrender.com
   ```

## Free Tier Limitations
- Render Free Web Services spin down after 15 minutes of inactivity (~30–50s cold start on first request).
- Free tier local disk (`database.json`) is ephemeral across redeploys/restarts; for permanent multi-month persistence, attach a persistent disk or migrate storage to Supabase/Postgres.
