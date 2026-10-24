import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { Minus, Plus, Trash2, Pencil, MapPin } from "lucide-react";
import { useMemo, useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, PrimaryButton, Empty, Carousel, Chip, AllergyBadge } from "@/components/biffy/ui";
import { PointPicker } from "@/components/biffy/point-picker";
import { Switch } from "@/components/ui/switch";
import { dishById, paymentMethodsCatalog, restaurantById } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { cop, isOpenNow, isReachable } from "@/lib/format";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/carrito")({
  head: () => seo("Carrito", "Revisa tu pedido, prográmalo y paga."),
  component: Cart,
});

const dayNames = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];

function Cart() {
  const s = useStore();
  const navigate = useNavigate();
  const [when, setWhen] = useState<"now" | "later">("now");
  const [dayIdx, setDayIdx] = useState(0);
  const [slot, setSlot] = useState<string | null>(null);
  const [pay, setPay] = useState(s.defaultPayment);
  const [usePts, setUsePts] = useState(false);
  const [tipPct, setTipPct] = useState(0);

  const rests = [...new Set(s.cart.map((i) => dishById(i.dishId)!.restaurantId))].map((id) => restaurantById(id)!);
  const unreachable = rests.filter((r) => !isReachable(r, s.point));
  const openNow = rests.every((r) => isOpenNow(r));
  const sum = s.cartSummary(usePts ? s.points : 0);
  const tip = Math.round(((sum.subtotal - sum.discount) * tipPct) / 100);
  const grand = sum.total + tip;

  const days = useMemo(() => {
    const out: { date: Date; ok: boolean }[] = [];
    for (let i = 0; i < 7; i++) {
      const d = new Date();
      d.setHours(0, 0, 0, 0);
      d.setDate(d.getDate() + i);
      out.push({ date: d, ok: rests.every((r) => !r.closedDays.includes(d.getDay())) });
    }
    return out;
  }, [rests]);

  const slots = useMemo(() => {
    if (!rests.length) return [];
    const open = Math.max(...rests.map((r) => r.open));
    const close = Math.min(...rests.map((r) => r.close));
    const day = days[dayIdx];
    if (!day?.ok) return [];
    const res: string[] = [];
    const now = new Date();
    const lead = rests.every((r) => r.demo) ? 8 : 45;
    for (let m = open * 60; m <= close * 60 - 30; m += 30) {
      const t = new Date(day.date);
      t.setMinutes(m);
      if (t.getTime() > now.getTime() + lead * 60000) res.push(t.toISOString());
    }
    return res;
  }, [rests, days, dayIdx]);

  const isDemo = rests.length > 0 && rests.every((r) => r.demo);
  const noonPick = (() => {
    for (let i = 0; i < days.length; i++) {
      const day = days[i]; if (!day?.ok) continue;
      const t = new Date(day.date);
      t.setHours(12, 0, 0, 0);
      if (t.getTime() > Date.now() + 8 * 60000) return { i, iso: t.toISOString() };
    }
    return null;
  })();
  const pickNoon = (): void => {
    if (!noonPick) return;
    setWhen("later"); setDayIdx(noonPick.i); setSlot(noonPick.iso);
    toast.success(noonPick.i === 0 ? "Programado para hoy a las 12:00" : "Programado a las 12:00 del próximo día disponible");
  };

  if (!s.cart.length)
    return (
      <Screen nav={false}>
        <TopBar title="Carrito" />
        <Empty emoji="🛒" title="Tu carrito está vacío" body="Explora platos cerca de ti." action={<Link to="/explorar" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Explorar</Link>} />
      </Screen>
    );

  const confirm = (): void => {
    if (!s.loggedIn) {
      toast("Inicia sesión para completar tu pedido");
      navigate({ to: "/login", search: { next: "/carrito" } });
      return;
    }
    if (unreachable.length) { toast.error("Hay locales que no entregan en tu punto"); return; }
    if (when === "now" && !openNow) { toast.error("Un local está cerrado. Programa tu pedido."); return; }
    if (when === "later" && !slot) { toast.error("Elige una hora de entrega"); return; }
    const o = s.placeOrder({ scheduledFor: when === "later" ? slot! : undefined, paymentId: pay, pointsToUse: usePts ? s.points : 0, tip });
    toast.success(when === "later" ? "Pedido programado 📅" : "¡Pedido confirmado! 🎉");
    navigate({ to: "/pedido/$id", params: { id: o.id } });
  };

  return (
    <Screen nav={false} className="pb-36">
      <TopBar title="Tu carrito" right={<button onClick={() => { s.clearCart(); toast("Carrito vaciado"); }} aria-label="Vaciar" className="grid size-11 place-items-center rounded-full bg-card shadow-sm active:scale-95"><Trash2 className="size-5 text-danger" /></button>} />
      <div className="space-y-4 px-4">
        <section className="space-y-2">
          {s.cart.map((it) => {
            const d = dishById(it.dishId)!;
            const r = restaurantById(d.restaurantId)!;
            const opts = (d.options ?? []).filter((o) => it.optionIds.includes(o.id));
            return (
              <div key={it.key} className="flex gap-3 rounded-2xl bg-card p-3 shadow-sm">
                <div className="grid size-16 shrink-0 place-items-center rounded-xl bg-accent text-3xl">{d.emoji}</div>
                <div className="min-w-0 flex-1">
                  <p className="truncate font-semibold">{d.name}</p>
                  <p className="truncate text-xs text-muted-foreground">{r.name}{opts.length ? " · " + opts.map((o) => o.label).join(", ") : ""}{it.note ? ` · “${it.note}”` : ""}</p>
                  <AllergyBadge dish={d} />
                  <div className="mt-2 flex items-center justify-between">
                    <span className="font-bold">{cop(s.unitPrice(d, it.optionIds) * it.qty)}</span>
                    <div className="flex items-center gap-1">
                      <Link to="/plato/$id" params={{ id: d.id }} onClick={() => s.removeItem(it.key)} aria-label="Editar" className="grid size-9 place-items-center rounded-full bg-muted active:scale-90"><Pencil className="size-4" /></Link>
                      <button aria-label="Menos" onClick={() => s.setQty(it.key, it.qty - 1)} className="grid size-9 place-items-center rounded-full bg-muted active:scale-90">{it.qty === 1 ? <Trash2 className="size-4 text-danger" /> : <Minus className="size-4" />}</button>
                      <span className="w-5 text-center font-bold">{it.qty}</span>
                      <button aria-label="Más" onClick={() => s.setQty(it.key, it.qty + 1)} className="grid size-9 place-items-center rounded-full bg-primary text-primary-foreground active:scale-90"><Plus className="size-4" /></button>
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </section>

        <section className="rounded-2xl bg-card p-4 shadow-sm">
          <h2 className="font-bold">¿Cuándo lo quieres?</h2>
          <div className="mt-3 grid grid-cols-2 gap-2">
            <button onClick={() => setWhen("now")} className={cn("rounded-xl border p-3 font-semibold active:scale-95", when === "now" && "border-primary bg-accent text-primary")}>⚡ Ahora {!openNow && <span className="block text-[11px] text-danger">Local cerrado</span>}</button>
            <button onClick={() => setWhen("later")} className={cn("rounded-xl border p-3 font-semibold active:scale-95", when === "later" && "border-primary bg-accent text-primary")}>📅 Programar</button>
          </div>
          {isDemo && noonPick && (
            <button onClick={pickNoon} className={cn("mt-2 w-full rounded-xl border-2 border-dashed border-primary p-3 text-left font-semibold active:scale-[0.99]", slot === noonPick.iso && when === "later" && "bg-accent")}>
              🕛 Que llegue a las 12:00 {noonPick.i === 0 ? "hoy" : `· ${dayNames[days[noonPick.i]!.date.getDay()]} ${days[noonPick.i]!.date.getDate()}`}
              <span className="block text-xs font-normal text-muted-foreground">A las 12:00 Sebastián sale con tu pedido · llega en 8 min</span>
            </button>
          )}
          {when === "later" && (
            <>
              <Carousel className="mt-3">
                {days.map((d, i) => (
                  <button key={i} disabled={!d.ok} onClick={() => { setDayIdx(i); setSlot(null); }} className={cn("w-16 shrink-0 snap-start rounded-xl border p-2 text-center active:scale-95 disabled:opacity-30", dayIdx === i && "border-primary bg-primary text-primary-foreground")}>
                    <span className="block text-xs">{i === 0 ? "Hoy" : dayNames[d.date.getDay()]}</span>
                    <span className="block text-lg font-bold">{d.date.getDate()}</span>
                  </button>
                ))}
              </Carousel>
              <p className="mt-3 text-xs text-muted-foreground">Horas según disponibilidad del local</p>
              {slots.length ? (
                <div className="mt-2 grid grid-cols-4 gap-2">
                  {slots.map((t) => (
                    <button key={t} onClick={() => setSlot(t)} className={cn("rounded-lg border py-2 text-sm font-semibold active:scale-95", slot === t && "border-primary bg-primary text-primary-foreground")}>
                      {new Date(t).toLocaleTimeString("es-CO", { hour: "2-digit", minute: "2-digit" })}
                    </button>
                  ))}
                </div>
              ) : (
                <p className="mt-2 text-sm font-semibold text-danger">Sin horarios disponibles este día</p>
              )}
            </>
          )}
        </section>

        <section className="rounded-2xl bg-card p-4 shadow-sm">
          <h2 className="font-bold">Punto de entrega</h2>
          <PointPicker trigger={(open) => (
            <button onClick={open} className="mt-2 flex w-full items-center gap-3 rounded-xl border p-3 text-left active:scale-[0.99]">
              <MapPin className="size-5 text-primary" />
              <span className="flex-1"><b>{s.point.name}</b><span className="block text-xs text-muted-foreground">{s.point.detail}</span></span>
              <span className="text-sm font-bold text-primary">Cambiar</span>
            </button>
          )} />
          {unreachable.length > 0 && <p className="mt-2 text-sm font-semibold text-danger">{unreachable.map((r) => r.name).join(", ")} no entrega aquí.</p>}
        </section>

        <section className="rounded-2xl bg-card p-4 shadow-sm">
          <h2 className="font-bold">Método de pago</h2>
          {rests.some((r) => r.demo) && <p className="mt-1 text-xs text-muted-foreground">Pago simulado: no se cobra dinero ni se envía un pedido real a Qbano.</p>}
          <div className="mt-2 space-y-2">
            {paymentMethodsCatalog.map((m) => (
              <button key={m.id} onClick={() => setPay(m.id)} className={cn("flex w-full items-center gap-3 rounded-xl border p-3 active:scale-[0.99]", pay === m.id && "border-primary bg-accent")}>
                <span className="text-xl">{m.emoji}</span><span className="flex-1 text-left font-semibold">{m.label}</span>
                <span className={cn("size-5 rounded-full border-2", pay === m.id && "border-[6px] border-primary")} />
              </button>
            ))}
          </div>
          {s.loggedIn && s.points > 0 && (
            <label className="mt-3 flex items-center justify-between rounded-xl bg-secondary/20 p-3">
              <span className="text-sm font-semibold">Usar mis {s.points} Gotas 💧 (−{cop(Math.min(s.points * s.GOTA_VALUE, sum.subtotal - sum.discount))})</span>
              <Switch checked={usePts} onCheckedChange={setUsePts} />
            </label>
          )}
        </section>

        <section className="rounded-2xl bg-card p-4 shadow-sm">
          <h2 className="font-bold">Propina para el repartidor</h2>
          <p className="mt-1 text-xs text-muted-foreground">El 100% es para quien te lleva el pedido.{pay === "cash" ? " Se la pagas en efectivo junto al total." : ""}</p>
          <div className="mt-2 grid grid-cols-4 gap-2">
            {[0, 5, 10, 15].map((p) => (
              <button key={p} onClick={() => setTipPct(p)} className={cn("rounded-xl border py-2.5 text-sm font-bold active:scale-95", tipPct === p && "border-primary bg-accent")}>{p === 0 ? "Sin" : p + "%"}</button>
            ))}
          </div>
        </section>

        <section className="space-y-1.5 rounded-2xl bg-card p-4 text-sm shadow-sm">
          <Row l="Subtotal" v={cop(sum.subtotal)} />
          {sum.discount > 0 && <Row l="🎓 Descuento estudiante" v={"−" + cop(sum.discount)} green />}
          <Row l="Tarifa de entrega" v={cop(sum.fee)} />
          {sum.pointsDiscount > 0 && <Row l="💧 Gotas" v={"−" + cop(sum.pointsDiscount)} green />}
          {tip > 0 && <Row l={`🤝 Propina (${tipPct}%)`} v={cop(tip)} />}
          <div className="mt-2 flex justify-between border-t pt-2 text-base font-extrabold"><span>Total</span><span>{cop(grand)}</span></div>
        </section>
      </div>

      <div className="fixed inset-x-0 bottom-0 z-40 mx-auto max-w-md border-t bg-card p-4 pb-[max(env(safe-area-inset-bottom),1rem)]">
        <PrimaryButton onClick={confirm}>{s.loggedIn ? "Pagar" : "Inicia sesión para pagar"} · {cop(grand)}</PrimaryButton>
      </div>
    </Screen>
  );
}

function Row({ l, v, green }: { l: string; v: string; green?: boolean }) {
  return <div className={cn("flex justify-between", green && "font-semibold text-success")}><span>{l}</span><span>{v}</span></div>;
}
