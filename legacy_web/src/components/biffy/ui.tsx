import { Link, useNavigate, useRouterState } from "@tanstack/react-router";
import { ArrowLeft, Heart, Home, Search, Sparkles, User, ShoppingBag, AlertTriangle, Plus, Bike, Wallet, Store, ClipboardList, UtensilsCrossed, BarChart3 } from "lucide-react";
import type { ReactNode } from "react";
import { toast } from "sonner";
import { useStore } from "@/lib/store";
import { cop, allergyConflicts, distanceKm } from "@/lib/format";
import { restaurantById, type Dish, type Restaurant } from "@/lib/mock-data";
import { cn } from "@/lib/utils";

export function Screen({ children, nav = true, className }: { children: ReactNode; nav?: boolean; className?: string }) {
  return (
    <div className={cn("min-h-dvh pb-6", nav && "pb-28", className)}>
      {children}
      {nav && <BottomNav />}
      <CartFab withNav={nav} />
    </div>
  );
}

export function TopBar({ title, right, back = true }: { title: string; right?: ReactNode; back?: boolean }) {
  const navigate = useNavigate();
  return (
    <header className="sticky top-0 z-30 grid grid-cols-[2.75rem_minmax(0,1fr)_2.75rem] items-center gap-2 bg-background/95 px-3 pb-2 pt-[max(env(safe-area-inset-top),0.75rem)] backdrop-blur">
      {back ? (
        <button
          aria-label="Volver"
          onClick={() => (window.history.length > 1 ? window.history.back() : navigate({ to: "/" }))}
          className="grid size-11 place-items-center rounded-full bg-card shadow-sm active:scale-95"
        >
          <ArrowLeft className="size-5" />
        </button>
      ) : (
        <span />
      )}
      <h1 className="truncate text-center text-base font-bold">{title}</h1>
      <div className="flex justify-end">{right}</div>
    </header>
  );
}

const studentTabs = [
  { to: "/", label: "Inicio", icon: Home },
  { to: "/explorar", label: "Explorar", icon: Search },
  { to: "/ai", label: "Biffy AI", icon: Sparkles },
  { to: "/perfil", label: "Perfil", icon: User },
] as const;
const courierTabs = [
  { to: "/repartidor", label: "Inicio", icon: Bike },
  { to: "/repartidor/ganancias", label: "Ganancias", icon: Wallet },
  { to: "/perfil", label: "Perfil", icon: User },
] as const;

const merchantTabs = [
  { to: "/empresario", label: "Inicio", icon: Store },
  { to: "/empresario/pedidos", label: "Pedidos", icon: ClipboardList },
  { to: "/empresario/menu", label: "Menú", icon: UtensilsCrossed },
  { to: "/empresario/estadisticas", label: "Estadísticas", icon: BarChart3 },
  { to: "/empresario/perfil", label: "Perfil", icon: User },
] as const;

export function BottomNav() {
  const { mode } = useStore();
  const path = useRouterState({ select: (s) => s.location.pathname });
  const tabs = mode === "courier" ? courierTabs : mode === "merchant" ? merchantTabs : studentTabs;
  return (
    <nav className="fixed inset-x-0 bottom-0 z-40 mx-auto max-w-md border-t bg-card/95 pb-[env(safe-area-inset-bottom)] backdrop-blur">
      <ul className="flex">
        {tabs.map((t) => {
          const active = t.to === "/" || t.to === "/repartidor" || t.to === "/empresario" ? path === t.to : path.startsWith(t.to);
          const Icon = t.icon;
          return (
            <li key={t.to} className="flex-1">
              <Link
                to={t.to}
                className={cn(
                  "flex min-h-16 flex-col items-center justify-center gap-1 text-[11px] font-semibold active:scale-95",
                  active ? "text-primary" : "text-muted-foreground",
                )}
              >
                <Icon className={cn("size-6", active && "fill-primary/15")} />
                {t.label}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}

function CartFab({ withNav }: { withNav: boolean }) {
  const { cart, cartSummary, mode } = useStore();
  const path = useRouterState({ select: (s) => s.location.pathname });
  if (mode !== "student" || cart.length === 0 || path === "/carrito" || path.startsWith("/plato") || path.startsWith("/pedido") || path === "/ai") return null;
  const n = cart.reduce((s, i) => s + i.qty, 0);
  return (
    <Link
      to="/carrito"
      className={(withNav ? "bottom-20 " : "bottom-4 ") + "fixed inset-x-0 z-40 mx-auto flex w-[calc(100%-2rem)] max-w-[calc(28rem-2rem)] items-center justify-between rounded-2xl bg-primary px-4 py-3 text-primary-foreground shadow-lg active:scale-[0.98]"}
    >
      <span className="flex items-center gap-2 font-semibold">
        <ShoppingBag className="size-5" /> Ver carrito · {n}
      </span>
      <span className="font-bold">{cop(cartSummary().total)}</span>
    </Link>
  );
}

export function Carousel({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn("no-scrollbar -mx-4 flex snap-x snap-mandatory gap-3 overflow-x-auto overscroll-x-contain px-4 pb-1", className)}>
      {children}
    </div>
  );
}

export function SectionTitle({ title, action }: { title: string; action?: ReactNode }) {
  return (
    <div className="mb-3 mt-6 flex items-center justify-between">
      <h2 className="text-lg font-bold">{title}</h2>
      {action}
    </div>
  );
}

export function FavButton({ id, className }: { id: string; className?: string }) {
  const { favorites, toggleFavorite, loggedIn } = useStore();
  const navigate = useNavigate();
  const on = favorites.includes(id);
  return (
    <button
      aria-label={on ? "Quitar de favoritos" : "Agregar a favoritos"}
      onClick={(e) => {
        e.preventDefault();
        e.stopPropagation();
        if (!loggedIn) {
          toast("Inicia sesión para guardar favoritos");
          navigate({ to: "/login" });
          return;
        }
        toggleFavorite(id);
        toast(on ? "Quitado de favoritos" : "Guardado en favoritos ❤️");
      }}
      className={cn("grid size-9 place-items-center rounded-full bg-card/90 shadow-sm active:scale-90", className)}
    >
      <Heart className={cn("size-4", on ? "fill-danger text-danger" : "text-muted-foreground")} />
    </button>
  );
}

export function PriceTag({ dish }: { dish: Dish }) {
  const { discountedPrice } = useStore();
  const p = discountedPrice(dish);
  return p < dish.price ? (
    <span className="flex items-baseline gap-1.5">
      <span className="font-bold text-primary">{cop(p)}</span>
      <span className="text-xs text-muted-foreground line-through">{cop(dish.price)}</span>
    </span>
  ) : (
    <span className="font-bold">{cop(dish.price)}</span>
  );
}

export function AllergyBadge({ dish }: { dish: Dish }) {
  const { prefs } = useStore();
  const c = allergyConflicts(dish, prefs.allergies);
  if (!c.length) return null;
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-danger/10 px-2 py-0.5 text-[11px] font-semibold text-danger">
      <AlertTriangle className="size-3" /> Contiene {c.join(", ")}
    </span>
  );
}

export function DishCard({ dish, wide }: { dish: Dish; wide?: boolean }) {
  const { addToCart, loggedIn } = useStore();
  const navigate = useNavigate();
  const r = restaurantById(dish.restaurantId)!;
  return (
    <Link
      to="/plato/$id"
      params={{ id: dish.id }}
      className={cn("relative block snap-start rounded-2xl bg-card p-3 shadow-sm active:scale-[0.98]", wide ? "w-full" : "w-44 shrink-0")}
    >
      <div className="relative grid h-24 place-items-center overflow-hidden rounded-xl bg-accent text-5xl">
        {dish.photo ? <img src={dish.photo} alt={dish.name} loading="lazy" className="absolute inset-0 size-full rounded-xl object-cover" /> : dish.emoji}
        <FavButton id={dish.id} className="absolute right-1.5 top-1.5" />
      </div>
      <p className="mt-2 truncate font-semibold">{dish.name}</p>
      <p className="truncate text-xs text-muted-foreground">{r.name}</p>
      <div className="mt-1"><AllergyBadge dish={dish} /></div>
      <div className="mt-2 flex items-center justify-between">
        <PriceTag dish={dish} />
        <button
          aria-label={"Agregar " + dish.name}
          onClick={(e) => {
            e.preventDefault();
            e.stopPropagation();
            if (dish.options?.length) {
              navigate({ to: "/plato/$id", params: { id: dish.id } });
              return;
            }
            addToCart(dish.id);
            toast.success(`${dish.name} agregado al carrito`);
            void loggedIn;
          }}
          className="grid size-9 place-items-center rounded-full bg-primary text-primary-foreground active:scale-90"
        >
          <Plus className="size-5" />
        </button>
      </div>
    </Link>
  );
}

export function RestaurantCard({ r, wide }: { r: Restaurant; wide?: boolean }) {
  const { point, campusEligible } = useStore();
  const km = distanceKm(r, point);
  return (
    <Link
      to="/restaurante/$id"
      params={{ id: r.id }}
      className={cn("block snap-start rounded-2xl bg-card p-3 shadow-sm active:scale-[0.98]", wide ? "w-full" : "w-64 shrink-0")}
    >
      <div className="flex items-center gap-3">
        <div className="grid size-14 shrink-0 place-items-center rounded-xl bg-accent text-3xl">{r.emoji}</div>
        <div className="min-w-0 flex-1">
          <p className="truncate font-semibold">{r.name}</p>
          <p className="truncate text-xs text-muted-foreground">{r.tagline}</p>
          <p className="mt-1 text-xs font-medium">
            ⭐ {r.rating} · {r.timeMin} min · {km.toFixed(1)} km
          </p>
        </div>
        <FavButton id={r.id} />
      </div>
      {campusEligible(r.id) && (
        <span className="mt-2 inline-block rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-bold text-success">
          🎓 -{Math.round((r.studentDiscount ?? 0) * 100)}% estudiante
        </span>
      )}
    </Link>
  );
}

export function Empty({ emoji, title, body, action }: { emoji: string; title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center px-6 py-12 text-center">
      <div className="text-5xl">{emoji}</div>
      <p className="mt-3 font-bold">{title}</p>
      {body && <p className="mt-1 text-sm text-muted-foreground">{body}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function Chip({ active, children, onClick }: { active?: boolean; children: ReactNode; onClick?: () => void }) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "shrink-0 snap-start rounded-full border px-4 py-2 text-sm font-semibold active:scale-95",
        active ? "border-primary bg-primary text-primary-foreground" : "bg-card text-foreground",
      )}
    >
      {children}
    </button>
  );
}

export function PrimaryButton({ children, className, ...p }: React.ButtonHTMLAttributes<HTMLButtonElement>) {
  return (
    <button
      {...p}
      className={cn(
        "flex min-h-13 w-full items-center justify-center gap-2 rounded-2xl bg-primary px-4 py-3.5 font-bold text-primary-foreground active:scale-[0.98] disabled:opacity-40",
        className,
      )}
    >
      {children}
    </button>
  );
}

/** Simulated map: no external library, SVG route with moving marker. */
export function MockMap({ progress = 0, labelA = "Restaurante", labelB = "Tú", className }: { progress?: number; labelA?: string; labelB?: string; className?: string }) {
  const x = 40 + (260 - 40) * progress;
  const y = 140 - 100 * progress + Math.sin(progress * Math.PI) * -20;
  return (
    <div className={cn("relative overflow-hidden rounded-2xl bg-accent", className)}>
      <svg viewBox="0 0 300 180" className="h-full w-full">
        <defs>
          <pattern id="grid" width="30" height="30" patternUnits="userSpaceOnUse">
            <path d="M30 0H0V30" fill="none" stroke="currentColor" className="text-border" strokeWidth="1" />
          </pattern>
        </defs>
        <rect width="300" height="180" fill="url(#grid)" />
        <path d="M40 140 Q150 60 260 40" fill="none" className="stroke-primary" strokeWidth="4" strokeDasharray="8 6" strokeLinecap="round" />
        <circle cx="40" cy="140" r="9" className="fill-secondary" />
        <circle cx="260" cy="40" r="9" className="fill-success" />
        <circle cx={x} cy={y} r="11" className="fill-primary transition-all duration-1000" />
        <text x={x - 6} y={y + 4} fontSize="11">🛵</text>
      </svg>
      <span className="absolute bottom-2 left-2 rounded-full bg-card px-2 py-0.5 text-[11px] font-semibold">{labelA}</span>
      <span className="absolute right-2 top-2 rounded-full bg-card px-2 py-0.5 text-[11px] font-semibold">{labelB}</span>
    </div>
  );
}
