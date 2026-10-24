import { createFileRoute, Link } from "@tanstack/react-router";
import { Send, Sparkles, ShieldCheck } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Screen, Carousel, Chip, PriceTag } from "@/components/biffy/ui";
import { categories, restaurantById, type Dish } from "@/lib/mock-data";
import { useStore, type Store } from "@/lib/store";
import { allergyConflicts, cop } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/ai")({
  head: () => seo("Biffy AI", "Tu asistente para decidir qué comer según tus gustos, alergias y presupuesto."),
  component: AiPage,
});

type Mode = "gustos" | "rapido" | "economico" | "saludable" | "favoritos" | "sorpresa";
const modes: { id: Mode; label: string }[] = [
  { id: "gustos", label: "❤️ Mis gustos" },
  { id: "rapido", label: "⚡ Rápido" },
  { id: "economico", label: "💸 Económico" },
  { id: "saludable", label: "🥗 Saludable" },
  { id: "favoritos", label: "⭐ Favoritos" },
  { id: "sorpresa", label: "🎲 Sorpréndeme" },
];

function score(d: Dish, s: Store, mode: Mode) {
  const r = restaurantById(d.restaurantId)!;
  const price = s.discountedPrice(d);
  let sc = 55 + r.rating * 4;
  const why: string[] = [];
  if (s.prefs.likes.includes(d.category)) { sc += 12; why.push("te gusta " + d.category); }
  if (price <= s.prefs.budget) { sc += 8; why.push("dentro de tu presupuesto"); }
  if (s.prefs.lifestyle.some((l) => d.tags.includes(l))) { sc += 8; why.push("va con tu estilo de vida"); }
  if (s.campusEligible(r.id)) { sc += 4; why.push("descuento de campus"); }
  if (mode === "rapido") sc += 25 - r.timeMin;
  if (mode === "economico") sc += (25000 - price) / 1000;
  if (mode === "saludable") sc += d.category === "saludable" || (d.calories > 0 && d.calories < 600) ? 15 : -15;
  if (mode === "favoritos") sc += s.favorites.includes(d.id) || s.favorites.includes(r.id) ? 20 : -10;
  if (mode === "sorpresa") sc += Math.random() * 30 - 10;
  const h = new Date().getHours();
  if (h < 11 && d.category === "cafe") { sc += 6; why.push("ideal para la mañana"); }
  if (h >= 11 && h < 15 && d.category === "almuerzo") { sc += 6; why.push("hora de almuerzo"); }
  return { d, pct: Math.max(40, Math.min(99, Math.round(sc))), why };
}

type Msg = { role: "user" | "ai"; text: string; dishes?: Dish[] };

function answer(text: string, s: Store): Msg {
  const t = text.toLowerCase();
  const pool = s.reachableDishes.filter((d) => !allergyConflicts(d, s.prefs.allergies).length);
  const asked = s.reachableDishes.find((d) => t.includes(d.name.toLowerCase()) || t.includes(d.name.toLowerCase().split(" ")[0] + " " + (d.name.toLowerCase().split(" ")[1] ?? "")));
  if (asked && /(contiene|ingrediente|lleva|tiene|alerg)/.test(t)) {
    const c = allergyConflicts(asked, s.prefs.allergies);
    return { role: "ai", text: `${asked.name}: ${asked.description} Alérgenos: ${asked.allergens.join(", ") || "ninguno"}. ${asked.calories > 0 ? asked.calories + " kcal." : "Información nutricional no disponible."} Precio ${cop(s.discountedPrice(asked))}.${c.length ? ` ⚠️ Contiene ${c.join(", ")}, que marcaste como alergia.` : " ✅ Compatible con tus alergias."}`, dishes: [asked] };
  }
  if (t.includes("qbano")) {
    const order = ["qbano-especial", "qbano-pollo", "qbano-vegetariano"];
    const q = order.map((id) => s.reachableDishes.find((d) => d.id === id)).filter((d): d is Dish => !!d);
    if (q.length) return { role: "ai", text: `Estas son las ${q.length} mejores opciones de Qbano para ti en Icesi 🥪 (llegan en ~8 min):`, dishes: q };
  }
  let list = pool;
  const requestedRestaurant = s.reachableRestaurants.find((r) => t.includes(r.name.toLowerCase().split(" · ")[0] ?? r.name.toLowerCase()));
  if (requestedRestaurant) list = list.filter((d) => d.restaurantId === requestedRestaurant.id);
  const cat = categories.find((c) => t.includes(c.id) || t.includes(c.label.toLowerCase().slice(0, -1)) || t.includes(c.label.toLowerCase()));
  if (cat) list = list.filter((d) => d.category === cat.id);
  for (const tag of ["vegano", "vegetariano", "sin gluten", "picante", "proteína"]) if (t.includes(tag)) list = list.filter((d) => d.tags.some((x) => x.includes(tag)));
  const num = t.match(/(\d+)\s*(mil|k)?/);
  let max: number | undefined;
  if (num) max = Number(num[1]) * (num[2] || Number(num[1]) < 1000 ? 1000 : 1);
  if (/(barat|económ|economic)/.test(t)) max = max ?? 15000;
  if (max) list = list.filter((d) => s.discountedPrice(d) <= max!);
  if (/(saludable|light|ligero)/.test(t)) list = list.filter((d) => d.category === "saludable" || (d.calories > 0 && d.calories < 600));
  const ranked = list.map((d) => score(d, s, "gustos")).sort((a, b) => b.pct - a.pct).slice(0, 4).map((x) => x.d);
  if (!ranked.length) return { role: "ai", text: "No encontré opciones con eso cerca de ti 😕. Prueba subir el presupuesto o cambiar de categoría." };
  return { role: "ai", text: `Encontré ${ranked.length} opciones${max ? ` por menos de ${cop(max)}` : ""}, ordenadas por compatibilidad contigo:`, dishes: ranked };
}

function AiPage() {
  const s = useStore();
  const [mode, setMode] = useState<Mode>("gustos");
  const [seed, setSeed] = useState(0);
  const [msgs, setMsgs] = useState<Msg[]>([{ role: "ai", text: "¡Hola! Soy Biffy AI 🐝. Dime qué se te antoja, tu presupuesto o pregúntame qué contiene un plato." }]);
  const [input, setInput] = useState("");
  const [typing, setTyping] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  useEffect(() => {
    end.current?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  }, [msgs, typing]);

  const top3 = s.reachableDishes
    .filter((d) => !allergyConflicts(d, s.prefs.allergies).length)
    .map((d) => score(d, s, mode))
    .sort((a, b) => b.pct - a.pct)
    .slice(0, 3);
  void seed;

  const send = (text: string) => {
    if (!text.trim()) return;
    setMsgs((m) => [...m, { role: "user", text }]);
    setInput("");
    setTyping(true);
    setTimeout(() => { setMsgs((m) => [...m, answer(text, s)]); setTyping(false); }, 700);
  };

  return (
    <Screen>
      <div className="px-4 pt-[max(env(safe-area-inset-top),1rem)]">
        <h1 className="flex items-center gap-2 text-2xl font-extrabold"><Sparkles className="text-primary" /> Biffy AI</h1>
        <p className="text-sm text-muted-foreground">Decido contigo según {s.surveyDone ? "tus filtros" : "lo más popular"}, la hora y tu presupuesto.</p>
        {!s.surveyDone && s.loggedIn && <Link to="/encuesta" className="mt-2 block rounded-xl bg-secondary/25 p-2 text-sm font-semibold">Completa tus filtros para mejores recomendaciones (+300 💧)</Link>}
        <Carousel className="mt-3">{modes.map((m) => <Chip key={m.id} active={mode === m.id} onClick={() => { setMode(m.id); setSeed((x) => x + 1); }}>{m.label}</Chip>)}</Carousel>

        <h2 className="mb-2 mt-4 font-bold">Tus 3 mejores opciones</h2>
        <div className="space-y-2">
          {top3.map(({ d, pct, why }, i) => (
            <div key={d.id} className="flex gap-3 rounded-2xl bg-card p-3 shadow-sm">
              <div className="grid size-14 shrink-0 place-items-center rounded-xl bg-accent text-3xl">{d.emoji}</div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center justify-between gap-2"><p className="truncate font-semibold">{i + 1}. {d.name}</p><span className="shrink-0 rounded-full bg-success/15 px-2 py-0.5 text-xs font-bold text-success">{pct}% match</span></div>
                <p className="truncate text-xs text-muted-foreground">{restaurantById(d.restaurantId)?.name} · {why.slice(0, 2).join(", ") || "muy popular"}</p>
                <div className="mt-1 flex items-center justify-between">
                  <PriceTag dish={d} />
                  <Link to="/plato/$id" params={{ id: d.id }} className="rounded-full bg-primary px-3 py-1.5 text-xs font-bold text-primary-foreground active:scale-95">Pedir</Link>
                </div>
              </div>
            </div>
          ))}
          {!top3.length && <p className="text-sm text-muted-foreground">No hay opciones en tu zona.</p>}
        </div>
        <button onClick={() => { setMode("sorpresa"); setSeed((x) => x + 1); toast("Nuevas sugerencias 🎲"); }} className="mt-2 w-full rounded-xl bg-muted py-2.5 text-sm font-semibold active:scale-95">Otra sugerencia</button>

        <h2 className="mb-2 mt-5 font-bold">Chat</h2>
        <div className="space-y-2 rounded-2xl bg-card p-3 shadow-sm">
          {msgs.map((m, i) => (
            <div key={i} className={m.role === "user" ? "ml-10 rounded-2xl rounded-br-sm bg-primary p-3 text-sm text-primary-foreground" : "mr-6 rounded-2xl rounded-bl-sm bg-muted p-3 text-sm"}>
              {m.text}
              {m.dishes && (
                <div className="mt-2 space-y-1.5">
                  {m.dishes.map((d, k) => (
                    <Link key={d.id} to="/plato/$id" params={{ id: d.id }} className="flex items-center gap-2 rounded-xl bg-card p-2 active:scale-[0.99]">
                      <span className="text-xs font-bold text-primary">#{k + 1}</span><span className="text-xl">{d.emoji}</span>
                      <span className="min-w-0 flex-1 truncate font-semibold">{d.name}</span><span className="text-xs font-bold">{cop(s.discountedPrice(d))}</span>
                    </Link>
                  ))}
                  <p className="flex items-center gap-1 text-[11px] text-muted-foreground"><ShieldCheck className="size-3" /> Filtrado según tus alergias. Confirma siempre con el restaurante.</p>
                </div>
              )}
            </div>
          ))}
          {typing && <div className="mr-6 w-16 rounded-2xl bg-muted p-3 text-center text-sm">•••</div>}
          <div ref={end} />
        </div>
        <Carousel className="mt-2">
          {(s.pointId.startsWith("icesi-") ? ["Qbano", "¿Qué contiene el Qbano Especial?"] : ["Algo barato menos de 15 mil", "Pizza vegetariana", "¿Qué contiene el Bowl Proteico?", "Algo saludable"]).map((x) => <Chip key={x} onClick={() => send(x)}>{x}</Chip>)}
        </Carousel>
      </div>
      <form onSubmit={(e) => { e.preventDefault(); send(input); }} className="fixed inset-x-0 bottom-[4.25rem] z-30 mx-auto flex max-w-md gap-2 border-t bg-background p-3">
        <input value={input} onChange={(e) => setInput(e.target.value)} placeholder="Describe lo que buscas…" className="min-w-0 flex-1 rounded-2xl border bg-card px-4 py-3 outline-none focus:border-primary" />
        <button aria-label="Enviar" className="grid size-12 place-items-center rounded-2xl bg-primary text-primary-foreground active:scale-95"><Send className="size-5" /></button>
      </form>
      <div className="h-20" />
    </Screen>
  );
}
