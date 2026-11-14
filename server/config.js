// Limits and shared constants for the room server (docs/multiplayer.md section 5.3).
// Dependency-free: imported by the entries (worker.js, server.js) and the tests.

export const config = {
  max_peers_per_room: 4,
  max_text_bytes: 8192,
  max_binary_bytes: 2300,
  rate_msgs_per_s: 60,
  rate_burst: 120,
  room_max_age_s: 21600,
  room_code_length: 5,
  room_code_alphabet: "ABCDEFGHJKLMNPQRSTUVWXYZ23456789",
  max_name_chars: 12,
};

const LOCAL_ORIGIN = /^http:\/\/(localhost|127\.0\.0\.1)(:\d+)?$/;

// "a, b" -> ["a", "b"]
export function parseOrigins(text) {
  return String(text || "").split(",").map((s) => s.trim()).filter((s) => s.length > 0);
}

// Origin check shared by both entries. Localhost is always accepted.
// allowMissing: accept a request with no Origin header (native clients; local server only).
export function originAllowed(origin, allowedList, allowMissing) {
  if (!origin) return allowMissing === true;
  if (LOCAL_ORIGIN.test(origin)) return true;
  return allowedList.includes(origin);
}
