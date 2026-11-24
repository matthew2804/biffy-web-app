import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { LogOut } from "lucide-react";
import { toast } from "sonner";
import { Screen } from "@/components/biffy/ui";
import { Card, MerchantHeader, NoMerchant, Toggle } from "@/components/biffy/merchant-ui";
import { useStore } from "@/lib/store";
import { docCatalog, BIFFY_COMMISSION } from "@/lib/merchant";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/empresario/perfil")({
  head: () => seo("Mi restaurante", "Datos del negocio, sedes, documentos y configuración en Biffy."),
  component: MerchantProfilePage,
});

const days = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];

function MerchantProfilePage() {
  const s = useStore();
  const navigate = useNavigate();
  if (!s.merchant) return <NoMerchant />;
  const m = s.merchant;
  return (
    <Screen>
      <MerchantHeader title="Mi restaurante" subtitle="Perfil y configuración" right={<span className="rounded-full bg-secondary px-3 py-1 text-xs font-bold text-secondary-foreground">✓ Verificado</span>} />
      <div className="space-y-4 px-4 pt-4">
        <Card>
          <div className="flex items-center gap-3">
            <img src={m.logo} alt={m.brand} className="size-16 rounded-2xl object-cover" />
            <div className="min-w-0"><b className="block text-lg">{m.brand}</b><p className="truncate text-xs text-muted-foreground">{m.legalName} · NIT {m.nit}</p><p className="text-xs text-muted-foreground">{m.ownerName} · {m.phone}</p></div>
          </div>
        </Card>
        <Card title={`Sedes (${m.sedes.length})`}>
          <ul className="space-y-2">{m.sedes.map((x) => (
            <li key={x.id} className="rounded-2xl bg-muted p-3 text-sm"><b>{x.name}</b>{x.campusId && <span className="ml-2 rounded-full bg-success/15 px-2 text-xs font-bold text-success">🎓 -{Math.round(x.discount * 100)}%</span>}<br /><span className="text-xs text-muted-foreground">{x.address}, {x.city} · {x.open}:00–{x.close}:00 · Radio {x.radiusKm} km{x.closedDays.length ? " · Cierra " + x.closedDays.map((d) => days[d]).join(", ") : ""}</span></li>
          ))}</ul>
        </Card>
        <Card title="Configuración">
          <div className="space-y-2">
            <Toggle checked={m.showsNutrition} onChange={(v) => { s.updateMerchant({ showsNutrition: v }); toast(v ? "Ahora debes completar la nutrición de cada producto" : "La nutrición ya no se muestra a clientes"); }} label="Mostrar calorías y nutrientes" body="Te incluye en la sección de nutrición de los clientes" />
            <Toggle checked={m.paused} onChange={(v) => { s.updateMerchant({ paused: v }); toast(v ? "Pedidos pausados" : "Recibiendo pedidos"); }} label="Pausar pedidos hoy" body="Tu restaurante deja de aparecer a los clientes" />
          </div>
        </Card>
        <Card title="Legal, impuestos y pagos">
          <ul className="space-y-1 text-sm">
            <li>🧾 {m.incResponsible ? "Responsable de INC 8% (incluido en precios)" : "No responsable de INC"}</li>
            <li>📄 Facturación electrónica a cargo de Biffy (DIAN)</li>
            <li>🏦 {m.bank.bank} {m.bank.type} ••••{m.bank.number.slice(-4)} · liquidación quincenal</li>
            <li>💼 Comisión Biffy: {Math.round(BIFFY_COMMISSION * 100)}% por pedido</li>
          </ul>
          <ul className="mt-3 space-y-1 text-xs text-muted-foreground">{docCatalog.filter((d) => m.docs[d.id]).map((d) => <li key={d.id}>✅ {d.label}</li>)}</ul>
        </Card>
        <button onClick={() => { s.setMode("student"); toast("Modo cliente"); navigate({ to: "/" }); }} className="w-full rounded-2xl bg-card py-4 font-bold shadow-sm active:scale-[0.98]">🍔 Cambiar a modo cliente</button>
        <button onClick={() => { s.logout(); toast("Sesión cerrada"); navigate({ to: "/" }); }} className="flex w-full items-center justify-center gap-2 rounded-2xl bg-danger/10 py-4 font-bold text-danger active:scale-[0.98]"><LogOut className="size-5" /> Cerrar sesión de operador</button>
      </div>
    </Screen>
  );
}
