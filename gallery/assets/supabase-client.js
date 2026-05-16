// gallery/assets/supabase-client.js
//
// Public credentials. The anon key is safe to commit — security is enforced by
// Row-Level Security on the Supabase side, not by hiding this string.
//
// Replace the two placeholders with the values from Supabase → Project Settings → API.

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.0/+esm';

const SUPABASE_URL      = 'https://xmbdebavogezqhtkjnbm.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_RTQRQ6935sSVGr3CdBp9Sw_qY_UJi1J';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export const CATEGORIES = [
  { value: 'family',       label: 'Family & Personal' },
  { value: 'awards',       label: 'Awards & Recognition' },
  { value: 'publications', label: 'Publications & Manuscripts' },
  { value: 'documents',    label: 'Documents & Letters' },
  { value: 'other',        label: 'Other' },
];
