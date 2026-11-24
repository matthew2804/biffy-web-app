import bowl from "@/assets/demo-bowl.jpg";
import burger from "@/assets/demo-burger.jpg";
import type { MerchantProduct, MerchantProfile, MOrder } from "./merchant";

/** Demo data used by the "Autocompletar demo" button in merchant onboarding. */
export const demoProfile: MerchantProfile = {
  ownerName: "Laura Gómez", docType: "CC", docNumber: "1020304050", ownerRole: "Representante legal", phone: "3104567890", email: "",
  brand: "Wok & Roll", legalName: "Wok & Roll Express S.A.S.", nit: "901234567-8", personType: "juridica", cuisine: "asiatica",
  description: "Bowls asiáticos, wok y sushi hechos al momento", logo: bowl,
  sedes: [
    { id: "s1", name: "Campus", address: "Plazoleta B · Local 4", city: "Bogotá", locId: "unal", phone: "3104567890", open: 10, close: 21, closedDays: [0], radiusKm: 2.5, campusId: "unal", discount: 0.1 },
    { id: "s2", name: "Chapinero", address: "Calle 45 #18-22", city: "Bogotá", locId: "chapinero", phone: "3104567891", open: 11, close: 22, closedDays: [], radiusKm: 3.5, campusId: undefined, discount: 0 },
  ],
  incResponsible: true,
  docs: { rut: "rut.pdf", camara: "camara.pdf", cedula: "cedula.pdf", banco: "cert-bancaria.pdf", sanitario: "concepto.pdf", manipulacion: "manipulacion.pdf" },
  bank: { bank: "Bancolombia", type: "corriente", number: "12345678901", holder: "Wok & Roll Express S.A.S." },
  showsNutrition: true, paused: false,
};

export const demoProducts: MerchantProduct[] = [
  { id: "p1", name: "Teriyaki Chicken Bowl", category: "asiatica", section: "Bowls", description: "Pollo glaseado en salsa teriyaki sobre arroz jazmín con vegetales salteados y ajonjolí.", ingredients: ["Pollo", "Arroz jazmín", "Brócoli", "Zanahoria", "Ajonjolí", "Salsa teriyaki"], allergens: ["soya", "sésamo", "gluten"], noAllergens: false, tags: ["alto en proteína"], price: 22500, prepMin: 15, photo: bowl, extraPhotos: [], sedeIds: ["s1", "s2"], options: [{ id: "x1", label: "Extra pollo (100 g)", price: 6000 }, { id: "x2", label: "Quinoa en vez de arroz", price: 2000 }], available: true, featured: true, dailyStock: 35, nutrition: { kcal: 640, protein: 42, carbs: 70, fat: 18 } },
  { id: "p2", name: "Smash Burger Combo", category: "hamburguesa", section: "Combos", description: "Doble carne smash con cheddar fundido, pepinillos, papas rústicas y bebida.", ingredients: ["Carne de res", "Cheddar", "Pan brioche", "Pepinillos", "Papas"], allergens: ["gluten", "lácteos", "huevo"], noAllergens: false, tags: [], price: 28900, prepMin: 20, photo: burger, extraPhotos: [], sedeIds: ["s2"], options: [], available: true, featured: false, dailyStock: null, nutrition: { kcal: 1150, protein: 48, carbs: 95, fat: 62 } },
];

export function demoOrders(): MOrder[] {
  const now = Date.now();
  const iso = (m: number) => new Date(now - m * 60000).toISOString();
  return [
    { id: "B-1842", client: "Camila R.", items: [{ name: "Teriyaki Chicken Bowl", qty: 2, price: 22500, note: "Salsa aparte" }], total: 45000, payment: "Nequi · pagado", delivery: "domicilio", status: "nuevo", createdAt: iso(3), sedeId: "s1" },
    { id: "B-1841", client: "Daniel S.", items: [{ name: "Smash Burger Combo", qty: 1, price: 28900, note: "Sin cebolla" }], total: 28900, payment: "Efectivo · lo cobra el repartidor", delivery: "domicilio", status: "preparando", createdAt: iso(11), sedeId: "s2" },
    { id: "B-1840", client: "Sofía P.", items: [{ name: "Teriyaki Chicken Bowl", qty: 1, price: 22500 }], total: 22500, payment: "Tarjeta · pagado", delivery: "domicilio", status: "en_camino", createdAt: iso(25), sedeId: "s1" },
    { id: "B-1839", client: "Mario L.", items: [{ name: "Teriyaki Chicken Bowl", qty: 2, price: 22500 }], total: 45000, payment: "PSE · pagado", delivery: "domicilio", status: "entregado", createdAt: iso(55), sedeId: "s1" },
  ];
}
