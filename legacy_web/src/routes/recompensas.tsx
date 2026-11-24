import { createFileRoute, Link } from "@tanstack/react-router";
import { toast } from "sonner";
import { Screen, TopBar, Empty } from "@/components/biffy/ui";
import { Progress } from "@/components/ui/progress";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/recompensas")({
  head: () => seo("Club de Enjambre", "Gana Gotas Biffy y canjéalas por descuentos."),
  component: Rewards,
});

const levels = [
  { n: 3, name: "Abeja Obrera", prize: "Envío gratis" },
  { n: 6, name: "Abeja Exploradora", prize: "$5.000 de descuento" },
  { n: 10, name: "Abeja Reina", prize: "Combo gratis + 1.000 Gotas" },
];
const prizes = [
  { id: "p1", label: "Envío gratis", cost: 300 },
  { id: "p2", label: "Café gratis", cost: 650 },
  { id: "p3", label: "$7.000 de descuento", cost: 700 },
];

function Rewards() {
  const s = useStore();
  if (!s.loggedIn) return <Screen nav={false}><TopBar title="Recompensas" /><Empty emoji="🐝" title="Únete al Club de Enjambre" body="Inicia sesión para ganar Gotas." action={<Link to="/login" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Iniciar sesión</Link>} /></Screen>;
  const streak = s.ordersCount % 10;
  const code = "BIFFY-" + (s.user?.name.split(" ")[0]?.toUpperCase() ?? "AMIGO");

  const invite = async () => {
    const text = `Únete a Biffy con mi código ${code} y gana Gotas 🐝 ${window.location.origin}`;
    if (navigator.share) await navigator.share({ text }).catch(() => {});
    else await navigator.clipboard.writeText(text);
    toast.success("Invitación compartida. Ganarás 200 Gotas cuando tu amigo se una.");
    setTimeout(() => s.addReferral(), 4000); // simulated friend signup
  };

  return (
    <Screen nav={false}>
      <TopBar title="Club de Enjambre" />
      <div className="space-y-4 px-4">
        <div className="rounded-3xl bg-secondary p-5 text-secondary-foreground">
          <p className="text-sm font-semibold">Tus Gotas Biffy</p>
          <p className="text-4xl font-extrabold">{s.points} 💧</p>
          <p className="text-sm">≈ {cop(s.points * s.GOTA_VALUE)} en descuentos</p>
        </div>
        <div className="rounded-2xl bg-card p-4 shadow-sm">
          <div className="flex justify-between font-bold"><span>Racha de pedidos</span><span>{streak}/10</span></div>
          <Progress value={streak * 10} className="mt-2" />
          <div className="mt-3 space-y-2">
            {levels.map((l) => (
              <div key={l.n} className={"flex items-center justify-between rounded-xl p-2 text-sm " + (streak >= l.n ? "bg-success/15 font-semibold text-success" : "bg-muted")}>
                <span>{streak >= l.n ? "✅" : "🔒"} {l.n} pedidos · {l.name}</span><span>{l.prize}</span>
              </div>
            ))}
          </div>
        </div>
        <h2 className="text-lg font-bold">Cómo ganar Gotas</h2>
        <div className="space-y-2">
          {!s.surveyDone ? (
            <Link to="/encuesta" className="flex items-center justify-between rounded-2xl bg-card p-4 shadow-sm active:scale-[0.99]"><span>📋 Completa tus filtros</span><b className="text-primary">+300</b></Link>
          ) : (
            <div className="flex items-center justify-between rounded-2xl bg-card p-4 opacity-60"><span>✅ Filtros completados</span><b>+300</b></div>
          )}
          <button onClick={invite} className="flex w-full items-center justify-between rounded-2xl bg-card p-4 shadow-sm active:scale-[0.99]"><span>👥 Invita amigos ({s.referrals})</span><b className="text-primary">+200 c/u</b></button>
          <Link to="/explorar" className="flex items-center justify-between rounded-2xl bg-card p-4 shadow-sm active:scale-[0.99]"><span>🛍️ Haz pedidos</span><b className="text-primary">+1 por $1.000</b></Link>
        </div>
        <h2 className="text-lg font-bold">Canjear</h2>
        <div className="grid grid-cols-3 gap-2">
          {prizes.map((p) => (
            <button
              key={p.id}
              disabled={s.points < p.cost}
              onClick={() => { s.addPoints(-p.cost, `Canjeaste: ${p.label}`); toast.success(`Canjeaste ${p.label}. Se aplicará en tu próximo pedido.`); }}
              className="rounded-2xl bg-card p-3 text-center shadow-sm active:scale-95 disabled:opacity-40"
            >
              <p className="text-sm font-semibold">{p.label}</p>
              <p className="mt-1 text-xs font-bold text-primary">{p.cost} 💧</p>
            </button>
          ))}
        </div>
      </div>
    </Screen>
  );
}
