import { createFileRoute, Link } from "@tanstack/react-router";
import { Phone, MessageCircle, Camera, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Screen, MockMap, PrimaryButton, Empty } from "@/components/biffy/ui";
import { Switch } from "@/components/ui/switch";
import { Progress } from "@/components/ui/progress";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/repartidor/")({
  head: () => seo("Modo repartidor", "Recibe ofertas cerca de ti y gana entregando en tu ciudad o en tu campus."),
  component: Courier,
});

type Offer = { id: string; restaurant: string; pickup: string; dropoff: string; client: string; km: number; min: number; pay: number; payment: string; items: string; note: string; pickupCode: string; clientCode: string; zone: "general" | "campus"; campusId?: string };
const offers: Offer[] = [
  { id: "of1", restaurant: "La Plazoleta Pizza", pickup: "Plazoleta B · Local 12", dropoff: "Biblioteca Central", client: "Sofía", km: 0.8, min: 12, pay: 7800, payment: "Nequi (pagado)", items: "2 productos · Bolsa mediana", note: "Estoy en las bancas junto al ascensor", pickupCode: "8492", clientCode: "4821", zone: "campus", campusId: "unal" },
  { id: "of2", restaurant: "Verde Bowl", pickup: "Ingeniería · Cafetería", dropoff: "Plazoleta Che", client: "Mateo", km: 1.3, min: 14, pay: 6900, payment: "Efectivo · cobrar $22.000", items: "1 producto · Bolsa pequeña", note: "Camiseta azul", pickupCode: "3310", clientCode: "7755", zone: "campus", campusId: "unal" },
  { id: "of3", restaurant: "Café Enjambre", pickup: "Biblioteca · Piso 1", dropoff: "Edificio Ingeniería", client: "Valentina", km: 0.5, min: 8, pay: 5200, payment: "Tarjeta (pagado)", items: "3 productos · Bolsa pequeña", note: "Salón 302", pickupCode: "1188", clientCode: "2468", zone: "campus", campusId: "unal" },
  { id: "of4", restaurant: "Burger Station", pickup: "Cra. 7 #45-12", dropoff: "Calle 53 #10-20, Apto 301", client: "Andrés", km: 2.4, min: 18, pay: 9500, payment: "Nequi (pagado)", items: "2 productos · Bolsa mediana", note: "Portería, preguntar por Andrés", pickupCode: "5521", clientCode: "9034", zone: "general" },
  { id: "of5", restaurant: "Tacos El Parche", pickup: "Calle 63 #9-40", dropoff: "Parque de los Hippies", client: "Laura", km: 1.9, min: 15, pay: 8200, payment: "Efectivo · cobrar $31.000", items: "3 productos · Bolsa grande", note: "Chaqueta roja", pickupCode: "6610", clientCode: "1357", zone: "general" },
];
offers.push({ id: "of6", restaurant: "Wok Express", pickup: "Cl 53 #13-40 · Uniandes", dropoff: "Edificio ML", client: "Camila", km: 0.6, min: 9, pay: 5600, payment: "Nequi (pagado)", items: "1 producto · Bolsa pequeña", note: "Entrada del ML", pickupCode: "3307", clientCode: "6612", zone: "campus", campusId: "andes" });
const goals = [10, 25, 50];

function Courier() {
  const s = useStore();
  const [phase, setPhase] = useState<"home" | "offer" | "pickup" | "deliver">("home");
  const [offer, setOffer] = useState<Offer | null>(null);
  const [left, setLeft] = useState(18);
  const [checks, setChecks] = useState<boolean[]>([false, false, false]);
  const [code, setCode] = useState("");
  const [photo, setPhoto] = useState<string | null>(null);
  const [progress, setProgress] = useState(0);
  const [declined, setDeclined] = useState<string[]>([]);

  const zone = s.courier.zone;
  const zoneOffers = offers.filter((o) => o.zone === zone && (zone === "general" || o.campusId === s.user?.universityId));
  const canCampus = !!s.user?.verified;

  // Simulated incoming offer when online
  useEffect(() => {
    if (!s.courier.online || phase !== "home") return;
    const t = setTimeout(() => {
      const next = zoneOffers.find((o) => !declined.includes(o.id)) ?? zoneOffers[0]!;
      setOffer(next); setLeft(18); setPhase("offer");
    }, 5000);
    return () => clearTimeout(t);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [s.courier.online, phase, declined, zone]);

  useEffect(() => {
    if (phase !== "offer") return;
    if (left <= 0) { toast("La oferta expiró"); setPhase("home"); return; }
    const t = setTimeout(() => setLeft((x) => x - 1), 1000);
    return () => clearTimeout(t);
  }, [phase, left]);

  useEffect(() => {
    if (phase !== "deliver") return;
    const t = setInterval(() => setProgress((p) => Math.min(1, p + 0.1)), 800);
    return () => clearInterval(t);
  }, [phase]);

  if (s.mode !== "courier")
    return <Screen><Empty emoji="🛵" title="Modo repartidor desactivado" body="Actívalo desde tu perfil." action={<Link to="/perfil" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Ir al perfil</Link>} /></Screen>;

  const accept = (o: Offer) => { setOffer(o); setChecks([false, false, false]); setPhase("pickup"); toast.success("Pedido aceptado"); };
  const nextGoal = goals.find((g) => g > s.courier.totalRides) ?? 50;

  const complete = (): void => {
    if (!offer) return;
    if (code !== offer.clientCode) { toast.error("Código del cliente incorrecto"); return; }
    if (!photo) { toast.error("Toma una foto del pedido entregado"); return; }
    const fee = Math.round(offer.pay * 0.1);
    s.setCourier((c) => ({ ...c, earningsToday: c.earningsToday + offer.pay, deliveries: c.deliveries + 1, totalRides: c.totalRides + 1, pendingFee: c.pendingFee + fee }));
    if (goals.includes(s.courier.totalRides + 1)) toast.success(`🏆 ¡Meta de ${s.courier.totalRides + 1} carreras! Bono desbloqueado`);
    toast.success(`¡Entregado! +${cop(offer.pay)} recibidos`);
    setPhase("home"); setOffer(null); setCode(""); setPhoto(null); setProgress(0);
  };

  return (
    <Screen>
      <div className="px-4 pt-[max(env(safe-area-inset-top),1rem)]">
        <div className="flex items-center justify-between">
          <h1 className="text-xl font-extrabold">Modo repartidor</h1>
          <label className="flex items-center gap-2 text-sm font-bold">
            <span className={s.courier.online ? "text-success" : "text-muted-foreground"}>{s.courier.online ? "CONECTADO" : "DESCONECTADO"}</span>
            <Switch checked={s.courier.online} disabled={phase !== "home" && phase !== "offer"} onCheckedChange={(v) => { s.setCourier((c) => ({ ...c, online: v })); if (!v) setPhase("home"); toast(v ? "Estás visible para restaurantes cercanos" : "Desconectado"); }} />
          </label>
        </div>

        {phase === "home" && (
          <>
            <div className="mt-3 rounded-2xl bg-card p-1.5 shadow-sm">
              <div className="grid grid-cols-2 gap-1">
                {(["general", "campus"] as const).map((z) => (
                  <button key={z} onClick={() => {
                    if (z === "campus" && !canCampus) { toast.error("Verifica tu correo universitario para repartir en el campus"); return; }
                    s.setCourier((c) => ({ ...c, zone: z })); toast(z === "campus" ? "Repartiendo dentro de tu campus 🎓" : "Repartiendo en toda la ciudad 🛵");
                  }} className={cn("rounded-xl py-2.5 text-sm font-bold active:scale-95", zone === z ? "bg-primary text-primary-foreground" : "text-muted-foreground")}>
                    {z === "general" ? "🛵 General" : "🎓 Campus" + (canCampus ? "" : " 🔒")}
                  </button>
                ))}
              </div>
              <p className="px-2 pb-1 pt-1.5 text-xs text-muted-foreground">{zone === "general" ? "Pedidos de restaurantes de la ciudad cerca de ti." : "Solo pedidos dentro de tu universidad, a pie o en bici."}</p>
              {!canCampus && <Link to="/campus" className="block px-2 pb-1 text-xs font-bold text-primary">Verificar universidad para desbloquear Campus →</Link>}
            </div>
            <div className="mt-3 grid grid-cols-2 gap-3">
              <div className="rounded-2xl bg-primary p-4 text-primary-foreground"><p className="text-xs">Ganancias hoy</p><p className="text-2xl font-extrabold">{cop(s.courier.earningsToday)}</p></div>
              <div className="rounded-2xl bg-card p-4 shadow-sm"><p className="text-xs text-muted-foreground">Entregas</p><p className="text-2xl font-extrabold">{s.courier.deliveries}</p></div>
            </div>
            <div className="mt-3 rounded-2xl bg-card p-4 shadow-sm">
              <div className="flex justify-between text-sm font-bold"><span>🏆 Meta: {nextGoal} carreras</span><span>{s.courier.totalRides}/{nextGoal}</span></div>
              <Progress value={(s.courier.totalRides / nextGoal) * 100} className="mt-2" />
              <p className="mt-1 text-xs text-muted-foreground">Bonos: 10 → $10.000 · 25 → $30.000 · 50 → $80.000</p>
            </div>
            <h2 className="mb-2 mt-4 font-bold">Mapa de demanda cerca de ti <span className="text-xs text-danger">● Alta ahora</span></h2>
            <MockMap labelA={zone === "campus" ? "Plazoleta · 6 pedidos" : "Chapinero · 9 pedidos"} labelB={zone === "campus" ? "Biblioteca +$1.200" : "Zona G +$1.500"} className="h-40" />
            {!s.courier.online ? (
              <Empty emoji="😴" title="Estás desconectado" body="Conéctate para recibir ofertas." action={<PrimaryButton onClick={() => s.setCourier((c) => ({ ...c, online: true }))}>Conectarme</PrimaryButton>} />
            ) : (
              <>
                <h2 className="mb-2 mt-4 font-bold">Pedidos disponibles ({zoneOffers.length})</h2>
                <div className="space-y-2">
                  {zoneOffers.map((o) => (
                    <div key={o.id} className="rounded-2xl bg-card p-4 shadow-sm">
                      <div className="flex justify-between"><p className="font-bold">{o.restaurant}</p><p className="font-extrabold text-success">{cop(o.pay)}</p></div>
                      <p className="text-sm text-muted-foreground">→ {o.dropoff} · {o.km} km · {o.min} min</p>
                      <button onClick={() => accept(o)} className="mt-2 w-full rounded-xl bg-primary py-2.5 font-semibold text-primary-foreground active:scale-95">Tomar pedido</button>
                    </div>
                  ))}
                </div>
                <p className="mt-3 text-center text-xs text-muted-foreground">Recibirás nuevas ofertas en vivo…</p>
              </>
            )}
          </>
        )}

        {phase === "offer" && offer && (
          <div className="mt-3 space-y-3">
            <div className="flex items-center justify-between rounded-2xl bg-secondary p-3 text-secondary-foreground"><span className="font-bold">Oferta exclusiva · EN VIVO</span><span className="text-2xl font-extrabold">{left}s</span></div>
            <MockMap labelA={offer.pickup} labelB={offer.dropoff} className="h-48" />
            <div className="rounded-2xl bg-card p-4 shadow-sm">
              <p className="text-lg font-bold">{offer.restaurant}</p>
              <p className="text-sm">📍 Recoger: {offer.pickup}</p>
              <p className="text-sm">🏁 Entregar: {offer.dropoff}</p>
              <div className="mt-3 grid grid-cols-3 text-center">
                <div><p className="text-xs text-muted-foreground">Distancia</p><p className="font-bold">{offer.km} km</p></div>
                <div><p className="text-xs text-muted-foreground">Tiempo</p><p className="font-bold">{offer.min} min</p></div>
                <div><p className="text-xs text-muted-foreground">Pago</p><p className="font-bold text-success">{cop(offer.pay)}</p></div>
              </div>
              <p className="mt-2 text-xs">💳 Pago del cliente: {offer.payment}</p>
            </div>
            <div className="grid grid-cols-2 gap-2">
              <button onClick={() => { setDeclined((d) => [...d, offer.id]); setPhase("home"); toast("Rechazada · no afecta tu nivel"); }} className="rounded-2xl bg-muted py-4 font-bold active:scale-95">Rechazar</button>
              <PrimaryButton onClick={() => accept(offer)}>Aceptar</PrimaryButton>
            </div>
          </div>
        )}

        {phase === "pickup" && offer && (
          <div className="mt-3 space-y-3">
            <p className="text-sm font-bold text-primary">Paso 1 de 2 · Recoger y verificar</p>
            <MockMap progress={0} labelA="Llegaste" labelB={offer.pickup} className="h-36" />
            <div className="rounded-2xl bg-primary p-4 text-center text-primary-foreground">
              <p className="text-sm">Muestra este código al restaurante</p>
              <p className="text-4xl font-extrabold tracking-[0.4em]">{offer.pickupCode}</p>
            </div>
            <div className="rounded-2xl bg-card p-4 shadow-sm">
              <p className="mb-2 font-bold">Checklist de recogida</p>
              {["Código validado por el restaurante", "Pedido sellado (bolsa cerrada, sin derrames)", `Productos verificados: ${offer.items}`].map((l, i) => (
                <button key={l} onClick={() => setChecks((c) => c.map((x, k) => (k === i ? !x : x)))} className="flex min-h-12 w-full items-center gap-3 text-left text-sm">
                  <span className={cn("grid size-6 place-items-center rounded-md border-2", checks[i] && "border-success bg-success text-primary-foreground")}>{checks[i] && "✓"}</span>{l}
                </button>
              ))}
            </div>
            <PrimaryButton disabled={!checks.every(Boolean)} onClick={() => { setPhase("deliver"); toast("Recogida confirmada · rumbo al cliente"); }}>Confirmar recogida</PrimaryButton>
            <Link to="/soporte" className="block text-center text-sm font-semibold text-primary">¿Problema con el pedido? Soporte</Link>
          </div>
        )}

        {phase === "deliver" && offer && (
          <div className="mt-3 space-y-3">
            <p className="text-sm font-bold text-primary">Paso 2 de 2 · Entrega a {offer.client}</p>
            <MockMap progress={progress} labelA={offer.pickup} labelB={offer.dropoff} className="h-44" />
            <div className="flex items-center gap-3 rounded-2xl bg-card p-4 shadow-sm">
              <div className="grid size-12 place-items-center rounded-full bg-accent text-xl">👩🏻</div>
              <div className="min-w-0 flex-1"><p className="font-bold">{offer.client}</p><p className="truncate text-xs text-muted-foreground">“{offer.note}”</p></div>
              <a href="tel:+573001234567" aria-label="Llamar" className="grid size-11 place-items-center rounded-full bg-success/15 text-success"><Phone className="size-5" /></a>
              <a href="sms:+573001234567" aria-label="Chat" className="grid size-11 place-items-center rounded-full bg-primary/15 text-primary"><MessageCircle className="size-5" /></a>
            </div>
            <div className="rounded-2xl bg-card p-4 text-sm shadow-sm">💳 Método de pago: <b>{offer.payment}</b></div>
            <div className="rounded-2xl bg-card p-4 shadow-sm">
              <p className="flex items-center gap-2 font-bold"><ShieldCheck className="size-4 text-success" /> Código del cliente</p>
              <input value={code} onChange={(e) => setCode(e.target.value.replace(/\D/g, "").slice(0, 4))} inputMode="numeric" placeholder="••••" className="mt-2 w-full rounded-xl border p-3 text-center text-2xl tracking-[0.5em]" />
              <p className="mt-1 text-[11px] text-muted-foreground">Demo: el cliente te dirá {offer.clientCode}</p>
            </div>
            <label className="flex cursor-pointer items-center gap-3 rounded-2xl border-2 border-dashed bg-card p-4">
              {photo ? <img src={photo} alt="Evidencia de entrega" className="size-16 rounded-xl object-cover" /> : <Camera className="size-8 text-primary" />}
              <span className="font-semibold">{photo ? "Foto lista · tocar para cambiar" : "Tomar foto de evidencia (obligatoria)"}</span>
              <input type="file" accept="image/*" capture="environment" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) setPhoto(URL.createObjectURL(f)); }} />
            </label>
            <PrimaryButton onClick={complete}>Marcar como entregado · {cop(offer.pay)}</PrimaryButton>
            <button onClick={() => toast("Soporte notificado. Te llamaremos en 1 minuto.")} className="w-full py-2 text-sm font-semibold text-danger">No encuentro al cliente · Pedir ayuda</button>
          </div>
        )}
      </div>
    </Screen>
  );
}
