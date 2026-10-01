/**
 * Public client configuration for Expo.
 *
 * Values are intentionally read from EXPO_PUBLIC_* variables. Never put a
 * Supabase service-role/secret key in an Expo public environment variable.
 */
export function getSupabasePublicConfig() {
  const url = process.env.EXPO_PUBLIC_SUPABASE_URL?.trim();
  const key = (process.env.EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.EXPO_PUBLIC_SUPABASE_ANON_KEY)?.trim();

  if (!url || !key || url.includes("YOUR_PROJECT") || key === "YOUR_PUBLISHABLE_KEY") {
    return { configured: false as const };
  }

  try {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.hostname !== "localhost") {
      return { configured: false as const };
    }
  } catch {
    return { configured: false as const };
  }

  return { configured: true as const, url, anonKey: key };
}
