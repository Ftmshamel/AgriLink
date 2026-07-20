// Single import point for the AgriLink data layer.
//
// At runtime we pick exactly one backend:
//
//   - `firestoreDb` when the user has filled in their Firebase credentials
//     (see `frontend/.env`).  Reads come from an in-memory cache populated
//     by Firestore `onSnapshot` listeners; writes go straight to Firestore.
//
//   - `mockDb` otherwise — a localStorage-backed implementation for local
//     development and offline-friendly usage.
//
// Both backends expose an *identical* API.  Mutating methods are async on
// both so call sites are interchangeable.

import { isFirebaseConfigured } from "./firebase";
import { mockDb } from "./mockDb";
import { firestoreDb } from "./firestoreDb";

export const db = isFirebaseConfigured ? firestoreDb : mockDb;

// Keep a debug handle around in dev tools.
if (typeof window !== "undefined") {
  window.__agrilinkDb = db;
}
