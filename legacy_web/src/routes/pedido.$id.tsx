import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Phone, MessageCircle, ShieldCheck } from "lucide-react";
import { useEffect, useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, MockMap, Empty, PrimaryButton } from "@/components/biffy/ui";
import { deliveryPoints, dishById, paymentMethodsCatalog, restaurantById } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/pedido/$id")({
  head: () => ({
    meta: [
      { title: "Seguimiento de pedido · Biffy" },
      { name: "description", content: "Sigue tu pedido en tiempo real." },
      { property: "og:title", content: "Seguimiento de pedido · Biffy" },
      { property: "og:description", content: "Sigue tu pedido en tiempo real." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary" },
    ],
  }),
  component: Tracking,
});

const steps = [
  { id: "confirmado", label: "Confirmado" },
  { id: "preparando", label: "Preparando" },
  { id: "en_camino", label: "En camino" },
  { id: "entregado", label: "Entregado" },
] as const;

function Tracking() {
  const { id } = Route.useParams();
  const s = useStore();
  const navigate = useNavigate();
  const o = s.orders.find((x) => x.id === id);
  const [rating, setRating] = useState(0);

  useEffect(() => {
    if (!o || !["confirmado", "preparando", "en_camino"].includes(o.status)) return;
    const t = setTimeout(() => s.advanceOrder(o.id), 6000);
    return () => clearTimeout(t);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [o?.id, o?.status]);

  // Pedido programado: al llegar la hora de entrega arranca solo el proceso de delivery.
  useEffect(() => {
    if (!o || o.status !== "programado" || !o.scheduledFor) return;
    const t = setInterval(() => {
      if (Date.now() >= new Date(o.scheduledFor!).getTime()) {
        s.updateOrder(o.id, { status: "confirmado", scheduledFor: undefined });
        toast.success("¡Es la hora! Tu pedido ya está en proceso 🐝");
      }
    }, 1000);
    return () => clearInterval(t);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [o?.id, o?.status, o?.scheduledFor]);

  if (!o) return <Screen nav={false}><TopBar title="Pedido" /><Empty emoji="🧾" title="Pedido no encontrado" action={<Link to="/pedidos" className="font-bold text-primary">Ver mis pedidos</Link>} /></Screen>;

  const idx = steps.findIndex((x) => x.id === o.status);
  const progress = o.status === "en_camino" ? 0.6 : o.status === "entregado" ? 1 : 0;
  const point = deliveryPoints.find((p) => p.id === o.pointId)!;
  const pay = paymentMethodsCatalog.find((p) => p.id === o.paymentId);
  const isDemo = o.restaurantIds.some((rid) => restaurantById(rid)?.demo);

  return (
    <Screen nav={false} className="pb-10">
      <TopBar title={`Pedido ${o.id}`} right={<Link to="/pedidos" className="text-sm font-bold text-primary">Todos</Link>} />
      <div className="space-y-4 px-4">
        {o.restaurantIds.some((rid) => restaurantById(rid)?.demo) && <p className="border-y py-2 text-sm font-semibold text-muted-foreground">Pedido de demostración · sin cobros ni entrega real</p>}
        {o.status === "cancelado" ? (
          <Empty emoji="❌" title="Pedido cancelado" />
        ) : (
          <>
            <MockMap progress={progress} labelA={restaurantById(o.restaurantIds[0] ?? "")?.name ?? "Restaurante"} labelB={point.name} className="h-56" />
            <div className="rounded-2xl bg-card p-4 shadow-sm">
              <p className="text-sm text-muted-foreground">{o.status === "entregado" ? "Entregado" : o.status === "programado" ? "Llega a las" : "Llega en"}</p>
              <p className="text-2xl font-extrabold">{o.status === "entregado" ? "¡Buen provecho! 😋" : o.status === "programado" && o.scheduledFor ? new Date(o.scheduledFor).toLocaleTimeString("es-CO", { hour: "2-digit", minute: "2-digit" }) : `${isDemo ? Math.max(1, 8 - idx * 3) : Math.max(2, 18 - idx * 6)} min`}</p>
              <div className="mt-4 flex gap-1.5">{steps.map((st, i) => <div key={st.id} className={cn("h-1.5 flex-1 rounded-full", i <= idx ? "bg-success" : "bg-muted")} />)}</div>
              <div className="mt-2 flex justify-between text-[11px] font-semibold">{steps.map((st, i) => <span key={st.id} className={i <= idx ? "text-success" : "text-muted-foreground"}>{st.label}</span>)}</div>
            </div>
            {o.status !== "entregado" && (
              <>
                <div className="flex items-center gap-3 rounded-2xl bg-card p-4 shadow-sm">
                  <div className="grid size-12 place-items-center rounded-full bg-accent text-2xl">🧑🏽‍🦱</div>
                  <div className="flex-1"><p className="font-bold">{isDemo ? "Sebastián" : "Andrés"} · Repartidor</p><p className="text-xs text-muted-foreground">{isDemo ? "🎓 Repartidor de campus · Universidad Icesi · ⭐ 4.9" : "⭐ 4.9 · Bicicleta"}</p></div>
                  <a href="tel:+573001112233" aria-label="Llamar" className="grid size-11 place-items-center rounded-full bg-success/15 text-success active:scale-90"><Phone className="size-5" /></a>
                  <a href="sms:+573001112233" aria-label="Mensaje" className="grid size-11 place-items-center rounded-full bg-primary/15 text-primary active:scale-90"><MessageCircle className="size-5" /></a>
                </div>
                <div className="rounded-2xl bg-primary p-4 text-primary-foreground">
                  <p className="flex items-center gap-2 text-sm font-semibold"><ShieldCheck className="size-4" /> Código de entrega</p>
                  <p className="mt-1 text-4xl font-extrabold tracking-[0.4em]">{o.code}</p>
                  <p className="mt-1 text-xs opacity-90">Díselo al repartidor solo cuando tengas tu pedido.</p>
                </div>
              </>
            )}
            {o.status === "entregado" && (
              <div className="rounded-2xl bg-card p-4 text-center shadow-sm">
                <p className="font-bold">¿Cómo estuvo tu pedido?</p>
                <div className="mt-2 flex justify-center gap-2">{[1, 2, 3, 4, 5].map((n) => <button key={n} onClick={() => { setRating(n); toast("¡Gracias por calificar!"); }} className="text-3xl active:scale-90">{n <= rating ? "⭐" : "☆"}</button>)}</div>
                <PrimaryButton className="mt-3" onClick={() => { s.reorder(o.id); navigate({ to: "/carrito" }); }}>Pedir de nuevo</PrimaryButton>
              </div>
            )}
          </>
        )}

        <div className="rounded-2xl bg-card p-4 text-sm shadow-sm">
          <p className="mb-2 font-bold">Resumen</p>
          {o.items.map((i) => <p key={i.key} className="flex justify-between"><span>{i.qty}× {dishById(i.dishId)?.name}</span></p>)}
          <p className="mt-2 flex justify-between text-muted-foreground"><span>Pago</span><span>{pay?.label}</span></p>
          {o.tip > 0 && <p className="flex justify-between text-muted-foreground"><span>Propina para el repartidor</span><span>{cop(o.tip)}</span></p>}
          <p className="flex justify-between text-muted-foreground"><span>Entrega</span><span>{point.name}</span></p>
          <p className="mt-2 flex justify-between border-t pt-2 font-extrabold"><span>Total</span><span>{cop(o.total)}</span></p>
        </div>
        <Link to="/soporte" className="block text-center text-sm font-semibold text-primary">¿Problemas con tu pedido? Contactar soporte</Link>
      </div>
    </Screen>
  );
}
