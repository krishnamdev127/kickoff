import "react-native-url-polyfill/auto";
import AsyncStorage from "@react-native-async-storage/async-storage";
import { createClient } from "@supabase/supabase-js";
import { getSupabasePublicConfig } from "./supabase-config";

const config = getSupabasePublicConfig();

/**
 * Null when no public project configuration is supplied.
 * Use only the publishable/anon key here—never a service-role secret.
 */
export const supabase = config.configured
  ? createClient(config.url, config.anonKey, {
      auth: {
        storage: AsyncStorage,
        autoRefreshToken: true,
        persistSession: true,
        detectSessionInUrl: false,
      },
    })
  : null;
