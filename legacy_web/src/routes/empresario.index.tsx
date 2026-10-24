import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, SectionTitle, Empty } from "@/components/biffy/ui";
import { MerchantHeader, NoMerchant, statusMeta } from "@/components/biffy/merchant-ui";
import { Receipt } from "@/components/biffy/receipt";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import type { MOrder } from "@/lib/merchant";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/empresario/")({
  head: () => seo("Panel del restaurante", "Ventas del día, pedidos activos y tus platos más vendidos."),
  component: MerchantHome,
});

function MerchantHome() {
  const s = useStore();
  const [receipt, setReceipt] = useState<MOrder | null>(null);
  if (!s.merchant) return <NoMerchant />;
  const m = s.merchant;
  const valid = s.mOrders.filter((o) => o.status !== "rechazado");
  const sales = valid.reduce((a, o) => a + o.total, 0);
  const c = (st: string) => s.mOrders.filter((o) => o.status === st).length;
  const active = s.mOrders.filter((o) => o.status === "nuevo" || o.status === "preparando");
  const top = [...s.products].sort((a, b) => Number(b.featured) - Number(a.featured)).slice(0, 3);

  return (
    <Screen>
      <MerchantHeader
        title={`Hola, ${m.brand} 👋`}
        subtitle="Así va tu restaurante hoy"
        right={
          <button onClick={() => { s.updateMerchant({ paused: !m.paused }); toast(m.paused ? "Restaurante abierto: recibes pedidos" : "Pedidos pausados: no apareces a clientes"); }} className={"shrink-0 rounded-full px-4 py-2 text-sm font-bold active:scale-95 " + (m.paused ? "bg-danger/15 text-danger" : "bg-success text-primary-foreground")}>
            {m.paused ? "⏸ Pausado" : "● Abierto"}
          </button>
        }
      />
      <div className="px-4">
        <div className="mt-4 rounded-3xl bg-primary p-5 text-primary-foreground">
          <p className="text-sm font-semibold opacity-80">Ventas de hoy</p>
          <p className="text-3xl font-extrabold">{cop(sales)}</p>
          <p className="mt-1 text-xs opacity-80">{valid.length} pedidos · se liquidan cada quincena</p>
        </div>
        <div className="mt-3 grid grid-cols-2 gap-3">
          {([["🧾", "Por confirmar", c("nuevo")], ["🍳", "En preparación", c("preparando")], ["🛵", "En camino", c("en_camino") + c("listo")], ["✅", "Entregados", c("entregado")]] as const).map(([e, l, n]) => (
            <Link key={l} to="/empresario/pedidos" className="rounded-3xl bg-card p-4 shadow-sm active:scale-[0.98]"><span className="text-2xl">{e}</span><p className="mt-1 text-2xl font-extrabold">{n}</p><p className="text-xs text-muted-foreground">{l}</p></Link>
          ))}
        </div>

        <SectionTitle title="Pedidos ahora" action={<Link to="/empresario/pedidos" className="text-sm font-bold text-primary">Ver todos</Link>} />
        {active.length === 0 ? <Empty emoji="😌" title="Sin pedidos pendientes" /> : (
          <div className="space-y-3">{active.map((o) => (
            <button key={o.id} onClick={() => setReceipt(o)} className="w-full rounded-3xl bg-card p-4 text-left shadow-sm active:scale-[0.99]">
              <div className="flex justify-between"><b>#{o.id}</b><span className={"rounded-full px-2 py-0.5 text-xs font-bold " + statusMeta[o.status]!.cls}>{statusMeta[o.status]!.label}</span></div>
              <p className="mt-1 text-sm">{o.client} · {o.items.map((i) => `${i.qty}× ${i.name}`).join(", ")}</p>
              <p className="mt-1 font-extrabold">{cop(o.total)}</p>
            </button>
          ))}</div>
        )}

        <SectionTitle title="Tus productos destacados" action={<Link to="/empresario/menu" className="text-sm font-bold text-primary">Menú</Link>} />
        {top.length === 0 ? <Empty emoji="🍽️" title="Aún no tienes productos" action={<Link to="/empresario/producto/$id" params={{ id: "nuevo" }} className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Crear producto</Link>} /> : (
          <div className="space-y-3">{top.map((p) => (
            <Link key={p.id} to="/empresario/producto/$id" params={{ id: p.id }} className="flex items-center gap-3 rounded-3xl bg-card p-3 shadow-sm active:scale-[0.99]">
              <img src={p.photo} alt={p.name} className="size-16 rounded-2xl object-cover" />
              <span className="min-w-0 flex-1"><b className="block truncate">{p.name}</b><span className="text-sm font-bold text-primary">{cop(p.price)}</span></span>
              {p.featured && <span className="rounded-full bg-secondary px-2 py-0.5 text-xs font-bold text-secondary-foreground">Top</span>}
            </Link>
          ))}</div>
        )}
      </div>
      <Receipt order={receipt} onClose={() => setReceipt(null)} />
    </Screen>
  );
}
