import { createFileRoute } from "@tanstack/react-router";
import { toast } from "sonner";
import { Screen, TopBar } from "@/components/biffy/ui";
import { Progress } from "@/components/ui/progress";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/repartidor/ganancias")({
  head: () => seo("Ganancias", "Tus ganancias, tarifa quincenal y premios por carreras."),
  component: Earnings,
});

const goals = [
  { n: 10, prize: 10000 },
  { n: 25, prize: 30000 },
  { n: 50, prize: 80000 },
];

function Earnings() {
  const s = useStore();
  const c = s.courier;
  const next = new Date();
  next.setDate(next.getDate() <= 15 ? 15 : new Date(next.getFullYear(), next.getMonth() + 1, 0).getDate());
  return (
    <Screen>
      <TopBar title="Ganancias" back={false} />
      <div className="space-y-3 px-4">
        <div className="rounded-3xl bg-primary p-5 text-primary-foreground">
          <p className="text-sm">Recibido hoy</p>
          <p className="text-3xl font-extrabold">{cop(c.earningsToday)}</p>
          <p className="text-sm opacity-90">{c.deliveries} entregas · pagos inmediatos al entregar</p>
        </div>
        <div className="rounded-2xl bg-card p-4 shadow-sm">
          <p className="font-bold">Tarifa Biffy (10%)</p>
          <p className="text-2xl font-extrabold text-danger">{cop(c.pendingFee)}</p>
          <p className="text-xs text-muted-foreground">Se cobra cada quincena · próximo cobro {next.toLocaleDateString("es-CO", { day: "numeric", month: "long" })}</p>
          <button onClick={() => (c.pendingFee ? toast.success("Tarifa pagada. ¡Gracias!") : toast("No tienes saldo pendiente"))} className="mt-3 w-full rounded-xl bg-muted py-2.5 text-sm font-semibold active:scale-95">Pagar ahora</button>
        </div>
        <h2 className="mt-2 font-bold">Premios por carreras</h2>
        {goals.map((g) => (
          <div key={g.n} className="rounded-2xl bg-card p-4 shadow-sm">
            <div className="flex justify-between text-sm font-bold"><span>{c.totalRides >= g.n ? "✅" : "🏆"} {g.n} carreras</span><span className="text-success">+{cop(g.prize)}</span></div>
            <Progress value={Math.min(100, (c.totalRides / g.n) * 100)} className="mt-2" />
            <p className="mt-1 text-xs text-muted-foreground">{Math.min(c.totalRides, g.n)}/{g.n}</p>
          </div>
        ))}
      </div>
    </Screen>
  );
}
