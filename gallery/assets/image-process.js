// gallery/assets/image-process.js
//
// Client-side image processing on upload. Two goals:
//   1. Strip EXIF (GPS, device info) — Canvas re-encoding drops metadata.
//   2. Resize to MAX_DIMENSION on the longest edge — caps storage/bandwidth.
//
// PDFs and other non-image files pass through unchanged from the caller.

const MAX_DIMENSION = 2000;
const JPEG_QUALITY  = 0.88;

/**
 * Resize + EXIF-strip an image File. Returns a Blob ready for upload.
 * Caller decides whether to call this (only call for image/*).
 *
 * @param {File} file
 * @returns {Promise<Blob>}
 */
export async function processImage(file) {
  const img = await loadImage(file);

  let { width, height } = img;
  const longest = Math.max(width, height);
  if (longest > MAX_DIMENSION) {
    const scale = MAX_DIMENSION / longest;
    width  = Math.round(width  * scale);
    height = Math.round(height * scale);
  }

  const canvas = document.createElement('canvas');
  canvas.width  = width;
  canvas.height = height;
  const ctx = canvas.getContext('2d');
  ctx.drawImage(img, 0, 0, width, height);

  // PNG keeps transparency; everything else becomes JPEG.
  const outType = file.type === 'image/png' ? 'image/png' : 'image/jpeg';
  const quality = outType === 'image/jpeg' ? JPEG_QUALITY : undefined;

  return await new Promise((resolve, reject) => {
    canvas.toBlob(
      (blob) => (blob ? resolve(blob) : reject(new Error('toBlob failed'))),
      outType,
      quality,
    );
  });
}

function loadImage(file) {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload  = () => { URL.revokeObjectURL(url); resolve(img); };
    img.onerror = (e) => { URL.revokeObjectURL(url); reject(e); };
    img.src = url;
  });
}

export function pickExtension(file, processedMime) {
  if (processedMime === 'image/png')  return 'png';
  if (processedMime === 'image/jpeg') return 'jpg';
  // Fall back to whatever the original had.
  const parts = file.name.split('.');
  return parts.length > 1 ? parts.pop().toLowerCase() : 'bin';
}
