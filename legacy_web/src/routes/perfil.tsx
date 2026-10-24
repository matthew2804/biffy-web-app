import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { ChevronRight, Lock, Unlock, LogOut, Bike } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, Empty, PrimaryButton } from "@/components/biffy/ui";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Switch } from "@/components/ui/switch";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/perfil")({
  head: () => seo("Perfil", "Tu cuenta, preferencias, pagos y soporte."),
  component: Profile,
});

function Profile() {
  const s = useStore();
  const navigate = useNavigate();
  const [unlocked, setUnlocked] = useState(false);
  const [pinOpen, setPinOpen] = useState(false);
  const [pin, setPin] = useState("");
  const [sent, setSent] = useState<string | null>(null);
  const [via, setVia] = useState<"correo" | "teléfono">("correo");
  const [courierOpen, setCourierOpen] = useState(false);
  const [edit, setEdit] = useState({ name: "", phone: "", career: "" });

  if (!s.user)
    return <Screen><div className="pt-10" /><Empty emoji="👤" title="Aún no has iniciado sesión" body="Entra para ver pedidos, recompensas y preferencias." action={<Link to="/login" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Iniciar sesión</Link>} /></Screen>;
  const u = s.user;
  const isCourier = s.mode === "courier";

  const sendPin = () => {
    const p = String(Math.floor(1000 + Math.random() * 9000));
    setSent(p);
    toast(`PIN enviado a tu ${via} (demo: ${p})`, { duration: 8000 });
  };

  const items: { to: "/pedidos" | "/recompensas" | "/favoritos" | "/campus" | "/encuesta" | "/pagos" | "/ajustes" | "/soporte"; label: string; emoji: string; hint?: string | undefined }[] = [
    { to: "/pedidos", label: "Mis pedidos e historial", emoji: "🧾" },
    { to: "/recompensas", label: "Recompensas", emoji: "🎁", hint: `${s.points} 💧` },
    { to: "/favoritos", label: "Favoritos", emoji: "❤️", hint: String(s.favorites.length) },
    { to: "/campus", label: "Mi campus", emoji: "🎓", hint: u.verified ? "Verificado" : "Verificar" },
    { to: "/encuesta", label: s.surveyDone ? "Editar gustos y alergias" : "Completa tus filtros", emoji: "🥗", hint: s.surveyDone ? undefined : "+300 💧" },
    { to: "/pagos", label: "Métodos de pago", emoji: "💳" },
    { to: "/ajustes", label: "Configuración y notificaciones", emoji: "⚙️" },
    { to: "/soporte", label: "Ayuda y soporte", emoji: "💬" },
  ];

  return (
    <Screen>
      <div className="px-4 pt-[max(env(safe-area-inset-top),1rem)]">
        <h1 className="text-2xl font-extrabold">Perfil</h1>
        <div className="mt-3 flex items-center gap-3 rounded-3xl bg-card p-4 shadow-sm">
          <div className="grid size-16 shrink-0 place-items-center rounded-full bg-primary text-2xl font-extrabold text-primary-foreground">{u.name[0]?.toUpperCase()}</div>
          <div className="min-w-0">
            <p className="truncate text-lg font-bold">{u.name}</p>
            <p className="truncate text-sm text-muted-foreground">{s.university?.name ?? "Universidad no verificada"}</p>
            <p className="text-xs font-semibold">{u.verified ? "✅ Verificado" : "⚠️ Sin verificar"} · {s.ordersCount} pedidos · {s.points} 💧</p>
          </div>
        </div>

        {!s.surveyDone && (
          <Link to="/encuesta" className="mt-3 block rounded-2xl bg-secondary p-4 font-semibold text-secondary-foreground active:scale-[0.99]">📋 Completa la encuesta de filtros y gana 300 Gotas →</Link>
        )}

        <div className="mt-4 rounded-2xl bg-card p-4 shadow-sm">
          <div className="flex items-center justify-between">
            <p className="font-bold">Información personal</p>
            {unlocked ? (
              <button onClick={() => { s.updateUser({ name: edit.name || u.name, phone: edit.phone || u.phone, career: edit.career || u.career }); setUnlocked(false); toast.success("Datos guardados"); }} className="flex items-center gap-1 text-sm font-bold text-primary"><Unlock className="size-4" /> Guardar y bloquear</button>
            ) : (
              <button onClick={() => { setPinOpen(true); setSent(null); setPin(""); }} className="flex items-center gap-1 text-sm font-bold text-primary"><Lock className="size-4" /> Desbloquear</button>
            )}
          </div>
          {([
            ["Nombre", "name", u.name],
            ["Teléfono", "phone", u.phone],
            ["Carrera", "career", u.career],
          ] as const).map(([l, k, v]) => (
            <label key={k} className="mt-3 block text-sm">
              <span className="text-muted-foreground">{l}</span>
              {unlocked ? (
                <input defaultValue={v} onChange={(e) => setEdit((x) => ({ ...x, [k]: e.target.value }))} className="mt-1 w-full rounded-xl border bg-background p-2.5" />
              ) : (
                <span className="mt-1 block font-semibold">{k === "phone" ? v.replace(/\d(?=\d{2})/g, "•") : v}</span>
              )}
            </label>
          ))}
          <p className="mt-3 text-sm"><span className="text-muted-foreground">Correo</span><span className="block font-semibold">{unlocked ? u.email : u.email.replace(/^(.).+(@.+)$/, "$1•••$2")}</span></p>
        </div>

        <ul className="mt-4 overflow-hidden rounded-2xl bg-card shadow-sm">
          {items.map((it) => (
            <li key={it.to} className="border-b last:border-0">
              <button onClick={() => navigate({ to: it.to })} className="flex min-h-14 w-full items-center gap-3 px-4 text-left active:bg-muted">
                <span className="text-xl">{it.emoji}</span><span className="flex-1 font-semibold">{it.label}</span>
                {it.hint && <span className="text-sm font-bold text-primary">{it.hint}</span>}
                <ChevronRight className="size-5 text-muted-foreground" />
              </button>
            </li>
          ))}
        </ul>

        <div className="mt-4 rounded-3xl bg-primary p-5 text-primary-foreground">
          <div className="flex items-center justify-between">
            <p className="flex items-center gap-2 text-lg font-extrabold"><Bike /> {isCourier ? "Modo repartidor activo" : "Gana dinero como repartidor"}</p>
            <Switch checked={isCourier} onCheckedChange={(v) => { if (v) setCourierOpen(true); else { s.setMode("student"); s.setCourier((c) => ({ ...c, online: false })); toast("Volviste al modo estudiante"); navigate({ to: "/" }); } }} />
          </div>
          <p className="mt-1 text-sm opacity-90">{isCourier ? "Desactívalo para volver a pedir comida." : "Reparte en tu ciudad o en tu campus y recibe tu pago al instante."}</p>
          {isCourier && <Link to="/repartidor" className="mt-3 inline-block rounded-xl bg-card px-4 py-2 font-bold text-primary">Ir al panel</Link>}
        </div>

        <Link to={s.merchant ? "/empresario" : "/empresario/registro"} onClick={() => { if (s.merchant) s.setMode("merchant"); }} className="mt-3 flex items-center gap-3 rounded-3xl bg-card p-4 shadow-sm active:scale-[0.99]">
          <span className="text-3xl">🏪</span>
          <span className="min-w-0 flex-1"><b className="block">{s.merchant ? `Panel de ${s.merchant.brand}` : "Vende tu restaurante en Biffy"}</b><span className="text-xs text-muted-foreground">{s.merchant ? "Pedidos, menú y estadísticas" : "Registra tu negocio y llega a estudiantes"}</span></span>
          <ChevronRight className="size-5 text-muted-foreground" />
        </Link>


        <button onClick={() => { s.logout(); toast("Sesión cerrada"); navigate({ to: "/" }); }} className="mt-4 flex w-full items-center justify-center gap-2 rounded-2xl bg-danger/10 py-4 font-bold text-danger active:scale-[0.98]"><LogOut className="size-5" /> Cerrar sesión</button>
      </div>

      <Dialog open={pinOpen} onOpenChange={setPinOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Verifica que eres tú</DialogTitle></DialogHeader>
          {!sent ? (
            <div className="space-y-3">
              <p className="text-sm text-muted-foreground">Te enviaremos un PIN de 4 dígitos.</p>
              <div className="grid grid-cols-2 gap-2">
                {(["correo", "teléfono"] as const).map((v) => <button key={v} onClick={() => setVia(v)} className={"rounded-xl border p-3 font-semibold " + (via === v ? "border-primary bg-accent" : "")}>{v === "correo" ? "📧 Correo" : "📱 SMS"}</button>)}
              </div>
              <PrimaryButton onClick={sendPin}>Enviar PIN</PrimaryButton>
            </div>
          ) : (
            <div className="space-y-3">
              <input value={pin} onChange={(e) => setPin(e.target.value.replace(/\D/g, "").slice(0, 4))} inputMode="numeric" placeholder="••••" className="w-full rounded-xl border p-3 text-center text-2xl tracking-[0.5em]" />
              <PrimaryButton onClick={() => { if (pin === sent) { setUnlocked(true); setPinOpen(false); toast.success("Información desbloqueada"); } else toast.error("PIN incorrecto"); }}>Confirmar</PrimaryButton>
              <button onClick={sendPin} className="w-full text-sm font-semibold text-primary">Reenviar PIN</button>
            </div>
          )}
        </DialogContent>
      </Dialog>

      <Dialog open={courierOpen} onOpenChange={setCourierOpen}>
        <DialogContent className="max-w-sm">
          <DialogHeader><DialogTitle>Activar modo repartidor</DialogTitle></DialogHeader>
          <ul className="space-y-2 text-sm">
            <li>✅ Documento de identidad y mayor de edad</li>
            <li>✅ Moto, bicicleta, patineta o a pie</li>
            <li>{u.verified ? "🎓 Puedes elegir repartir en tu campus desde el panel" : "🎓 Verifica tu universidad si también quieres repartir en el campus"}</li>
            <li>ℹ️ Recibes el pago al entregar; Biffy cobra su tarifa cada quincena.</li>
          </ul>
          <PrimaryButton onClick={() => { s.setMode("courier"); setCourierOpen(false); toast.success("¡Modo repartidor activado! 🛵"); navigate({ to: "/repartidor" }); }}>Entrar como repartidor</PrimaryButton>
        </DialogContent>
      </Dialog>
    </Screen>
  );
}
