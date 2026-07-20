// Simple reverse geocoding using Nominatim (OpenStreetMap)
export async function reverseGeocode(lat, lng) {
  const url = `https://nominatim.openstreetmap.org/reverse?format=jsonv2&lat=${encodeURIComponent(lat)}&lon=${encodeURIComponent(lng)}&addressdetails=1`;
  try {
    const res = await fetch(url, {
      headers: { "User-Agent": "AgriLinks/1.0 (contact@agrilink.app)" },
    });
    if (!res.ok) return null;
    const json = await res.json();
    const addr = json.address || {};

    // Nominatim uses different keys; map common PH fields
    const barangay =
      addr.suburb ||
      addr.neighbourhood ||
      addr.hamlet ||
      addr.village ||
      addr.quarter ||
      addr.city_district ||
      addr.town ||
      null;
    const municipality =
      addr.city || addr.town || addr.municipality || addr.county || null;
    const province = addr.state || addr.region || null;

    return {
      displayName: json.display_name,
      barangay,
      municipality,
      province,
      raw: json,
    };
  } catch (err) {
    console.error("reverseGeocode error", err);
    return null;
  }
}
