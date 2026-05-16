// gallery/assets/gallery.js
//
// Gallery CRUD: list (with category filter), upload (with image processing),
// soft-delete (update setting deleted_at), get signed display URL.

import { supabase, CATEGORIES } from './supabase-client.js';
import { processImage, pickExtension } from './image-process.js';

const BUCKET = 'gallery';
const SIGNED_URL_TTL_SECONDS = 60 * 60; // 1 hour

const MAX_PHOTO_BYTES    = 10 * 1024 * 1024; // 10 MB before processing
const MAX_DOCUMENT_BYTES = 20 * 1024 * 1024; // 20 MB

export { CATEGORIES };

/**
 * Fetch non-deleted gallery items, optionally filtered by category.
 * Returns rows ordered newest first.
 */
export async function listItems({ category } = {}) {
  let query = supabase
    .from('gallery_items')
    .select('id, uploader_id, title, caption, storage_path, media_type, category, taken_on, created_at')
    .is('deleted_at', null)
    .order('created_at', { ascending: false });

  if (category && category !== 'all') {
    query = query.eq('category', category);
  }

  const { data, error } = await query;
  if (error) throw error;
  return data ?? [];
}

/**
 * Generate a short-lived signed URL for a storage path. Bucket is private,
 * so this is how items get displayed in the UI.
 */
export async function getSignedUrl(storagePath, expiresIn = SIGNED_URL_TTL_SECONDS) {
  const { data, error } = await supabase
    .storage
    .from(BUCKET)
    .createSignedUrl(storagePath, expiresIn);
  if (error) throw error;
  return data.signedUrl;
}

/**
 * Upload a file (+ metadata). For images, runs EXIF strip + resize first.
 * Throws on validation failures so the UI can show inline errors.
 */
export async function uploadItem({
  file,
  title,
  caption,
  category,
  takenOn,
  userId,
}) {
  if (!file)     throw new Error('No file selected.');
  if (!title)    throw new Error('Title is required.');
  if (!category) throw new Error('Category is required.');
  if (!userId)   throw new Error('Not signed in.');

  const isImage = file.type.startsWith('image/');
  const isPdf   = file.type === 'application/pdf';
  if (!isImage && !isPdf) {
    throw new Error('Only images and PDFs are allowed.');
  }

  if (isImage    && file.size > MAX_PHOTO_BYTES)    throw new Error('Image is too large (max 10 MB).');
  if (!isImage   && file.size > MAX_DOCUMENT_BYTES) throw new Error('Document is too large (max 20 MB).');

  // Process images; pass through documents untouched.
  let blobToUpload  = file;
  let uploadType    = file.type;
  if (isImage) {
    blobToUpload = await processImage(file);
    uploadType   = blobToUpload.type;
  }

  const mediaType = isImage ? 'photo' : 'document';
  const ext       = pickExtension(file, uploadType);
  const storagePath = `${userId}/${crypto.randomUUID()}.${ext}`;

  // 1. Upload bytes
  const { error: uploadErr } = await supabase
    .storage
    .from(BUCKET)
    .upload(storagePath, blobToUpload, {
      contentType: uploadType,
      cacheControl: '3600',
      upsert: false,
    });
  if (uploadErr) throw uploadErr;

  // 2. Insert metadata row
  const { data, error: insertErr } = await supabase
    .from('gallery_items')
    .insert({
      uploader_id:  userId,
      title:        title.trim(),
      caption:      caption?.trim() || null,
      category,
      media_type:   mediaType,
      storage_path: storagePath,
      taken_on:     takenOn || null,
    })
    .select()
    .single();

  if (insertErr) {
    // Best-effort cleanup if metadata write fails
    await supabase.storage.from(BUCKET).remove([storagePath]).catch(() => {});
    throw insertErr;
  }
  return data;
}

/**
 * Soft delete: sets deleted_at + deleted_by. Item disappears from feeds but
 * remains in storage; admin can restore via the Supabase dashboard.
 */
export async function softDelete({ itemId, userId }) {
  const { error } = await supabase
    .from('gallery_items')
    .update({
      deleted_at: new Date().toISOString(),
      deleted_by: userId,
    })
    .eq('id', itemId);
  if (error) throw error;
}

/**
 * Edit your own title/caption/category/taken_on.
 */
export async function updateItem({ itemId, patch }) {
  const allowed = {};
  for (const key of ['title','caption','category','taken_on']) {
    if (key in patch) allowed[key] = patch[key];
  }
  const { data, error } = await supabase
    .from('gallery_items')
    .update(allowed)
    .eq('id', itemId)
    .select()
    .single();
  if (error) throw error;
  return data;
}
