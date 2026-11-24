import qbanoSandwich from "@/assets/demo-qbano-sandwich.jpg";

// Mock data (no backend yet). Bogotá catalog plus a fictional Icesi demo.
export type CategoryId =
  | "pizza"
  | "hamburguesa"
  | "saludable"
  | "cafe"
  | "postres"
  | "mexicana"
  | "asiatica"
  | "almuerzo"
  | "sandwich";

export const categories: { id: CategoryId; label: string; emoji: string }[] = [
  { id: "sandwich", label: "Sándwiches", emoji: "🥪" },
  { id: "pizza", label: "Pizza", emoji: "🍕" },
  { id: "hamburguesa", label: "Hamburguesas", emoji: "🍔" },
  { id: "saludable", label: "Saludable", emoji: "🥗" },
  { id: "almuerzo", label: "Almuerzos", emoji: "🍛" },
  { id: "cafe", label: "Café", emoji: "☕" },
  { id: "postres", label: "Postres", emoji: "🍩" },
  { id: "mexicana", label: "Mexicana", emoji: "🌮" },
  { id: "asiatica", label: "Asiática", emoji: "🍜" },
];

export const universities = [
  { id: "icesi", name: "Universidad Icesi", domain: "icesi.edu.co" },
  { id: "unal", name: "Universidad Nacional", domain: "unal.edu.co" },
  { id: "andes", name: "Universidad de los Andes", domain: "uniandes.edu.co" },
  { id: "javeriana", name: "Pontificia Universidad Javeriana", domain: "javeriana.edu.co" },
];

export type DeliveryPoint = { id: string; name: string; detail: string; lat: number; lng: number };
export const deliveryPoints: DeliveryPoint[] = [
  { id: "icesi-biblioteca", name: "Icesi · Biblioteca", detail: "Punto de encuentro demo · Cali", lat: 3.3415, lng: -76.5305 },
  { id: "icesi-plazoleta", name: "Icesi · Plazoleta", detail: "Punto de encuentro demo · Cali", lat: 3.3421, lng: -76.5298 },
  { id: "icesi-entrada", name: "Icesi · Entrada principal", detail: "Punto de encuentro demo · Cali", lat: 3.3409, lng: -76.5309 },
  { id: "biblio", name: "Biblioteca Central", detail: "Entrada principal", lat: 4.6355, lng: -74.083 },
  { id: "inge", name: "Edificio Ingeniería", detail: "Hall piso 1", lat: 4.6378, lng: -74.0825 },
  { id: "plazoleta", name: "Plazoleta Che", detail: "Junto a las bancas", lat: 4.6362, lng: -74.0815 },
  { id: "chapinero", name: "Casa · Chapinero", detail: "Cra 7 #60-20", lat: 4.6465, lng: -74.0628 },
  { id: "suba", name: "Casa · Suba (lejos)", detail: "Cl 145 #91-10", lat: 4.7405, lng: -74.0835 },
];

export type Restaurant = {
  id: string;
  name: string;
  emoji: string;
  tagline: string;
  rating: number;
  timeMin: number;
  lat: number;
  lng: number;
  radiusKm: number;
  couriersNearby: number;
  campusId?: string;
  studentDiscount?: number; // 0.15 = 15%
  open: number; // hour 0-23
  close: number;
  closedDays: number[]; // 0 = domingo
  place: string;
  showsNutrition?: boolean;
  paused?: boolean;
  brandId?: string;
  demo?: boolean;
  campusDeliveryOnly?: boolean;
};

export const restaurants: Restaurant[] = [
  { id: "qbano-icesi", name: "Qbano · Icesi", emoji: "🥪", tagline: "Sándwiches · menú de demostración", rating: 4.8, timeMin: 8, lat: 3.3418, lng: -76.5303, radiusKm: 0.6, couriersNearby: 2, campusId: "icesi", open: 10, close: 20, closedDays: [0], place: "Entrega dentro de Icesi · sede simulada", demo: true, campusDeliveryOnly: true },
  { id: "r1", name: "La Plazoleta Pizza", emoji: "🍕", tagline: "Pizza artesanal en horno de leña", rating: 4.8, timeMin: 15, lat: 4.6365, lng: -74.0818, radiusKm: 2.5, couriersNearby: 6, campusId: "unal", studentDiscount: 0.15, open: 10, close: 21, closedDays: [0], place: "Plazoleta B · Local 12" },
  { id: "r2", name: "Burger Lab", emoji: "🍔", tagline: "Smash burgers y papas rústicas", rating: 4.6, timeMin: 20, lat: 4.6395, lng: -74.0790, radiusKm: 3, couriersNearby: 4, open: 11, close: 22, closedDays: [], place: "Cl 45 #22-10" },
  { id: "r3", name: "Verde Bowl", emoji: "🥗", tagline: "Bowls frescos, veganos y sin gluten", rating: 4.9, timeMin: 12, lat: 4.6370, lng: -74.0840, radiusKm: 2, couriersNearby: 5, campusId: "unal", studentDiscount: 0.2, open: 7, close: 19, closedDays: [0, 6], place: "Edificio Ingeniería · Cafetería", showsNutrition: true },
  { id: "r4", name: "Café Enjambre", emoji: "☕", tagline: "Café de origen y pastelería", rating: 4.7, timeMin: 8, lat: 4.6350, lng: -74.0828, radiusKm: 1.5, couriersNearby: 3, campusId: "unal", studentDiscount: 0.1, open: 6, close: 20, closedDays: [0], place: "Biblioteca Central · Piso 1", showsNutrition: true },
  { id: "r5", name: "Taquería El Parche", emoji: "🌮", tagline: "Tacos al pastor y burritos", rating: 4.5, timeMin: 25, lat: 4.6450, lng: -74.0650, radiusKm: 3.5, couriersNearby: 2, open: 12, close: 23, closedDays: [1], place: "Chapinero · Cra 9 #58" },
  { id: "r6", name: "Wok Express", emoji: "🍜", tagline: "Ramen, arroz chino y bao", rating: 4.4, timeMin: 22, lat: 4.6420, lng: -74.0750, radiusKm: 4, couriersNearby: 3, campusId: "andes", studentDiscount: 0.12, open: 11, close: 21, closedDays: [], place: "Cl 53 #13-40" },
  { id: "r7", name: "Corrientazo Doña Rosa", emoji: "🍛", tagline: "Almuerzo ejecutivo casero", rating: 4.8, timeMin: 18, lat: 4.6340, lng: -74.0850, radiusKm: 2, couriersNearby: 4, campusId: "unal", studentDiscount: 0.1, open: 11, close: 16, closedDays: [0], place: "Calle 26 · Local 3" },
  { id: "r8", name: "Domino's Norte", emoji: "🍕", tagline: "Cadena · cobertura amplia", rating: 4.2, timeMin: 35, lat: 4.7300, lng: -74.0700, radiusKm: 6, couriersNearby: 8, open: 10, close: 23, closedDays: [], place: "Suba · Cl 140" },
  { id: "r9", name: "Dulce Panal", emoji: "🍩", tagline: "Donas, brownies y malteadas", rating: 4.6, timeMin: 14, lat: 4.6380, lng: -74.0805, radiusKm: 2.5, couriersNearby: 0, open: 9, close: 20, closedDays: [], place: "Cl 44 #20-15" },
];

export type DishOption = { id: string; label: string; price: number };
export type Dish = {
  id: string;
  restaurantId: string;
  name: string;
  description: string;
  price: number;
  emoji: string;
  category: CategoryId;
  tags: string[]; // vegano, vegetariano, sin gluten, picante, alto en proteína
  allergens: string[]; // gluten, lácteos, maní, mariscos, huevo, soya
  calories: number;
  popular?: boolean;
  options?: DishOption[];
  section: string;
  photo?: string;
  nutrition?: Nutrition;
};
export type Nutrition = { kcal: number; protein: number; carbs: number; fat: number };

export const dishes: Dish[] = [
  { id: "qbano-especial", restaurantId: "qbano-icesi", name: "Qbano Especial", description: "Ejemplo de menú: pan tostado, pollo, jamón, queso, lechuga, tomate y salsa. Ingredientes y precio no oficiales.", price: 24900, emoji: "🥪", category: "sandwich", tags: [], allergens: ["gluten", "lácteos", "huevo"], calories: 0, popular: true, section: "Sándwiches", photo: qbanoSandwich, options: [{ id: "qbano-queso", label: "Extra queso", price: 3000 }] },
  { id: "qbano-pollo", restaurantId: "qbano-icesi", name: "Sándwich de Pollo", description: "Ejemplo de menú: pan tostado, pollo, queso, lechuga y tomate. Ingredientes y precio no oficiales.", price: 21900, emoji: "🥪", category: "sandwich", tags: [], allergens: ["gluten", "lácteos"], calories: 0, popular: true, section: "Sándwiches", photo: qbanoSandwich },
  { id: "qbano-vegetariano", restaurantId: "qbano-icesi", name: "Sándwich Vegetariano", description: "Ejemplo de menú: pan tostado, queso, lechuga, tomate y vegetales. Ingredientes y precio no oficiales.", price: 18900, emoji: "🥪", category: "sandwich", tags: ["vegetariano"], allergens: ["gluten", "lácteos"], calories: 0, section: "Sándwiches" },
  { id: "d1", restaurantId: "r1", name: "Pizza Margarita", description: "Tomate, mozzarella fresca y albahaca.", price: 18000, emoji: "🍕", category: "pizza", tags: ["vegetariano"], allergens: ["gluten", "lácteos"], calories: 720, popular: true, section: "Pizzas", options: [{ id: "o1", label: "Borde de queso", price: 4000 }, { id: "o2", label: "Extra albahaca", price: 1000 }] },
  { id: "d2", restaurantId: "r1", name: "Pizza Pepperoni", description: "Doble pepperoni y orégano.", price: 21000, emoji: "🍕", category: "pizza", tags: ["picante"], allergens: ["gluten", "lácteos"], calories: 860, popular: true, section: "Pizzas", options: [{ id: "o1", label: "Borde de queso", price: 4000 }, { id: "o3", label: "Jalapeños", price: 2000 }] },
  { id: "d3", restaurantId: "r1", name: "Limonada de coco", description: "Natural, 16 oz.", price: 7000, emoji: "🥥", category: "cafe", tags: ["vegano", "sin gluten"], allergens: [], calories: 210, section: "Bebidas" },
  { id: "d4", restaurantId: "r2", name: "Smash Doble", description: "Doble carne, cheddar, cebolla caramelizada.", price: 24000, emoji: "🍔", category: "hamburguesa", tags: ["alto en proteína"], allergens: ["gluten", "lácteos", "huevo"], calories: 980, popular: true, section: "Burgers", options: [{ id: "o4", label: "Tocineta", price: 3500 }, { id: "o5", label: "Papas grandes", price: 4000 }] },
  { id: "d5", restaurantId: "r2", name: "Burger Veggie", description: "Medallón de garbanzo y aguacate.", price: 19000, emoji: "🍔", category: "hamburguesa", tags: ["vegetariano"], allergens: ["gluten", "soya"], calories: 640, section: "Burgers" },
  { id: "d6", restaurantId: "r2", name: "Papas rústicas", description: "Con salsa de la casa.", price: 8000, emoji: "🍟", category: "hamburguesa", tags: ["vegano", "sin gluten"], allergens: [], calories: 420, section: "Acompañantes" },
  { id: "d7", restaurantId: "r3", name: "Bowl Proteico", description: "Quinoa, pollo, aguacate y huevo.", price: 22000, emoji: "🥗", category: "saludable", tags: ["sin gluten", "alto en proteína"], allergens: ["huevo"], calories: 560, popular: true, section: "Bowls", nutrition: { kcal: 560, protein: 38, carbs: 52, fat: 20 } },
  { id: "d8", restaurantId: "r3", name: "Bowl Vegano", description: "Garbanzos, hummus, vegetales asados.", price: 19500, emoji: "🥙", category: "saludable", tags: ["vegano", "sin gluten"], allergens: ["sésamo"], calories: 480, section: "Bowls", options: [{ id: "o6", label: "Extra hummus", price: 2500 }], nutrition: { kcal: 480, protein: 18, carbs: 60, fat: 17 } },
  { id: "d9", restaurantId: "r3", name: "Wrap de pollo", description: "Tortilla integral y vegetales.", price: 16000, emoji: "🌯", category: "saludable", tags: ["alto en proteína"], allergens: ["gluten", "lácteos"], calories: 510, section: "Wraps", nutrition: { kcal: 510, protein: 32, carbs: 48, fat: 19 } },
  { id: "d10", restaurantId: "r4", name: "Capuchino", description: "Café de origen Huila.", price: 6500, emoji: "☕", category: "cafe", tags: ["vegetariano", "sin gluten"], allergens: ["lácteos"], calories: 140, popular: true, section: "Café", options: [{ id: "o7", label: "Leche de almendras", price: 1500 }, { id: "o8", label: "Shot extra", price: 2000 }], nutrition: { kcal: 140, protein: 7, carbs: 12, fat: 7 } },
  { id: "d11", restaurantId: "r4", name: "Croissant de almendras", description: "Horneado cada mañana.", price: 7500, emoji: "🥐", category: "postres", tags: ["vegetariano"], allergens: ["gluten", "lácteos", "maní", "huevo"], calories: 390, section: "Pastelería", nutrition: { kcal: 390, protein: 8, carbs: 40, fat: 22 } },
  { id: "d12", restaurantId: "r5", name: "Tacos al pastor x3", description: "Cerdo marinado, piña y cilantro.", price: 17000, emoji: "🌮", category: "mexicana", tags: ["picante", "sin gluten"], allergens: [], calories: 620, popular: true, section: "Tacos" },
  { id: "d13", restaurantId: "r5", name: "Burrito de frijol", description: "Arroz, frijol, pico de gallo.", price: 15000, emoji: "🌯", category: "mexicana", tags: ["vegano"], allergens: ["gluten"], calories: 700, section: "Burritos" },
  { id: "d14", restaurantId: "r6", name: "Ramen Tonkotsu", description: "Caldo de cerdo, huevo y cebollín.", price: 26000, emoji: "🍜", category: "asiatica", tags: [], allergens: ["gluten", "huevo", "soya"], calories: 850, popular: true, section: "Ramen" },
  { id: "d15", restaurantId: "r6", name: "Arroz de camarón", description: "Wok con vegetales.", price: 23000, emoji: "🍤", category: "asiatica", tags: ["sin gluten"], allergens: ["mariscos", "soya"], calories: 690, section: "Wok" },
  { id: "d16", restaurantId: "r7", name: "Almuerzo ejecutivo", description: "Sopa, seco del día, jugo y postre.", price: 13000, emoji: "🍛", category: "almuerzo", tags: [], allergens: ["gluten"], calories: 900, popular: true, section: "Menú del día" },
  { id: "d17", restaurantId: "r7", name: "Bandeja vegetariana", description: "Arroz, frijol, maduro y ensalada.", price: 12000, emoji: "🥘", category: "almuerzo", tags: ["vegetariano", "sin gluten"], allergens: [], calories: 780, section: "Menú del día" },
  { id: "d18", restaurantId: "r8", name: "Pizza Hawaiana familiar", description: "Jamón y piña, 8 porciones.", price: 39000, emoji: "🍕", category: "pizza", tags: [], allergens: ["gluten", "lácteos"], calories: 1900, section: "Pizzas" },
  { id: "d19", restaurantId: "r9", name: "Dona glaseada", description: "Glaseado de vainilla.", price: 4500, emoji: "🍩", category: "postres", tags: ["vegetariano"], allergens: ["gluten", "lácteos", "huevo"], calories: 300, section: "Donas" },
];

export const allergyOptions = ["gluten", "lácteos", "maní", "mariscos", "huevo", "soya", "sésamo"];
export const lifestyleOptions = ["vegano", "vegetariano", "sin gluten", "alto en proteína", "bajo en calorías"];
export const tasteOptions: { id: CategoryId; label: string; emoji: string }[] = categories;

export const paymentMethodsCatalog = [
  { id: "nequi", label: "Nequi", emoji: "📱" },
  { id: "daviplata", label: "Daviplata", emoji: "📲" },
  { id: "card", label: "Tarjeta •••• 4521", emoji: "💳" },
  { id: "pse", label: "PSE", emoji: "🏦" },
  { id: "cash", label: "Efectivo", emoji: "💵" },
];

export const restaurantById = (id: string) => restaurants.find((r) => r.id === id);
export const dishById = (id: string) => dishes.find((d) => d.id === id);
