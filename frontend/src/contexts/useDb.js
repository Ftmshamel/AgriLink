import { useEffect, useState } from "react";
import { db } from "../services/db";

// Generic hook that re-runs a selector function whenever the data layer
// notifies of a change.  Mirrors the "live" feel of Firestore's onSnapshot.
//
// `selector` should be a pure read; `deps` are the inputs the selector
// depends on (used both for re-running on prop change and for memoization).
export function useDb(selector, deps = []) {
  const [value, setValue] = useState(() => selector());

  // Re-read whenever a dependency changes.
  // eslint-disable-next-line react-hooks/set-state-in-effect, react-hooks/exhaustive-deps
  useEffect(() => { setValue(selector()); }, deps);

  // Subscribe to live updates.
  // eslint-disable-next-line react-hooks/exhaustive-deps
  useEffect(() => db.subscribe(() => setValue(selector())), deps);

  return value;
}
