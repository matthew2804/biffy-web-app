import type { Dish, Restaurant, DeliveryPoint } from "./mock-data";

export const cop = (n: number) =>
  "$" + Math.round(n).toLocaleString("es-CO", { maximumFractionDigits: 0 });

export function distanceKm(a: { lat: number; lng: number }, b: { lat: number; lng: number }) {
  const R = 6371;
  const dLat = ((b.lat - a.lat) * Math.PI) / 180;
  const dLng = ((b.lng - a.lng) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a.lat * Math.PI) / 180) * Math.cos((b.lat * Math.PI) / 180) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** A restaurant is visible only if the point is inside its radius and couriers are nearby. */
export function isReachable(r: Restaurant, p: DeliveryPoint) {
  if (r.campusDeliveryOnly && !p.id.startsWith(`${r.campusId}-`)) return false;
  return r.couriersNearby > 0 && distanceKm(r, p) <= r.radiusKm;
}

export function isOpenNow(r: Restaurant, d = new Date()) {
  const h = d.getHours();
  return !r.paused && !r.closedDays.includes(d.getDay()) && h >= r.open && h < r.close;
}

export function allergyConflicts(d: Dish, allergies: string[]) {
  return d.allergens.filter((a) => allergies.includes(a));
}
