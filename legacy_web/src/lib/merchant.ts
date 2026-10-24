import { categories, dishes, restaurants, type CategoryId, type DishOption, type Nutrition } from "./mock-data";

/** Brand id used for the restaurants created by the merchant of this session. */
export const MERCHANT_BRAND = "me";
/** Biffy commission over each order (charged in the biweekly settlement). */
export const BIFFY_COMMISSION = 0.15;
/** Colombian national consumption tax (INC) for restaurants, already included in the price. */
export const INC_RATE = 0.08;

export type Sede = {
  id: string;
  name: string;
  address: string;
  city: string;
  locId: string;
  phone: string;
  open: number;
  close: number;
  closedDays: number[];
  radiusKm: number;
  campusId?: string | undefined;
  discount: number; // 0..0.3, only with campusId
};

export type DocId = "rut" | "camara" | "cedula" | "banco" | "sanitario" | "manipulacion";
export const docCatalog: { id: DocId; label: string; hint: string; onlyJuridica?: boolean }[] = [
  { id: "rut", label: "RUT actualizado (DIAN)", hint: "Debe mostrar tu responsabilidad frente al impuesto al consumo" },
  { id: "camara", label: "Certificado de Cámara de Comercio", hint: "Expedido hace menos de 30 días", onlyJuridica: true },
  { id: "cedula", label: "Cédula del representante legal", hint: "Ambas caras, legible" },
  { id: "banco", label: "Certificación bancaria", hint: "A nombre del titular del RUT, menor a 30 días" },
  { id: "sanitario", label: "Concepto sanitario favorable", hint: "Secretaría de Salud de tu ciudad" },
  { id: "manipulacion", label: "Curso de manipulación de alimentos", hint: "Certificado vigente del personal de cocina" },
];

export type MerchantProfile = {
  ownerName: string;
  docType: "CC" | "CE" | "PPT";
  docNumber: string;
  ownerRole: string;
  phone: string;
  email: string;
  brand: string;
  legalName: string;
  nit: string;
  personType: "natural" | "juridica";
  cuisine: CategoryId;
  description: string;
  logo: string;
  sedes: Sede[];
  incResponsible: boolean; // true → INC 8% obligatorio
  docs: Partial<Record<DocId, string>>;
  bank: { bank: string; type: "ahorros" | "corriente"; number: string; holder: string };
  showsNutrition: boolean;
  paused: boolean;
};

export type MerchantProduct = {
  id: string;
  name: string;
  category: CategoryId;
  section: string;
  description: string;
  ingredients: string[];
  allergens: string[];
  noAllergens: boolean;
  tags: string[];
  price: number;
  prepMin: number;
  photo: string;
  extraPhotos: string[];
  sedeIds: string[];
  options: DishOption[];
  available: boolean;
  featured: boolean;
  dailyStock: number | null;
  nutrition: Nutrition | null;
};

export type MOrderStatus = "nuevo" | "preparando" | "listo" | "en_camino" | "entregado" | "rechazado";
export type MOrder = {
  id: string;
  client: string;
  items: { name: string; qty: number; price: number; note?: string }[];
  total: number;
  payment: string;
  delivery: "domicilio" | "recoger";
  status: MOrderStatus;
  createdAt: string;
  scheduledFor?: string | undefined;
  rejectReason?: string;
  sedeId: string;
  clientOrderId?: string;
};

export const sedeLocations = [
  { id: "unal", label: "Campus U. Nacional · Plazoleta", lat: 4.6366, lng: -74.0822 },
  { id: "teusaquillo", label: "Teusaquillo · Cl 45", lat: 4.6392, lng: -74.0795 },
  { id: "chapinero", label: "Chapinero · Cra 7", lat: 4.6455, lng: -74.0640 },
  { id: "andes", label: "Las Aguas · U. de los Andes", lat: 4.6020, lng: -74.0660 },
  { id: "suba", label: "Suba · Cl 145", lat: 4.7395, lng: -74.0830 },
];

export const banks = ["Bancolombia", "Davivienda", "Banco de Bogotá", "BBVA", "Nequi", "Daviplata"];

/** Validation shared by the product editor; returns human messages, empty = publishable. */
export function productErrors(p: MerchantProduct, needsNutrition: boolean): string[] {
  const e: string[] = [];
  if (!p.photo) e.push("Sube la foto principal del plato");
  if (p.name.trim().length < 3) e.push("Nombre del producto (mín. 3 caracteres)");
  if (p.description.trim().length < 20) e.push("Descripción (mín. 20 caracteres)");
  if (!p.section.trim()) e.push("Sección en la carta");
  if (p.ingredients.length === 0) e.push("Agrega al menos un ingrediente");
  if (!p.noAllergens && p.allergens.length === 0) e.push("Marca los alérgenos o confirma que no tiene");
  if (!(p.price >= 1000)) e.push("Precio de venta (mín. $1.000)");
  if (p.sedeIds.length === 0) e.push("Selecciona al menos una sede");
  if (p.options.some((o) => !o.label.trim())) e.push("Completa el nombre de cada extra");
  if (needsNutrition) {
    const n = p.nutrition;
    if (!n || !(n.kcal > 0) || n.protein < 0 || n.carbs < 0 || n.fat < 0 || [n.protein, n.carbs, n.fat].some((x) => Number.isNaN(x)))
      e.push("Calorías y nutrientes (tu restaurante los muestra)");
  }
  return e;
}

export function emptyProduct(id: string, sedeIds: string[]): MerchantProduct {
  return { id, name: "", category: "almuerzo", section: "", description: "", ingredients: [], allergens: [], noAllergens: false, tags: [], price: 0, prepMin: 15, photo: "", extraPhotos: [], sedeIds, options: [], available: true, featured: false, dailyStock: null, nutrition: null };
}

export const restaurantIdForSede = (sedeId: string) => `${MERCHANT_BRAND}-${sedeId}`;

/** Publishes merchant data into the shared catalog so clients see it (respecting radius rules). */
export function syncCatalog(m: MerchantProfile | null, products: MerchantProduct[]) {
  for (let i = restaurants.length - 1; i >= 0; i--) if (restaurants[i]!.brandId === MERCHANT_BRAND) restaurants.splice(i, 1);
  for (let i = dishes.length - 1; i >= 0; i--) if (dishes[i]!.id.startsWith("mp-")) dishes.splice(i, 1);
  if (!m) return;
  const emoji = categories.find((c) => c.id === m.cuisine)?.emoji ?? "🍽️";
  for (const s of m.sedes) {
    const loc = sedeLocations.find((l) => l.id === s.locId) ?? sedeLocations[0]!;
    restaurants.push({
      id: restaurantIdForSede(s.id), name: `${m.brand} · ${s.name}`, emoji, tagline: m.description, rating: 5, timeMin: 20,
      lat: loc.lat, lng: loc.lng, radiusKm: s.radiusKm, couriersNearby: 3, open: s.open, close: s.close, closedDays: s.closedDays,
      place: `${s.address}, ${s.city}`, showsNutrition: m.showsNutrition, paused: m.paused, brandId: MERCHANT_BRAND,
      ...(s.campusId ? { campusId: s.campusId, studentDiscount: s.discount } : {}),
    });
  }
  for (const p of products) {
    if (!p.available || p.dailyStock === 0) continue;
    for (const sid of p.sedeIds) {
      if (!m.sedes.some((s) => s.id === sid)) continue;
      dishes.push({
        id: `mp-${p.id}-${sid}`, restaurantId: restaurantIdForSede(sid), name: p.name, description: p.description, price: p.price,
        emoji, category: p.category, tags: p.tags, allergens: p.allergens, calories: p.nutrition?.kcal ?? 0, popular: p.featured,
        section: p.section, photo: p.photo, ...(p.options.length ? { options: p.options } : {}),
        ...(m.showsNutrition && p.nutrition ? { nutrition: p.nutrition } : {}),
      });
    }
  }
}

export const productIdFromDish = (dishId: string) => (dishId.startsWith("mp-") ? dishId.split("-")[1]! : null);
export const sedeIdFromDish = (dishId: string) => (dishId.startsWith("mp-") ? dishId.split("-").slice(2).join("-") : null);

export function incBreakdown(total: number, responsible: boolean) {
  if (!responsible) return { base: total, inc: 0 };
  const base = Math.round(total / (1 + INC_RATE));
  return { base, inc: total - base };
}
