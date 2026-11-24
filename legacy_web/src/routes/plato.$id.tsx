import { createFileRoute, Link, notFound, useNavigate } from "@tanstack/react-router";
import { Minus, Plus, Share2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, FavButton, PrimaryButton, AllergyBadge, PriceTag } from "@/components/biffy/ui";
import { dishById, restaurantById } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { cop, isReachable } from "@/lib/format";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/plato/$id")({
  loader: ({ params }) => {
    const dish = dishById(params.id);
    if (!dish) throw notFound();
    return { dish };
  },
  head: ({ loaderData }) => ({
    meta: loaderData
      ? [
          { title: `${loaderData.dish.name} · Biffy` },
          { name: "description", content: loaderData.dish.description },
          { property: "og:title", content: `${loaderData.dish.name} · Biffy` },
          { property: "og:description", content: loaderData.dish.description },
          { property: "og:type", content: "website" },
          { name: "twitter:card", content: "summary" },
        ]
      : [{ title: "Plato no encontrado · Biffy" }, { name: "robots", content: "noindex" }],
  }),
  notFoundComponent: () => <div className="p-10 text-center">Plato no encontrado. <Link to="/" className="text-primary">Volver</Link></div>,
  component: DishPage,
});

function DishPage() {
  const { dish } = Route.useLoaderData();
  const s = useStore();
  const navigate = useNavigate();
  const r = restaurantById(dish.restaurantId)!;
  const [qty, setQty] = useState(1);
  const [opts, setOpts] = useState<string[]>([]);
  const [note, setNote] = useState("");
  const reachable = isReachable(r, s.point);
  const unit = s.unitPrice(dish, opts);
  const discounted = s.campusEligible(r.id) ? Math.round(unit * (1 - (r.studentDiscount ?? 0))) : unit;

  const share = async () => {
    const url = window.location.href;
    if (navigator.share) await navigator.share({ title: dish.name, url }).catch(() => {});
    else { await navigator.clipboard.writeText(url); toast("Enlace copiado"); }
  };

  return (
    <Screen nav={false} className="pb-32">
      <TopBar title={r.name} right={<button aria-label="Compartir" onClick={share} className="grid size-11 place-items-center rounded-full bg-card shadow-sm active:scale-95"><Share2 className="size-5" /></button>} />
      <div className="px-4">
        <div className="relative grid h-56 place-items-center overflow-hidden rounded-3xl bg-accent text-8xl">
          {dish.photo ? <img src={dish.photo} alt={dish.name} className="absolute inset-0 size-full rounded-3xl object-cover" /> : dish.emoji}
          <FavButton id={dish.id} className="absolute right-3 top-3 size-11" />
        </div>
        <h1 className="mt-4 text-2xl font-extrabold">{dish.name}</h1>
        <Link to="/restaurante/$id" params={{ id: r.id }} className="text-sm font-semibold text-primary">{r.name} · ⭐ {r.rating}</Link>
        <p className="mt-2 text-muted-foreground">{dish.description}</p>
        <div className="mt-3 flex flex-wrap gap-2">
          <PriceTag dish={dish} />
          {dish.calories > 0 && <span className="text-xs text-muted-foreground">· {dish.calories} kcal</span>}
          {dish.tags.map((t) => <span key={t} className="rounded-full bg-success/15 px-2 py-0.5 text-[11px] font-semibold text-success">{t}</span>)}
        </div>
        <div className="mt-2"><AllergyBadge dish={dish} /></div>
        {dish.allergens.length > 0 && <p className="mt-2 text-xs text-muted-foreground">Alérgenos: {dish.allergens.join(", ")}</p>}

        {dish.nutrition && r.showsNutrition && (
          <div className="mt-4 rounded-2xl bg-card p-4 shadow-sm">
            <p className="text-sm font-bold">🥦 Información nutricional · porción</p>
            <div className="mt-2 grid grid-cols-4 gap-2 text-center">
              {([["Calorías", dish.nutrition.kcal, "kcal"], ["Proteína", dish.nutrition.protein, "g"], ["Carbos", dish.nutrition.carbs, "g"], ["Grasas", dish.nutrition.fat, "g"]] as const).map(([l, v, u]) => (
                <div key={l} className="rounded-xl bg-accent p-2"><p className="font-extrabold">{v}<span className="text-[10px]"> {u}</span></p><p className="text-[11px] text-muted-foreground">{l}</p></div>
              ))}
            </div>
            <p className="mt-2 text-[11px] text-muted-foreground">Datos reportados por el restaurante.</p>
          </div>
        )}

        {dish.options && (
          <div className="mt-6">
            <h2 className="font-bold">Personaliza</h2>
            <div className="mt-2 space-y-2">
              {dish.options.map((o) => {
                const on = opts.includes(o.id);
                return (
                  <button key={o.id} onClick={() => setOpts((x) => (on ? x.filter((y) => y !== o.id) : [...x, o.id]))} className={cn("flex w-full items-center justify-between rounded-2xl border bg-card p-4 active:scale-[0.99]", on && "border-primary")}>
                    <span className="flex items-center gap-3">
                      <span className={cn("grid size-5 place-items-center rounded-md border-2", on && "border-primary bg-primary text-primary-foreground")}>{on && "✓"}</span>
                      {o.label}
                    </span>
                    <span className="font-semibold">+{cop(o.price)}</span>
                  </button>
                );
              })}
            </div>
          </div>
        )}

        <h2 className="mt-6 font-bold">Nota para el restaurante</h2>
        <textarea value={note} onChange={(e) => setNote(e.target.value)} placeholder="Ej: sin cebolla" className="mt-2 w-full rounded-2xl border bg-card p-3 outline-none focus:border-primary" rows={2} />
      </div>

      <div className="fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-md items-center gap-3 border-t bg-card p-4 pb-[max(env(safe-area-inset-bottom),1rem)]">
        <div className="flex items-center gap-3 rounded-2xl bg-muted px-2">
          <button aria-label="Menos" onClick={() => setQty((q) => Math.max(1, q - 1))} className="grid size-11 place-items-center active:scale-90"><Minus className="size-5" /></button>
          <span className="w-5 text-center font-bold">{qty}</span>
          <button aria-label="Más" onClick={() => setQty((q) => q + 1)} className="grid size-11 place-items-center active:scale-90"><Plus className="size-5" /></button>
        </div>
        <PrimaryButton
          disabled={!reachable}
          onClick={() => {
            s.addToCart(dish.id, qty, opts, note.trim());
            toast.success("Agregado al carrito", { action: { label: "Ver", onClick: () => navigate({ to: "/carrito" }) } });
            navigate({ to: "/restaurante/$id", params: { id: r.id } });
          }}
        >
          {reachable ? `Agregar · ${cop(discounted * qty)}` : "Fuera de tu zona"}
        </PrimaryButton>
      </div>
    </Screen>
  );
}
