// Firebase initialization with graceful fallback.
//
// When real Firebase credentials are present in frontend/.env (VITE_FIREBASE_*),
// this module initializes Firebase Auth + Firestore.
// Otherwise it exports `null` clients so the rest of the app can run in
// "demo mode" against a local mock backend (see services/mockDb.js).

import { initializeApp, getApps } from "firebase/app";
import { getAuth } from "firebase/auth";
import { getFirestore } from "firebase/firestore";

const config = {
  apiKey:            import.meta.env.VITE_FIREBASE_API_KEY,
  authDomain:        import.meta.env.VITE_FIREBASE_AUTH_DOMAIN,
  projectId:         import.meta.env.VITE_FIREBASE_PROJECT_ID,
  storageBucket:     import.meta.env.VITE_FIREBASE_STORAGE_BUCKET,
  messagingSenderId: import.meta.env.VITE_FIREBASE_MSG_SENDER_ID,
  appId:             import.meta.env.VITE_FIREBASE_APP_ID,
};

export const isFirebaseConfigured = Boolean(config.apiKey && config.projectId);

let app = null;
let auth = null;
let db = null;

if (isFirebaseConfigured) {
  app = getApps().length ? getApps()[0] : initializeApp(config);
  auth = getAuth(app);
  db = getFirestore(app);
} else if (typeof window !== "undefined") {
  console.info(
    "[AgriLink] Firebase not configured — running in demo mode with localStorage. " +
      "Set VITE_FIREBASE_* in frontend/.env to enable cloud sync."
  );
}

export { app, auth, db };
