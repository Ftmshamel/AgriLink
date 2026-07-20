// Leaflet's default marker icons rely on relative asset paths that break under
// bundlers like Vite. We swap in a tiny inline SVG icon so we don't need to
// host PNG sprites.
import L from "leaflet";

const farmSvg = `
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 44" width="32" height="44">
  <path d="M16 0C7.16 0 0 7.16 0 16c0 11 16 28 16 28s16-17 16-28C32 7.16 24.84 0 16 0z" fill="#377c1f"/>
  <circle cx="16" cy="16" r="7" fill="#fff"/>
  <path d="M16 10c-2 1.5-3 3.5-3 5.5 0 2 1.5 3.5 3 3.5s3-1.5 3-3.5c0-2-1-4-3-5.5z" fill="#377c1f"/>
</svg>`;

export const farmIcon = L.divIcon({
  className: "agrilink-marker",
  html: farmSvg,
  iconSize: [32, 44],
  iconAnchor: [16, 44],
  popupAnchor: [0, -40],
});
