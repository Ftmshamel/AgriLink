// Image storage abstraction.
//
// In production (Firebase configured) we upload to Firebase Storage and store
// the resulting download URL on the document.  In demo mode (no Firebase) we
// downsize the image to a JPEG data-URL and store that directly on the
// document so it round-trips through localStorage without extra moving parts.

import { isFirebaseConfigured, app } from "./firebase";
import { getStorage, ref, uploadBytes, getDownloadURL, deleteObject } from "firebase/storage";

const MAX_DIMENSION = 1280;
const DATA_URL_QUALITY = 0.82;
const UPLOAD_TIMEOUT_MS = 20000;

let storage = null;
if (isFirebaseConfigured && app) {
  storage = getStorage(app);
}

/** Resize + compress a File client-side before upload. Returns a Blob. */
async function resizeImage(file, { maxDim = MAX_DIMENSION, quality = DATA_URL_QUALITY } = {}) {
  if (!file.type.startsWith("image/")) return file;

  const dataUrl = await new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });

  const img = await new Promise((resolve, reject) => {
    const i = new Image();
    i.onload = () => resolve(i);
    i.onerror = reject;
    i.src = dataUrl;
  });

  let { width, height } = img;
  if (width > maxDim || height > maxDim) {
    if (width > height) {
      height = Math.round(height * (maxDim / width));
      width = maxDim;
    } else {
      width = Math.round(width * (maxDim / height));
      height = maxDim;
    }
  }

  const canvas = document.createElement("canvas");
  canvas.width = width;
  canvas.height = height;
  const ctx = canvas.getContext("2d");
  ctx.drawImage(img, 0, 0, width, height);

  const blob = await new Promise((resolve) =>
    canvas.toBlob(resolve, "image/jpeg", quality)
  );
  return blob || file;
}

async function blobToDataUrl(blob) {
  return new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(r.result);
    r.onerror = reject;
    r.readAsDataURL(blob);
  });
}

function withTimeout(promise, ms, label = "operation") {
  let timer = null;
  return Promise.race([
    promise.finally(() => {
      if (timer) clearTimeout(timer);
    }),
    new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error(`${label} timed out`)), ms);
    }),
  ]);
}

/**
 * Upload a File to a logical "folder" (e.g. `farms`, `crops`, `users`).
 * Returns an object the rest of the app can store directly on a document:
 *
 *   { url, path, kind: 'firebase' | 'data-url' }
 */
export async function uploadImage(file, folder = "uploads", options = {}) {
  if (!file) return null;
  const blob = await resizeImage(file, {
    maxDim: options.maxDim ?? MAX_DIMENSION,
    quality: options.quality ?? DATA_URL_QUALITY,
  });

  if (storage) {
    try {
      const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, "_");
      const path = `${folder}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}-${safeName}`;
      const r = ref(storage, path);
      await withTimeout(
        uploadBytes(r, blob, { contentType: blob.type || "image/jpeg" }),
        UPLOAD_TIMEOUT_MS,
        "Firebase upload",
      );
      const url = await withTimeout(getDownloadURL(r), 10000, "Download URL fetch");
      return { url, path, kind: "firebase" };
    } catch (err) {
      // Keep UX responsive even if Storage is misconfigured/slow.
      console.warn("[AgriLink] Firebase Storage upload failed, using local data-url fallback.", err);
    }
  }

  // Local fallback: just stash the data URL on the document.
  const url = await blobToDataUrl(blob);
  return { url, path: null, kind: "data-url" };
}

/** Best-effort delete. No-op in demo mode (data URL is just text). */
export async function deleteImage(stored) {
  if (!stored || !stored.path || stored.kind !== "firebase" || !storage) return;
  try {
    await deleteObject(ref(storage, stored.path));
  } catch {
    /* ignore */
  }
}
