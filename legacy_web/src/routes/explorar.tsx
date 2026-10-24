import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Mic, Search, SlidersHorizontal, X } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { z } from "zod";
import { Screen, Carousel, Chip, DishCard, RestaurantCard, SectionTitle, Empty, PrimaryButton } from "@/components/biffy/ui";
import { PointPicker } from "@/components/biffy/point-picker";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { Slider } from "@/components/ui/slider";
import { categories, restaurantById, lifestyleOptions } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { allergyConflicts, cop, isOpenNow } from "@/lib/format";
import { seo } from "@/lib/seo";

const searchSchema = z.object({ cat: z.string().optional(), q: z.string().optional(), campus: z.boolean().optional() });

export const Route = createFileRoute("/explorar")({
  validateSearch: (s: Record<string, unknown>): { cat?: string | undefined; q?: string | undefined; campus?: boolean | undefined } => searchSchema.parse(s),
  head: () => seo("Explorar", "Busca platos y restaurantes, filtra por categoría, precio y dieta."),
  component: Explorar,
});

type Quick = "rapido" | "barato" | "top" | "abierto" | "seguro";
const quick: { id: Quick; label: string }[] = [
  { id: "rapido", label: "⚡ < 15 min" },
  { id: "barato", label: "💸 < $15.000" },
  { id: "top", label: "⭐ 4.7+" },
  { id: "abierto", label: "🟢 Abierto" },
  { id: "seguro", label: "🛡️ Sin mis alérgenos" },
];

function Explorar() {
  const s = useStore();
  const search = Route.useSearch();
  const navigate = useNavigate({ from: "/explorar" });
  const [q, setQ] = useState(search.q ?? "");
  const [quicks, setQuicks] = useState<Quick[]>([]);
  const [open, setOpen] = useState(false);
  const [maxPrice, setMaxPrice] = useState(40000);
  const [diets, setDiets] = useState<string[]>([]);
  const cat = search.cat;

  const toggleQuick = (id: Quick) => setQuicks((x) => (x.includes(id) ? x.filter((y) => y !== id) : [...x, id]));

  const results = useMemo(() => {
    const t = q.trim().toLowerCase();
    return s.reachableDishes.filter((d) => {
      const r = restaurantById(d.restaurantId)!;
      if (cat && d.category !== cat) return false;
      if (search.campus && !s.campusEligible(r.id)) return false;
      if (t && !(d.name + " " + d.description + " " + r.name + " " + d.category + " " + d.tags.join(" ")).toLowerCase().includes(t)) return false;
      if (s.discountedPrice(d) > maxPrice) return false;
      if (diets.length && !diets.every((x) => d.tags.includes(x))) return false;
      for (const k of quicks) {
        if (k === "rapido" && r.timeMin >= 15) return false;
        if (k === "barato" && s.discountedPrice(d) >= 15000) return false;
        if (k === "top" && r.rating < 4.7) return false;
        if (k === "abierto" && !isOpenNow(r)) return false;
        if (k === "seguro" && allergyConflicts(d, s.prefs.allergies).length) return false;
      }
      return true;
    });
  }, [q, cat, quicks, maxPrice, diets, s, search.campus]);

  const restResults = useMemo(() => {
    const ids = new Set(results.map((d) => d.restaurantId));
    const t = q.trim().toLowerCase();
    return s.reachableRestaurants.filter((r) => ids.has(r.id) || (t && r.name.toLowerCase().includes(t)));
  }, [results, q, s.reachableRestaurants]);

  const filtering = !!(q || cat || quicks.length || diets.length || maxPrice < 40000 || search.campus);
  const activeFilters = (diets.length ? 1 : 0) + (maxPrice < 40000 ? 1 : 0);

  const voice = (): void => {
    type SR = new () => { lang: string; start: () => void; onresult: (e: { results: { 0: { 0: { transcript: string } } } }) => void };
    const w = window as unknown as { SpeechRecognition?: SR; webkitSpeechRecognition?: SR };
    const Ctor = w.SpeechRecognition ?? w.webkitSpeechRecognition;
    if (!Ctor) { toast("Búsqueda por voz no disponible en este dispositivo"); return; }
    const rec = new Ctor();
    rec.lang = "es-CO";
    rec.onresult = (e) => setQ(e.results[0][0].transcript);
    rec.start();
    toast("Escuchando… 🎙️");
  };

  return (
    <Screen>
      <div className="sticky top-0 z-30 bg-background px-4 pb-3 pt-[max(env(safe-area-inset-top),1rem)]">
        <div className="mb-3 flex items-center justify-between">
          <h1 className="text-2xl font-extrabold">Explorar</h1>
          <PointPicker />
        </div>
        <div className="flex gap-2">
          <label className="flex min-w-0 flex-1 items-center gap-2 rounded-2xl bg-card px-3 shadow-sm">
            <Search className="size-5 shrink-0 text-muted-foreground" />
            <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Pizza, bowl, Burger Lab…" className="min-w-0 flex-1 bg-transparent py-3.5 outline-none" enterKeyHint="search" />
            {q ? (
              <button aria-label="Borrar" onClick={() => setQ("")}><X className="size-5" /></button>
            ) : (
              <button aria-label="Buscar por voz" onClick={voice}><Mic className="size-5 text-primary" /></button>
            )}
          </label>
          <button aria-label="Filtros" onClick={() => setOpen(true)} className="relative grid size-13 place-items-center rounded-2xl bg-primary text-primary-foreground active:scale-95">
            <SlidersHorizontal className="size-5" />
            {activeFilters > 0 && <span className="absolute -right-1 -top-1 grid size-5 place-items-center rounded-full bg-secondary text-[11px] font-bold text-secondary-foreground">{activeFilters}</span>}
          </button>
        </div>
        <Carousel className="mt-3">
          {s.user?.verified && <Chip active={!!search.campus} onClick={() => navigate({ search: (p) => ({ ...p, campus: p.campus ? undefined : true }) })}>🎓 Mi campus</Chip>}
          <Chip onClick={() => void navigate({ to: "/nutricion" })}>🥦 Calorías y nutrientes</Chip>
          {quick.map((x) => <Chip key={x.id} active={quicks.includes(x.id)} onClick={() => toggleQuick(x.id)}>{x.label}</Chip>)}
        </Carousel>
      </div>

      <div className="px-4">
        <Carousel>
          {categories.map((c) => (
            <button
              key={c.id}
              onClick={() => navigate({ search: (p) => ({ ...p, cat: p.cat === c.id ? undefined : c.id }) })}
              className={"flex w-20 shrink-0 snap-start flex-col items-center gap-1 active:scale-95 " + (cat === c.id ? "text-primary" : "")}
            >
              <span className={"grid size-16 place-items-center rounded-2xl text-3xl shadow-sm " + (cat === c.id ? "bg-primary/15 ring-2 ring-primary" : "bg-card")}>{c.emoji}</span>
              <span className="text-xs font-semibold">{c.label}</span>
            </button>
          ))}
        </Carousel>

        {filtering ? (
          <>
            <SectionTitle
              title={`${results.length} plato${results.length === 1 ? "" : "s"} · ${restResults.length} restaurante${restResults.length === 1 ? "" : "s"}`}
              action={<button className="text-sm font-bold text-primary" onClick={() => { setQ(""); setQuicks([]); setDiets([]); setMaxPrice(40000); navigate({ search: {} }); }}>Limpiar</button>}
            />
            {restResults.length > 0 && <Carousel className="mb-4">{restResults.map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>}
            {results.length ? (
              <div className="grid grid-cols-2 gap-3">{results.map((d) => <DishCard key={d.id} dish={d} wide />)}</div>
            ) : (
              <Empty emoji="🔍" title="Sin resultados" body="Prueba con otra palabra, quita filtros o cambia tu punto de entrega." />
            )}
          </>
        ) : (
          <>
            <SectionTitle title="Tendencia en el campus 🔥" />
            <Carousel>{s.reachableDishes.filter((d) => d.popular).map((d) => <DishCard key={d.id} dish={d} />)}</Carousel>
            <Carousel className="mt-3">{[...s.reachableRestaurants].sort((a, b) => b.rating - a.rating).map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>
            <SectionTitle title="Todos los restaurantes" />
            <div className="space-y-3">{s.reachableRestaurants.map((r) => <RestaurantCard key={r.id} r={r} wide />)}</div>
            {s.reachableRestaurants.length === 0 && <Empty emoji="📍" title="Nada disponible en tu zona" body="Cambia el punto de entrega para ver opciones." />}
          </>
        )}
      </div>

      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="bottom" className="mx-auto max-w-md rounded-t-3xl">
          <SheetHeader><SheetTitle>Filtros</SheetTitle></SheetHeader>
          <div className="space-y-6 p-4">
            <div>
              <p className="mb-3 font-semibold">Precio máximo: {cop(maxPrice)}</p>
              <Slider min={5000} max={40000} step={1000} value={[maxPrice]} onValueChange={(v) => setMaxPrice(v[0] ?? maxPrice)} />
            </div>
            <div>
              <p className="mb-3 font-semibold">Estilo de vida</p>
              <div className="flex flex-wrap gap-2">
                {lifestyleOptions.map((x) => (
                  <Chip key={x} active={diets.includes(x)} onClick={() => setDiets((d) => (d.includes(x) ? d.filter((y) => y !== x) : [...d, x]))}>{x}</Chip>
                ))}
              </div>
            </div>
            <PrimaryButton onClick={() => setOpen(false)}>Ver {results.length} resultados</PrimaryButton>
          </div>
        </SheetContent>
      </Sheet>
    </Screen>
  );
}
