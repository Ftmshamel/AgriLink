import {
  MapContainer,
  TileLayer,
  Marker,
  useMapEvents,
  useMap,
} from "react-leaflet";
import { useEffect } from "react";
import { farmIcon } from "./leafletIcon";
import { DEFAULT_MAP_CENTER, DEFAULT_MAP_ZOOM } from "../../lib/constants";
import { reverseGeocode } from "../../services/geocode";

function ClickHandler({ onPick }) {
  useMapEvents({
    async click(e) {
      const lat = e.latlng.lat;
      const lng = e.latlng.lng;
      const geo = await reverseGeocode(lat, lng);
      const payload = { lat, lng, ...(geo || {}) };
      onPick(payload);
    },
  });
  return null;
}

function Recenter({ position }) {
  const map = useMap();
  useEffect(() => {
    if (position)
      map.flyTo([position.lat, position.lng], Math.max(map.getZoom(), 12));
  }, [position, map]);
  return null;
}

// An interactive leaflet map. Click to drop / move a pin.
// Use as a controlled component: pass `value` and `onChange`.
export default function MapPicker({
  value,
  onChange,
  height = 320,
  readOnly = false,
}) {
  const center = value ? [value.lat, value.lng] : DEFAULT_MAP_CENTER;
  const zoom = value ? 13 : DEFAULT_MAP_ZOOM;

  return (
    <div
      className="overflow-hidden rounded-xl border border-slate-200"
      style={{ height }}
    >
      <MapContainer
        center={center}
        zoom={zoom}
        scrollWheelZoom={!readOnly}
        style={{ height: "100%", width: "100%" }}
      >
        <TileLayer
          attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
          url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
        />
        {!readOnly && <ClickHandler onPick={onChange} />}
        {value && <Marker position={[value.lat, value.lng]} icon={farmIcon} />}
        {value && <Recenter position={value} />}
      </MapContainer>
    </div>
  );
}
