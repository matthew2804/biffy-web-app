import { createFileRoute, Link } from "@tanstack/react-router";
import { Bell, Search, Gift, GraduationCap, ChevronRight, ClipboardList } from "lucide-react";
import { Screen, Carousel, SectionTitle, DishCard, RestaurantCard, Empty, PrimaryButton } from "@/components/biffy/ui";
import { PointPicker } from "@/components/biffy/point-picker";
import { categories } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { allergyConflicts } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/")({
  head: () => seo("Inicio", "Pide comida cerca de tu universidad con descuentos de estudiante."),
  component: Home,
});

const statusLabel: Record<string, string> = {
  confirmado: "Confirmado",
  preparando: "Preparando",
  en_camino: "En camino",
  programado: "Programado",
};

function Home() {
  const s = useStore();
  const active = s.orders.find((o) => ["confirmado", "preparando", "en_camino", "programado"].includes(o.status));
  const unread = s.notifications.filter((n) => !n.read).length;
  const recommended = s.reachableDishes
    .filter((d) => !allergyConflicts(d, s.prefs.allergies).length)
    .sort((a, b) => Number(s.prefs.likes.includes(b.category)) - Number(s.prefs.likes.includes(a.category)) || Number(!!b.popular) - Number(!!a.popular))
    .slice(0, 8);
  const popular = s.reachableDishes.filter((d) => d.popular);
  const campusRests = s.user?.verified ? s.reachableRestaurants.filter((r) => r.campusId === s.user!.universityId) : [];
  const campusDishes = s.reachableDishes.filter((d) => campusRests.some((r) => r.id === d.restaurantId));
  const topRests = [...s.reachableRestaurants].sort((a, b) => b.rating - a.rating);

  return (
    <Screen>
      <header className="grid grid-cols-[minmax(0,1fr)_auto] items-center gap-3 px-4 pt-[max(env(safe-area-inset-top),1rem)]">
        <PointPicker />
        <div className="flex gap-2">
          <Link to={s.loggedIn ? "/notificaciones" : "/login"} aria-label="Notificaciones" className="relative grid size-11 place-items-center rounded-full bg-card shadow-sm active:scale-95">
            <Bell className="size-5" />
            {s.loggedIn && unread > 0 && <span className="absolute right-1.5 top-1.5 grid size-4 place-items-center rounded-full bg-danger text-[10px] font-bold text-primary-foreground">{unread}</span>}
          </Link>
        </div>
      </header>

      <div className="px-4">
        <h1 className="mt-4 text-2xl font-extrabold">
          {s.user ? `Hola, ${s.user.name.split(" ")[0]} 👋` : "¿Qué se te antoja hoy? 🐝"}
        </h1>
        <Link to="/restaurante/$id" params={{ id: "qbano-icesi" }} className="mt-3 flex items-center gap-3 border-y border-primary/40 py-3 active:opacity-70">
          <span className="text-3xl">🥪</span>
          <span className="min-w-0 flex-1"><b className="block">Qbano en Icesi</b><span className="text-xs text-muted-foreground">Compra de demostración · sin cobros reales</span></span>
          <ChevronRight className="size-5 shrink-0" />
        </Link>
        <Link to="/explorar" className="mt-3 flex items-center gap-2 rounded-2xl bg-card px-4 py-3.5 text-muted-foreground shadow-sm active:scale-[0.99]">
          <Search className="size-5" /> Busca platos o restaurantes
        </Link>

        {s.loggedIn ? (
          <div className="mt-4 grid grid-cols-2 gap-3">
            <Link to="/recompensas" className="rounded-2xl bg-secondary p-4 text-secondary-foreground active:scale-[0.98]">
              <Gift className="size-6" />
              <p className="mt-2 text-xs font-semibold">Recompensas</p>
              <p className="text-xl font-extrabold">{s.points} 💧</p>
            </Link>
            <Link to="/campus" className="rounded-2xl bg-primary p-4 text-primary-foreground active:scale-[0.98]">
              <GraduationCap className="size-6" />
              <p className="mt-2 text-xs font-semibold">Mi campus</p>
              <p className="text-sm font-bold">{s.user?.verified ? "Hasta -20%" : "Verifícate"}</p>
            </Link>
          </div>
        ) : (
          <div className="mt-4 rounded-3xl bg-primary p-5 text-primary-foreground">
            <p className="text-lg font-extrabold">Descuentos de estudiante 🎓</p>
            <p className="mt-1 text-sm opacity-90">Inicia sesión con tu correo universitario y gana 450 Gotas de bienvenida.</p>
            <Link to="/login" className="mt-4 inline-block rounded-xl bg-card px-4 py-2.5 font-bold text-primary active:scale-95">Iniciar sesión</Link>
          </div>
        )}

        {s.loggedIn && !s.surveyDone && (
          <Link to="/encuesta" className="mt-3 flex items-center gap-3 rounded-2xl border-2 border-dashed border-primary/40 bg-card p-3 active:scale-[0.99]">
            <ClipboardList className="size-6 text-primary" />
            <span className="min-w-0 flex-1 text-sm"><b>Completa tus filtros</b> y gana 300 Gotas</span>
            <ChevronRight className="size-5" />
          </Link>
        )}

        {active && (
          <Link to="/pedido/$id" params={{ id: active.id }} className="mt-3 flex items-center gap-3 rounded-2xl bg-card p-4 shadow-sm active:scale-[0.99]">
            <span className="text-3xl">🛵</span>
            <span className="min-w-0 flex-1">
              <span className="block text-xs text-muted-foreground">Pedido {active.id}</span>
              <span className="block font-bold text-success">{statusLabel[active.status]}</span>
            </span>
            <span className="text-sm font-bold text-primary">Ver</span>
          </Link>
        )}

        <SectionTitle title="Categorías" />
        <Carousel>
          {categories.map((c) => (
            <Link key={c.id} to="/explorar" search={{ cat: c.id }} className="flex w-20 shrink-0 snap-start flex-col items-center gap-1 active:scale-95">
              <span className="grid size-16 place-items-center rounded-2xl bg-card text-3xl shadow-sm">{c.emoji}</span>
              <span className="text-xs font-semibold">{c.label}</span>
            </Link>
          ))}
        </Carousel>

        {s.reachableRestaurants.length === 0 ? (
          <Empty
            emoji="📍"
            title="No hay locales que lleguen aquí"
            body="Estás fuera del radio de entrega o no hay repartidores cerca."
            action={<PointPicker trigger={(open) => <PrimaryButton onClick={open}>Cambiar punto de entrega</PrimaryButton>} />}
          />
        ) : (
          <>
            {s.user?.verified && campusRests.length > 0 && (
              <>
                <SectionTitle title={`🎓 Tu campus · ${s.university?.name ?? ""}`} action={<Link to="/campus" className="text-sm font-bold text-primary">Ver todo</Link>} />
                <Carousel>{campusRests.map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>
                {campusDishes.length > 0 && <Carousel className="mt-3">{campusDishes.map((d) => <DishCard key={d.id} dish={d} />)}</Carousel>}
              </>
            )}
            <SectionTitle title={s.loggedIn ? "Recomendado para ti" : "Lo más pedido"} action={<Link to="/ai" className="text-sm font-bold text-primary">Biffy AI ✨</Link>} />
            <Carousel>{(s.loggedIn ? recommended : popular).map((d) => <DishCard key={d.id} dish={d} />)}</Carousel>
            <Carousel className="mt-3">{topRests.map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>

            <SectionTitle title="Restaurantes cerca" action={<Link to="/explorar" className="text-sm font-bold text-primary">Ver todo</Link>} />
            <Carousel>{s.reachableRestaurants.map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>

            <SectionTitle title="Populares en el campus" />
            <div className="grid grid-cols-2 gap-3">{popular.slice(0, 6).map((d) => <DishCard key={d.id} dish={d} wide />)}</div>
          </>
        )}
      </div>
    </Screen>
  );
}
