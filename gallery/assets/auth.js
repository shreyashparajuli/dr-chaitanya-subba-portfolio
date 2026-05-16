// gallery/assets/auth.js
//
// Thin wrappers over Supabase Auth plus a route guard that reads profiles.status.
// The guard is UX only — RLS on the server is the actual lock.

import { supabase } from './supabase-client.js';

export async function getSession() {
  const { data: { session } } = await supabase.auth.getSession();
  return session;
}

export async function getProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await supabase
    .from('profiles')
    .select('id, email, full_name, status')
    .eq('id', session.user.id)
    .single();
  if (error) {
    console.warn('getProfile error:', error);
    return null;
  }
  return data;
}

export async function signUp({ email, password, fullName }) {
  return supabase.auth.signUp({
    email,
    password,
    options: {
      data: { full_name: fullName },
      emailRedirectTo: new URL('login.html', location.href).toString(),
    },
  });
}

export async function signIn({ email, password }) {
  return supabase.auth.signInWithPassword({ email, password });
}

export async function signOut() {
  return supabase.auth.signOut();
}

export async function sendPasswordReset(email) {
  return supabase.auth.resetPasswordForEmail(email, {
    redirectTo: new URL('login.html', location.href).toString(),
  });
}

/**
 * Page guard. Use on any gallery page that requires an approved profile.
 *   - no session       → redirect to login.html
 *   - status=pending   → redirect to pending.html
 *   - status=disabled  → sign out + redirect to login.html
 *   - status=approved or admin → return the profile
 *
 * @returns {Promise<object|null>} profile if allowed, else null (a redirect is in flight).
 */
export async function requireApproved({
  loginUrl   = 'login.html',
  pendingUrl = 'pending.html',
} = {}) {
  const profile = await getProfile();

  if (!profile) {
    location.replace(loginUrl);
    return null;
  }
  if (profile.status === 'pending') {
    if (!location.pathname.endsWith('pending.html')) location.replace(pendingUrl);
    return null;
  }
  if (profile.status === 'disabled') {
    await signOut();
    location.replace(loginUrl);
    return null;
  }
  return profile; // approved or admin
}
