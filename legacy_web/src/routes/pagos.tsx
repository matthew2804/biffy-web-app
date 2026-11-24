import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, PrimaryButton } from "@/components/biffy/ui";
import { paymentMethodsCatalog } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/pagos")({
  head: () => seo("Métodos de pago", "Administra tus métodos de pago en Biffy."),
  component: Payments,
});

function Payments() {
  const s = useStore();
  const [cards, setCards] = useState<string[]>([]);
  const [num, setNum] = useState("");
  return (
    <Screen nav={false}>
      <TopBar title="Métodos de pago" />
      <div className="space-y-2 px-4">
        <p className="text-sm text-muted-foreground">Toca uno para usarlo por defecto.</p>
        {[...paymentMethodsCatalog, ...cards.map((c) => ({ id: c, label: "Tarjeta •••• " + c.slice(-4), emoji: "💳" }))].map((m) => (
          <button key={m.id} onClick={() => { s.setDefaultPayment(m.id); toast(`${m.label} es tu método por defecto`); }} className={cn("flex w-full items-center gap-3 rounded-2xl border bg-card p-4 active:scale-[0.99]", s.defaultPayment === m.id && "border-primary")}>
            <span className="text-2xl">{m.emoji}</span><span className="flex-1 text-left font-semibold">{m.label}</span>
            {s.defaultPayment === m.id && <span className="text-xs font-bold text-primary">Por defecto</span>}
          </button>
        ))}
        <div className="mt-4 rounded-2xl bg-card p-4">
          <p className="font-bold">Agregar tarjeta</p>
          <input value={num} onChange={(e) => setNum(e.target.value.replace(/\D/g, "").slice(0, 16))} inputMode="numeric" placeholder="Número de tarjeta" className="mt-2 w-full rounded-xl border p-3" />
          <PrimaryButton className="mt-3" disabled={num.length < 15} onClick={() => { setCards((c) => [...c, num]); setNum(""); toast.success("Tarjeta agregada"); }}>Guardar tarjeta</PrimaryButton>
        </div>
      </div>
    </Screen>
  );
}
