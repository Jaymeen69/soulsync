# SoulSync 💞

> Two Hearts. One Connection. Zero Distance.

SoulSync is a private relationship companion for couples — built with Flutter, Supabase, and love.

## Setup

1. Install Flutter SDK (https://flutter.dev)
2. Clone this repository
3. Copy `lib/core/supabase/supabase_config.example.dart` to `supabase_config.dart` and fill in your credentials
4. Add `google-services.json` to `android/app/`
5. Run `flutter pub get`
6. Run `flutter run`

## Architecture

- **State:** Riverpod
- **Navigation:** GoRouter
- **Backend:** Supabase (Auth, Database, Realtime, Storage)
- **Push:** Firebase Cloud Messaging

## Privacy

All couple data is isolated using Supabase Row Level Security (RLS). 
No secrets are stored in the mobile app.
