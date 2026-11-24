import { createFileRoute, Link, notFound } from "@tanstack/react-router";
import { Users, Clock, MapPin, Share2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, FavButton, Chip, Carousel, DishCard, Empty } from "@/components/biffy/ui";
import { dishes, restaurantById } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { distanceKm, isOpenNow, isReachable } from "@/lib/format";

export const Route = createFileRoute("/restaurante/$id")({
  loader: ({ params }) => {
    const r = restaurantById(params.id);
    if (!r) throw notFound();
    return { r };
  },
  head: ({ loaderData }) => ({
    meta: loaderData
      ? [
          { title: `${loaderData.r.name} · Biffy` },
          { name: "description", content: loaderData.r.tagline },
          { property: "og:title", content: `${loaderData.r.name} · Biffy` },
          { property: "og:description", content: loaderData.r.tagline },
          { property: "og:type", content: "website" },
          { name: "twitter:card", content: "summary" },
        ]
      : [{ title: "Restaurante no encontrado · Biffy" }, { name: "robots", content: "noindex" }],
  }),
  notFoundComponent: () => <div className="p-10 text-center">Restaurante no encontrado. <Link to="/" className="text-primary">Volver</Link></div>,
  component: RestaurantPage,
});

function RestaurantPage() {
  const { r } = Route.useLoaderData();
  const s = useStore();
  const menu = dishes.filter((d) => d.restaurantId === r.id);
  const sections = [...new Set(menu.map((d) => d.section))];
  const [sec, setSec] = useState<string | null>(null);
  const reachable = isReachable(r, s.point);
  const open = isOpenNow(r);

  const groupOrder = async () => {
    const url = `${window.location.origin}/restaurante/${r.id}?grupo=${Math.random().toString(36).slice(2, 7)}`;
    if (navigator.share) await navigator.share({ title: `Pedido grupal en ${r.name}`, url }).catch(() => {});
    else { await navigator.clipboard.writeText(url); }
    toast.success("Enlace de pedido grupal copiado. Compártelo con tus amigos 👥");
  };

  return (
    <Screen nav={false} className="pb-28">
      <TopBar title={r.name} right={<FavButton id={r.id} className="size-11" />} />
      <div className="px-4">
        <div className="grid h-40 place-items-center rounded-3xl bg-primary text-7xl">{r.emoji}</div>
        <h1 className="mt-4 text-2xl font-extrabold">{r.name}</h1>
        <p className="text-muted-foreground">{r.tagline}</p>
        {r.demo && <p className="mt-2 border-y py-2 text-xs text-muted-foreground">Demostración sin cobros ni entregas reales. Sede, menú, foto, precios y horarios ilustrativos, no oficiales.</p>}
        <div className="mt-3 flex flex-wrap gap-3 text-sm font-medium">
          <span>⭐ {r.rating}</span>
          <span className="flex items-center gap-1"><Clock className="size-4" /> {r.timeMin} min</span>
          <span className="flex items-center gap-1"><MapPin className="size-4" /> {distanceKm(r, s.point).toFixed(1)} km</span>
          <span className={open ? "text-success" : "text-danger"}>{open ? "Abierto" : `Cerrado · abre ${r.open}:00`}</span>
        </div>
        <p className="mt-1 text-xs text-muted-foreground">{r.place} · Horario {r.open}:00–{r.close}:00</p>
        {s.campusEligible(r.id) && !!r.studentDiscount && <p className="mt-2 rounded-xl bg-success/15 p-2 text-sm font-semibold text-success">🎓 Tienes {Math.round((r.studentDiscount ?? 0) * 100)}% de descuento de campus</p>}
        {r.campusId && !s.campusEligible(r.id) && <Link to="/campus" className="mt-2 block rounded-xl bg-accent p-2 text-sm font-semibold text-accent-foreground">🎓 Local de campus: verifica tu universidad para obtener descuento</Link>}
        {!reachable && <p className="mt-2 rounded-xl bg-danger/10 p-2 text-sm font-semibold text-danger">Este local no entrega en {s.point.name}.</p>}
        {!open && reachable && <p className="mt-2 rounded-xl bg-secondary/20 p-2 text-sm font-semibold">Puedes programar tu pedido para cuando abra.</p>}

        <div className="mt-4 grid grid-cols-2 gap-2">
          <button onClick={groupOrder} className="flex items-center justify-center gap-2 rounded-2xl bg-card p-3 font-semibold shadow-sm active:scale-95"><Users className="size-5" /> Pedido grupal</button>
          <button onClick={async () => { await navigator.clipboard.writeText(window.location.href); toast("Enlace copiado"); }} className="flex items-center justify-center gap-2 rounded-2xl bg-card p-3 font-semibold shadow-sm active:scale-95"><Share2 className="size-5" /> Compartir</button>
        </div>

        <Carousel className="sticky top-16 z-20 mt-4 bg-background py-2">
          <Chip active={!sec} onClick={() => setSec(null)}>Todo</Chip>
          {sections.map((x) => <Chip key={x} active={sec === x} onClick={() => setSec(x)}>{x}</Chip>)}
        </Carousel>
        {sections.filter((x) => !sec || x === sec).map((x) => (
          <div key={x}>
            <h2 className="mb-2 mt-4 font-bold">{x}</h2>
            <div className="grid grid-cols-2 gap-3">{menu.filter((d) => d.section === x).map((d) => <DishCard key={d.id} dish={d} wide />)}</div>
          </div>
        ))}
        {!menu.length && <Empty emoji="🍽️" title="Menú no disponible" />}
      </div>
    </Screen>
  );
}
