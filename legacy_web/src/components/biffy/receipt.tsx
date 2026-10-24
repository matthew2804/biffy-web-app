import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { BIFFY_COMMISSION, incBreakdown, type MOrder } from "@/lib/merchant";

/** Merchant receipt: what was sold, taxes, Biffy commission and the net amount for the settlement. */
export function Receipt({ order, onClose }: { order: MOrder | null; onClose: () => void }) {
  const s = useStore();
  if (!order) return null;
  const sede = s.merchant?.sedes.find((x) => x.id === order.sedeId);
  const { base, inc } = incBreakdown(order.total, !!s.merchant?.incResponsible);
  const fee = Math.round(order.total * BIFFY_COMMISSION);
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-w-sm rounded-3xl">
        <DialogHeader><DialogTitle>Recibo #{order.id}</DialogTitle></DialogHeader>
        <div className="space-y-3 text-sm">
          <p className="text-xs text-muted-foreground">{s.merchant?.legalName} · NIT {s.merchant?.nit}<br />Sede {sede?.name} · {new Date(order.createdAt).toLocaleString("es-CO")}<br />Cliente: {order.client}</p>
          <ul className="space-y-1 border-y py-2">
            {order.items.map((i, k) => (
              <li key={k} className="flex justify-between gap-2"><span>{i.qty}× {i.name}{i.note && <span className="block text-xs text-muted-foreground">“{i.note}”</span>}</span><span className="font-semibold">{cop(i.price * i.qty)}</span></li>
            ))}
          </ul>
          <div className="space-y-1">
            <Row l="Base gravable" v={cop(base)} />
            {inc > 0 && <Row l="INC 8% (incluido)" v={cop(inc)} />}
            <Row l="Total pagado por el cliente" v={cop(order.total)} b />
            <Row l={`Comisión Biffy ${Math.round(BIFFY_COMMISSION * 100)}%`} v={"-" + cop(fee)} />
            <Row l="Neto para tu liquidación quincenal" v={order.status === "rechazado" ? cop(0) : cop(order.total - fee)} b />
          </div>
          <p className="rounded-xl bg-muted p-2 text-xs">💳 {order.payment}. 🧾 Factura electrónica emitida por Biffy ante la DIAN. La entrega la gestiona Biffy.</p>
        </div>
      </DialogContent>
    </Dialog>
  );
}

function Row({ l, v, b }: { l: string; v: string; b?: boolean }) {
  return <p className={"flex justify-between " + (b ? "font-extrabold" : "text-muted-foreground")}><span>{l}</span><span>{v}</span></p>;
}
