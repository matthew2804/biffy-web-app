import { createContext, useContext, useMemo, useState, useCallback, type ReactNode } from "react";
import {
  deliveryPoints,
  dishById,
  dishes,
  restaurantById,
  restaurants,
  universities,
  type Dish,
} from "./mock-data";
import { isReachable } from "./format";
import { syncCatalog, productIdFromDish, sedeIdFromDish, type MerchantProfile, type MerchantProduct, type MOrder } from "./merchant";
import { demoOrders } from "./merchant-demo";

export type CartItem = { key: string; dishId: string; qty: number; optionIds: string[]; note: string };
export type OrderStatus = "programado" | "confirmado" | "preparando" | "en_camino" | "entregado" | "cancelado";
export type Order = {
  id: string;
  items: CartItem[];
  restaurantIds: string[];
  subtotal: number;
  discount: number;
  fee: number;
  tip: number;
  pointsUsed: number;
  total: number;
  status: OrderStatus;
  scheduledFor?: string | undefined; // ISO
  createdAt: string;
  paymentId: string;
  pointId: string;
  code: string;
};
export type User = {
  name: string;
  email: string;
  phone: string;
  career: string;
  universityId?: string | undefined;
  verified: boolean;
};
export type Prefs = { likes: string[]; allergies: string[]; lifestyle: string[]; budget: number };
export type Notification = { id: string; title: string; body: string; read: boolean };

const paymentLabels: Record<string, string> = { nequi: "Nequi", daviplata: "Daviplata", card: "Tarjeta", pse: "PSE", cash: "Efectivo" };
const GOTA_VALUE = 10; // 700 gotas ≈ $7.000 COP

function uid() {
  return Math.random().toString(36).slice(2, 9);
}
function code4() {
  return String(Math.floor(1000 + Math.random() * 9000));
}

function useStoreValue() {
  const [user, setUser] = useState<User | null>(null);
  const [points, setPoints] = useState(0);
  const [surveyDone, setSurveyDone] = useState(false);
  const [prefs, setPrefs] = useState<Prefs>({ likes: [], allergies: [], lifestyle: [], budget: 25000 });
  const [favorites, setFavorites] = useState<string[]>([]);
  const [cart, setCart] = useState<CartItem[]>([]);
  const [orders, setOrders] = useState<Order[]>([]);
  const [pointId, setPointId] = useState("biblio");
  const [mode, setMode] = useState<"student" | "courier" | "merchant">("student");
  const [defaultPayment, setDefaultPayment] = useState("nequi");
  const [referrals, setReferrals] = useState(0);
  const [notifications, setNotifications] = useState<Notification[]>([
    { id: "n1", title: "¡Bienvenido a Biffy! 🐝", body: "Completa tus filtros y gana 300 Gotas.", read: false },
    { id: "n2", title: "Descuento de campus", body: "Hasta 20% en locales de tu universidad.", read: false },
  ]);
  const [settings, setSettings] = useState({ push: true, promos: true, email: false, dark: false });
  const [courier, setCourier] = useState<{ online: boolean; zone: "general" | "campus"; earningsToday: number; deliveries: number; totalRides: number; pendingFee: number }>({ online: false, zone: "general", earningsToday: 0, deliveries: 0, totalRides: 7, pendingFee: 0 });

  const [merchant, setMerchant] = useState<MerchantProfile | null>(null);
  const [products, setProducts] = useState<MerchantProduct[]>([]);
  const [mOrders, setMOrders] = useState<MOrder[]>([]);
  const [catalogV, setCatalogV] = useState(0);
  const publish = (m: MerchantProfile | null, ps: MerchantProduct[]) => {
    syncCatalog(m, ps);
    setCatalogV((v) => v + 1);
  };

  const point = deliveryPoints.find((p) => p.id === pointId) ?? { id: "biblio", name: "Biblioteca Central", detail: "Entrada principal", lat: 4.6355, lng: -74.083 };
  const loggedIn = !!user;
  const ordersCount = orders.filter((o) => o.status === "entregado").length + 7 * (loggedIn ? 1 : 0);

  const notify = useCallback((title: string, body: string) => {
    setNotifications((n) => [{ id: uid(), title, body, read: false }, ...n]);
  }, []);

  const reachableRestaurants = useMemo(() => restaurants.filter((r) => isReachable(r, point)), [point, catalogV]);
  const reachableDishes = useMemo(() => {
    const ids = new Set(reachableRestaurants.map((r) => r.id));
    return dishes.filter((d) => ids.has(d.restaurantId));
  }, [reachableRestaurants, catalogV]);

  const campusEligible = (restaurantId: string) => {
    const r = restaurantById(restaurantId);
    return !!(r?.campusId && user?.verified && user.universityId === r.campusId);
  };

  const unitPrice = (d: Dish, optionIds: string[] = []) => {
    const base = d.price + (d.options ?? []).filter((o) => optionIds.includes(o.id)).reduce((s, o) => s + o.price, 0);
    return base;
  };
  const discountedPrice = (d: Dish) => {
    const r = restaurantById(d.restaurantId)!;
    return campusEligible(r.id) ? Math.round(d.price * (1 - (r.studentDiscount ?? 0))) : d.price;
  };

  const cartSummary = (pointsToUse = 0) => {
    let subtotal = 0;
    let discount = 0;
    const rIds = new Set<string>();
    for (const it of cart) {
      const d = dishById(it.dishId);
      if (!d) continue;
      const line = unitPrice(d, it.optionIds) * it.qty;
      subtotal += line;
      rIds.add(d.restaurantId);
      const r = restaurantById(d.restaurantId)!;
      if (campusEligible(r.id)) discount += Math.round(line * (r.studentDiscount ?? 0));
    }
    const allCampus = [...rIds].every((id) => !!restaurantById(id)?.campusId);
    const fee = cart.length === 0 ? 0 : (allCampus ? 1500 : 3500) * rIds.size;
    const maxPts = Math.min(pointsToUse, points, Math.floor((subtotal - discount) / GOTA_VALUE));
    const pointsDiscount = maxPts * GOTA_VALUE;
    const total = Math.max(0, subtotal - discount + fee - pointsDiscount);
    return { subtotal, discount, fee, pointsUsed: maxPts, pointsDiscount, total, restaurantIds: [...rIds] };
  };

  return {
    // state
    user, points, surveyDone, prefs, favorites, cart, orders, point, pointId, mode, defaultPayment,
    merchant, products, mOrders, catalogV,
    referrals, notifications, settings, courier, loggedIn, ordersCount,
    reachableRestaurants, reachableDishes, GOTA_VALUE,
    // helpers
    campusEligible, unitPrice, discountedPrice, cartSummary,
    university: universities.find((u) => u.id === user?.universityId),
    // actions
    startQbanoDemo() {
      setUser({ name: "Diego", email: "demo@icesi.edu.co", phone: "", career: "Estudiante · demostración", universityId: "icesi", verified: true });
      setPointId("icesi-biblioteca");
      setMode("student");
      setPrefs({ likes: ["sandwich"], allergies: [], lifestyle: [], budget: 30000 });
      setSurveyDone(true);
      setPoints(0);
      setDefaultPayment("cash");
      setCart([]);
      setOrders([]);
    },
    login(email: string, name: string) {
      const domain = email.split("@")[1]?.toLowerCase() ?? "";
      const uni = universities.find((u) => domain.endsWith(u.domain));
      setUser({ name: name || email.split("@")[0] || "Estudiante", email, phone: "+57 300 123 4567", career: "Ingeniería de Sistemas", universityId: uni?.id, verified: !!uni });
      setPoints((p) => (p === 0 ? 450 : p));
    },
    logout() {
      setUser(null);
      setMode("student");
      setCart([]);
    },
    verifyUniversity(email: string) {
      const domain = email.split("@")[1]?.toLowerCase() ?? "";
      const uni = universities.find((u) => domain.endsWith(u.domain));
      if (!uni) return false;
      setUser((u) => (u ? { ...u, universityId: uni.id, verified: true } : u));
      notify("Universidad verificada ✅", `Ya tienes acceso al campus ${uni.name}.`);
      return true;
    },
    updateUser(patch: Partial<User>) {
      setUser((u) => (u ? { ...u, ...patch } : u));
    },
    completeSurvey(p: Prefs) {
      setPrefs(p);
      if (!surveyDone) {
        setSurveyDone(true);
        setPoints((x) => x + 300);
        notify("+300 Gotas 💧", "Completaste tus filtros de gustos.");
      }
    },
    setPrefs,
    toggleFavorite(id: string) {
      setFavorites((f) => (f.includes(id) ? f.filter((x) => x !== id) : [...f, id]));
    },
    addToCart(dishId: string, qty = 1, optionIds: string[] = [], note = "") {
      setCart((c) => {
        const key = dishId + ":" + [...optionIds].sort().join(",") + ":" + note;
        const ex = c.find((i) => i.key === key);
        if (ex) return c.map((i) => (i.key === key ? { ...i, qty: i.qty + qty } : i));
        return [...c, { key, dishId, qty, optionIds, note }];
      });
    },
    setQty(key: string, qty: number) {
      setCart((c) => (qty <= 0 ? c.filter((i) => i.key !== key) : c.map((i) => (i.key === key ? { ...i, qty } : i))));
    },
    removeItem(key: string) {
      setCart((c) => c.filter((i) => i.key !== key));
    },
    clearCart() {
      setCart([]);
    },
    setPointId,
    setDefaultPayment,
    placeOrder(opts: { scheduledFor?: string | undefined; paymentId: string; pointsToUse: number; tip?: number }) {
      const s = cartSummary(opts.pointsToUse);
      const tip = Math.max(0, Math.round(opts.tip ?? 0));
      const order: Order = {
        id: "BF" + Math.floor(1000 + Math.random() * 9000),
        items: cart,
        restaurantIds: s.restaurantIds,
        subtotal: s.subtotal,
        discount: s.discount,
        fee: s.fee,
        tip,
        pointsUsed: s.pointsUsed,
        total: s.total + tip,
        status: opts.scheduledFor ? "programado" : "confirmado",
        scheduledFor: opts.scheduledFor,
        createdAt: new Date().toISOString(),
        paymentId: opts.paymentId,
        pointId,
        code: code4(),
      };
      setOrders((o) => [order, ...o]);
      // Route merchant-owned items to the merchant panel, one ticket per sede.
      const bySede = new Map<string, MOrder["items"]>();
      for (const it of cart) {
        const pid = productIdFromDish(it.dishId);
        const sid = sedeIdFromDish(it.dishId);
        const d = dishById(it.dishId);
        if (!pid || !sid || !d) continue;
        const arr = bySede.get(sid) ?? [];
        arr.push({ name: d.name, qty: it.qty, price: unitPrice(d, it.optionIds), ...(it.note ? { note: it.note } : {}) });
        bySede.set(sid, arr);
      }
      if (bySede.size) {
        const pay = (paymentLabels[opts.paymentId] ?? opts.paymentId) + (opts.paymentId === "cash" ? " · lo cobra el repartidor" : " · pagado");
        const tickets: MOrder[] = [...bySede].map(([sid, items]) => ({
          id: order.id + (bySede.size > 1 ? "-" + sid : ""), client: user?.name ?? "Cliente", items, total: items.reduce((a, i) => a + i.price * i.qty, 0),
          payment: pay, delivery: "domicilio", status: "nuevo", createdAt: order.createdAt, scheduledFor: opts.scheduledFor, sedeId: sid, clientOrderId: order.id,
        }));
        setMOrders((m) => [...tickets, ...m]);
      }
      setPoints((p) => p - s.pointsUsed + Math.floor(s.total / 1000));
      setCart([]);
      notify("Pedido " + order.id, opts.scheduledFor ? "Programado correctamente." : "¡Confirmado! El restaurante lo está recibiendo.");
      return order;
    },
    advanceOrder(id: string) {
      const flow: OrderStatus[] = ["confirmado", "preparando", "en_camino", "entregado"];
      setOrders((os) =>
        os.map((o) => {
          if (o.id !== id) return o;
          const i = flow.indexOf(o.status);
          if (i < 0 || i === flow.length - 1) return o;
          return { ...o, status: flow[i + 1]! };
        }),
      );
    },
    updateOrder(id: string, patch: Partial<Order>) {
      setOrders((os) => os.map((o) => (o.id === id ? { ...o, ...patch } : o)));
    },
    reorder(id: string) {
      const o = orders.find((x) => x.id === id);
      if (o) setCart(o.items.map((i) => ({ ...i })));
    },
    addPoints(n: number, reason: string) {
      setPoints((p) => p + n);
      notify(`+${n} Gotas 💧`, reason);
    },
    addReferral() {
      setReferrals((r) => r + 1);
      setPoints((p) => p + 200);
      notify("+200 Gotas 💧", "Un amigo se unió con tu código.");
    },
    markAllRead() {
      setNotifications((n) => n.map((x) => ({ ...x, read: true })));
    },
    setSettings,
    registerMerchant(m: MerchantProfile, ps: MerchantProduct[] = []) {
      setMerchant(m);
      setProducts(ps);
      setMOrders(ps.length ? demoOrders() : []);
      setMode("merchant");
      publish(m, ps);
      notify("Restaurante aprobado ✅", `${m.brand} ya está visible para clientes dentro de tu radio.`);
    },
    updateMerchant(patch: Partial<MerchantProfile>) {
      if (!merchant) return;
      const m = { ...merchant, ...patch };
      setMerchant(m);
      publish(m, products);
    },
    saveProduct(p: MerchantProduct) {
      const ps = products.some((x) => x.id === p.id) ? products.map((x) => (x.id === p.id ? p : x)) : [p, ...products];
      setProducts(ps);
      publish(merchant, ps);
    },
    deleteProduct(id: string) {
      const ps = products.filter((x) => x.id !== id);
      setProducts(ps);
      publish(merchant, ps);
    },
    setMOrderStatus(id: string, status: MOrder["status"], rejectReason?: string) {
      setMOrders((os) => os.map((o) => (o.id === id ? { ...o, status, ...(rejectReason ? { rejectReason } : {}) } : o)));
      const mo = mOrders.find((o) => o.id === id);
      if (mo?.clientOrderId) {
        const map: Partial<Record<MOrder["status"], OrderStatus>> = { preparando: "preparando", listo: "preparando", rechazado: "cancelado" };
        const st = map[status];
        if (st) setOrders((os) => os.map((o) => (o.id === mo.clientOrderId ? { ...o, status: st } : o)));
      }
      // Once ready, Biffy assigns a courier and handles the delivery — the merchant only watches.
      if (status === "listo") {
        setTimeout(() => {
          setMOrders((os) => os.map((o) => (o.id === id && o.status === "listo" ? { ...o, status: "en_camino" } : o)));
          if (mo?.clientOrderId) setOrders((os) => os.map((o) => (o.id === mo.clientOrderId ? { ...o, status: "en_camino" } : o)));
        }, 4000);
        setTimeout(() => setMOrders((os) => os.map((o) => (o.id === id && o.status === "en_camino" ? { ...o, status: "entregado" } : o))), 12000);
      }
    },
    setMode,
    setCourier,
  };
}

export type Store = ReturnType<typeof useStoreValue>;
// Keep one context instance across hot reloads so the provider and consumers always match.
const g = globalThis as unknown as { __biffyStoreCtx?: React.Context<Store | null> };
const Ctx = (g.__biffyStoreCtx ??= createContext<Store | null>(null));

export function StoreProvider({ children }: { children: ReactNode }) {
  const value = useStoreValue();
  return <Ctx.Provider value={value}>{children}</Ctx.Provider>;
}

export function useStore() {
  const v = useContext(Ctx);
  if (!v) throw new Error("useStore must be used inside StoreProvider");
  return v;
}
