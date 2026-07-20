import { MapContainer, TileLayer, Marker, Popup } from "react-leaflet";
import { useEffect } from "react";
import { useMap } from "react-leaflet";
import { farmIcon } from "./leafletIcon";
import { DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "../../lib/constants";

function FitMarkers({ markers }) {
  const map = useMap();

  useEffect(() => {
    const points = markers
      .filter((m) => m.lat != null && m.lng != null)
      .map((m) => [m.lat, m.lng]);
    if (points.length === 0) return;
    if (points.length === 1) {
      map.setView(points[0], Math.max(map.getZoom(), 10));
      return;
    }
    map.fitBounds(points, { padding: [28, 28], maxZoom: 12 });
  }, [markers, map]);

  return null;
}

// Read-only multi-marker map for the buyer marketplace / admin overview.
export default function FarmsMap({ markers = [], height = 360 }) {
  const center =
    markers.length > 0 ? [markers[0].lat, markers[0].lng] : DEFAULT_MAP_CENTER;
  const zoom = markers.length > 0 ? 8 : DEFAULT_MAP_ZOOM;

  return (
    <div className="overflow-hidden rounded-xl border border-slate-200" style={{ height }}>
      <MapContainer center={center} zoom={zoom} style={{ height: "100%", width: "100%" }}>
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        <FitMarkers markers={markers} />
        {markers.map((m) => (
          <Marker key={m.id} position={[m.lat, m.lng]} icon={farmIcon}>
            <Popup>
              <div className="space-y-1">
                <div className="font-semibold text-slate-900">{m.title}</div>
                {m.subtitle && <div className="text-xs text-slate-500">{m.subtitle}</div>}
                {m.body && <div className="text-xs text-slate-700 mt-1">{m.body}</div>}
              </div>
            </Popup>
          </Marker>
        ))}
      </MapContainer>
    </div>
  );
}
