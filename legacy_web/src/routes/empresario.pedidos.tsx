import { createFileRoute } from "@tanstack/react-router";
import { Search } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, Carousel, Chip, Empty } from "@/components/biffy/ui";
import { MerchantHeader, NoMerchant, statusMeta } from "@/components/biffy/merchant-ui";
import { Receipt } from "@/components/biffy/receipt";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import type { MOrder } from "@/lib/merchant";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/empresario/pedidos")({
  head: () => seo("Pedidos del restaurante", "Acepta, prepara y consulta los recibos de tus pedidos."),
  component: Pedidos,
});

const tabs = [
  { id: "all", label: "Todos" },
  { id: "nuevo", label: "Nuevos" },
  { id: "preparando", label: "En cocina" },
  { id: "listo", label: "Listos" },
  { id: "done", label: "Finalizados" },
] as const;
const reasons = ["Ingrediente agotado", "Cocina saturada", "Local por cerrar", "Producto no disponible"];

function Pedidos() {
  const s = useStore();
  const [tab, setTab] = useState<(typeof tabs)[number]["id"]>("all");
  const [q, setQ] = useState("");
  const [receipt, setReceipt] = useState<MOrder | null>(null);
  const [rejecting, setRejecting] = useState<MOrder | null>(null);
  if (!s.merchant) return <NoMerchant />;

  const match = (o: MOrder) =>
    tab === "all" ? true : tab === "done" ? ["en_camino", "entregado", "rechazado"].includes(o.status) : o.status === tab;
  const t = q.trim().toLowerCase();
  const list = s.mOrders.filter(match).filter((o) => !t || (o.id + o.client + o.items.map((i) => i.name).join(" ")).toLowerCase().includes(t));
  const count = (id: string) => s.mOrders.filter((o) => (id === "all" ? true : id === "done" ? ["en_camino", "entregado", "rechazado"].includes(o.status) : o.status === id)).length;

  return (
    <Screen>
      <MerchantHeader title="Pedidos" subtitle="Gestiona tu cocina en tiempo real" />
      <div className="px-4">
        <label className="mt-4 flex items-center gap-2 rounded-2xl bg-card px-3 shadow-sm">
          <Search className="size-5 text-muted-foreground" />
          <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar por #ID, cliente o plato" className="min-w-0 flex-1 bg-transparent py-3 outline-none" />
        </label>
        <Carousel className="mt-3">{tabs.map((x) => <Chip key={x.id} active={tab === x.id} onClick={() => setTab(x.id)}>{x.label} {count(x.id)}</Chip>)}</Carousel>

        <div className="mt-4 space-y-3">
          {list.length === 0 && <Empty emoji="🧾" title="No hay pedidos aquí" body="Los pedidos de tus clientes aparecerán en tiempo real." />}
          {list.map((o) => {
            const st = statusMeta[o.status]!;
            const sede = s.merchant!.sedes.find((x) => x.id === o.sedeId);
            return (
              <article key={o.id} className="rounded-3xl bg-card p-4 shadow-sm">
                <div className="flex items-start justify-between gap-2">
                  <div><p className="text-lg font-extrabold">#{o.id}</p><p className="text-xs text-muted-foreground">{new Date(o.createdAt).toLocaleTimeString("es-CO", { hour: "2-digit", minute: "2-digit" })} · Sede {sede?.name}</p></div>
                  <span className={"rounded-full px-2.5 py-1 text-xs font-bold " + st.cls}>{st.label}</span>
                </div>
                <p className="mt-3 rounded-2xl bg-muted p-3 text-sm font-semibold">{o.client}</p>
                <ul className="mt-2 space-y-1 text-sm">{o.items.map((i, k) => <li key={k}>{i.qty}× {i.name}{i.note && <span className="block text-xs text-danger">⚠ {i.note}</span>}</li>)}</ul>
                <p className="mt-2 text-xs font-semibold">{o.scheduledFor ? "📅 Programado: " + new Date(o.scheduledFor).toLocaleString("es-CO") : "⚡ Para ahora"} · 💳 {o.payment}</p>
                {o.rejectReason && <p className="mt-2 rounded-xl bg-danger/10 p-2 text-xs text-danger">Motivo: {o.rejectReason}</p>}
                <div className="mt-3 flex items-center justify-between"><span className="text-xs text-muted-foreground">Total</span><span className="text-xl font-extrabold">{cop(o.total)}</span></div>

                <div className="mt-3 flex gap-2">
                  {o.status === "nuevo" && (
                    <>
                      <button onClick={() => { s.setMOrderStatus(o.id, "preparando"); toast.success(`Pedido #${o.id} aceptado`); }} className="flex-1 rounded-2xl bg-primary py-3 font-bold text-primary-foreground active:scale-95">Aceptar pedido</button>
                      <button onClick={() => setRejecting(o)} className="rounded-2xl bg-danger/10 px-4 font-bold text-danger active:scale-95">Rechazar</button>
                    </>
                  )}
                  {o.status === "preparando" && <button onClick={() => { s.setMOrderStatus(o.id, "listo"); toast.success("¡Listo! Biffy asigna un repartidor 🛵"); }} className="flex-1 rounded-2xl bg-success py-3 font-bold text-primary-foreground active:scale-95">Marcar como listo</button>}
                  <button onClick={() => setReceipt(o)} className={(o.status === "nuevo" || o.status === "preparando" ? "" : "flex-1 ") + "rounded-2xl bg-muted px-4 py-3 font-bold active:scale-95"}>🧾 Recibo</button>
                </div>
              </article>
            );
          })}
        </div>
      </div>
      <Receipt order={receipt} onClose={() => setReceipt(null)} />
      <Dialog open={!!rejecting} onOpenChange={(v) => !v && setRejecting(null)}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader><DialogTitle>¿Por qué rechazas #{rejecting?.id}?</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">El cliente recibirá el reembolso completo.</p>
          <div className="space-y-2">{reasons.map((r) => <button key={r} onClick={() => { s.setMOrderStatus(rejecting!.id, "rechazado", r); setRejecting(null); toast("Pedido rechazado · reembolso en proceso"); }} className="w-full rounded-2xl border p-3 text-left font-semibold active:scale-[0.99]">{r}</button>)}</div>
        </DialogContent>
      </Dialog>
    </Screen>
  );
}
