import { createFileRoute } from "@tanstack/react-router";
import { Screen, Empty } from "@/components/biffy/ui";
import { Card, MerchantHeader, NoMerchant } from "@/components/biffy/merchant-ui";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { BIFFY_COMMISSION } from "@/lib/merchant";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/empresario/estadisticas")({
  head: () => seo("Estadísticas del restaurante", "Ventas, productos más vendidos y próxima liquidación quincenal."),
  component: Stats,
});

function Stats() {
  const s = useStore();
  if (!s.merchant) return <NoMerchant />;
  const valid = s.mOrders.filter((o) => o.status !== "rechazado");
  const sales = valid.reduce((a, o) => a + o.total, 0);
  const avg = valid.length ? sales / valid.length : 0;
  const units = new Map<string, { qty: number; total: number }>();
  for (const o of valid) for (const i of o.items) { const u = units.get(i.name) ?? { qty: 0, total: 0 }; u.qty += i.qty; u.total += i.qty * i.price; units.set(i.name, u); }
  const best = [...units].sort((a, b) => b[1].total - a[1].total);
  const bySede = s.merchant.sedes.map((x) => ({ name: x.name, total: valid.filter((o) => o.sedeId === x.id).reduce((a, o) => a + o.total, 0) }));
  const maxSede = Math.max(1, ...bySede.map((x) => x.total));
  const day = new Date().getDate();
  const nextPay = day <= 15 ? "15 de este mes" : "último día del mes";

  return (
    <Screen>
      <MerchantHeader title="Estadísticas" subtitle="Turno de hoy" />
      <div className="space-y-4 px-4 pt-4">
        <div className="rounded-3xl bg-primary p-5 text-primary-foreground">
          <p className="text-sm opacity-80">Ventas</p><p className="text-3xl font-extrabold">{cop(sales)}</p>
          <p className="mt-2 text-xs opacity-80">Neto estimado tras comisión: {cop(sales * (1 - BIFFY_COMMISSION))} · Pago el {nextPay}</p>
        </div>
        <div className="grid grid-cols-2 gap-3">
          <Card><p className="text-xs text-muted-foreground">Pedidos</p><p className="text-2xl font-extrabold">{valid.length}</p></Card>
          <Card><p className="text-xs text-muted-foreground">Ticket promedio</p><p className="text-2xl font-extrabold">{cop(avg)}</p></Card>
          <Card><p className="text-xs text-muted-foreground">Rechazados</p><p className="text-2xl font-extrabold">{s.mOrders.length - valid.length}</p></Card>
          <Card><p className="text-xs text-muted-foreground">Productos activos</p><p className="text-2xl font-extrabold">{s.products.filter((p) => p.available).length}</p></Card>
        </div>
        <Card title="Ventas por sede">
          <div className="space-y-3">{bySede.map((x) => (
            <div key={x.name}><p className="flex justify-between text-sm"><span>{x.name}</span><b>{cop(x.total)}</b></p><div className="mt-1 h-2.5 rounded-full bg-muted"><div className="h-full rounded-full bg-primary" style={{ width: `${(x.total / maxSede) * 100}%` }} /></div></div>
          ))}</div>
        </Card>
        <Card title="Más vendidos">
          {best.length === 0 ? <Empty emoji="📊" title="Aún no hay ventas" /> : (
            <ol className="space-y-2">{best.map(([n, u], i) => <li key={n} className="flex items-center gap-3 rounded-2xl bg-muted p-3"><b className="text-primary">#{i + 1}</b><span className="min-w-0 flex-1"><b className="block truncate text-sm">{n}</b><span className="text-xs text-muted-foreground">{u.qty} unidades</span></span><b className="text-sm">{cop(u.total)}</b></li>)}</ol>
          )}
        </Card>
      </div>
    </Screen>
  );
}
