# KickOff — Android app

KickOff is being migrated from the web prototype to a native Android app using **React Native + Expo**.

## Current demo

- Explore seeded games, search and filter by sport.
- Join/leave games and create a local demo game.
- My Games and Profile placeholder screens.
- Demo data persists on this device with AsyncStorage.

The current UI is a local prototype. It does **not** yet provide accounts, shared game data, real location search, realtime chat, notifications, or production capacity enforcement.

## Run locally

```bash
npm install
npx expo start
```

Press `a` to open an Android emulator, or scan the QR code with Expo Go where supported.

## Supabase foundation

The initial schema is in `supabase/migrations/20261001000100_initial_schema.sql`. It defines profiles, games, memberships, messages, row-level security, and capacity-aware join/leave functions with a waitlist.

Review the migration and apply it to the intended Supabase project before connecting the app. No Supabase project has been configured or migrated by this repository change.

## Next implementation steps

1. Apply and test the Supabase migration in the intended project.
2. Add Supabase client configuration and authentication.
3. Replace local demo data with shared games and server-side join/leave.
4. Add game details, chat, location, and push notifications.
5. Add tests, privacy/terms, moderation, and Android release signing.
