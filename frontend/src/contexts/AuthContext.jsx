import { createContext, useCallback, useContext, useEffect, useMemo, useState } from "react";
import { db } from "../services/db";

const SESSION_KEY = "agrilink:session:v1";
const AuthContext = createContext(null);

export function AuthProvider({ children }) {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);

  // Hydrate session on mount, awaiting the data layer's initial sync first
  // so the cache has a chance to populate when Firestore is the backend.
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        await db.ready();
        const raw = localStorage.getItem(SESSION_KEY);
        if (raw) {
          const { userId } = JSON.parse(raw);
          const fresh = db.findUserById(userId);
          if (!cancelled && fresh) setUser(fresh);
        }
      } catch {
        /* ignore */
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();
    return () => { cancelled = true; };
  }, []);

  // Keep `user` in sync if the underlying record changes (e.g. admin verifies us).
  const userId = user?.id;
  useEffect(() => {
    if (!userId) return;
    return db.subscribe(() => {
      const fresh = db.findUserById(userId);
      if (fresh) setUser((prev) => (prev && prev.id === fresh.id ? { ...prev, ...fresh } : prev));
    });
  }, [userId]);

  const login = useCallback(async (email, password) => {
    // Try cache first, fall back to a remote lookup (Firestore) so login
    // works even before the cache has hydrated.
    let found = db.findUserByEmail(email);
    if (!found && typeof db.findUserByEmailRemote === "function") {
      found = await db.findUserByEmailRemote(email);
    }
    if (!found) throw new Error("No account found with that email.");
    if (found.password !== password) throw new Error("Incorrect password.");
    if (found.blocked) throw new Error("This account has been blocked. Please contact AgriLink support.");
    localStorage.setItem(SESSION_KEY, JSON.stringify({ userId: found.id }));
    setUser(found);
    return found;
  }, []);

  const register = useCallback(async (data) => {
    const existing = db.findUserByEmail(data.email)
      || (typeof db.findUserByEmailRemote === "function" ? await db.findUserByEmailRemote(data.email) : null);
    if (existing) {
      throw new Error("An account with that email already exists.");
    }
    const created = await db.createUser(data);
    localStorage.setItem(SESSION_KEY, JSON.stringify({ userId: created.id }));
    setUser(created);
    return created;
  }, []);

  const logout = useCallback(() => {
    localStorage.removeItem(SESSION_KEY);
    setUser(null);
  }, []);

  const updateProfile = useCallback(
    async (patch) => {
      if (!user) return null;
      const updated = await db.updateUser(user.id, patch);
      setUser((prev) => ({ ...prev, ...updated }));
      return updated;
    },
    [user]
  );

  const value = useMemo(
    () => ({ user, loading, login, register, logout, updateProfile }),
    [user, loading, login, register, logout, updateProfile]
  );

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

// eslint-disable-next-line react-refresh/only-export-components
export const useAuth = () => {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error("useAuth must be used inside <AuthProvider>");
  return ctx;
};
