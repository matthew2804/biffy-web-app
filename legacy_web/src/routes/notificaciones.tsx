import { createFileRoute } from "@tanstack/react-router";
import { Screen, TopBar, Empty } from "@/components/biffy/ui";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/notificaciones")({
  head: () => seo("Notificaciones", "Novedades de tus pedidos y recompensas."),
  component: Notifs,
});

function Notifs() {
  const s = useStore();
  return (
    <Screen nav={false}>
      <TopBar title="Notificaciones" right={<button onClick={s.markAllRead} className="text-xs font-bold text-primary">Leer todo</button>} />
      <div className="space-y-2 px-4">
        {s.notifications.length === 0 && <Empty emoji="🔔" title="Sin notificaciones" />}
        {s.notifications.map((n) => (
          <div key={n.id} className={"rounded-2xl p-4 shadow-sm " + (n.read ? "bg-card" : "border-l-4 border-primary bg-accent")}>
            <p className="font-bold">{n.title}</p>
            <p className="text-sm text-muted-foreground">{n.body}</p>
          </div>
        ))}
      </div>
    </Screen>
  );
}
