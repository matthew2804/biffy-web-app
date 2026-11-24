import { createFileRoute, Link, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, Empty, Chip } from "@/components/biffy/ui";
import { dishById, restaurantById } from "@/lib/mock-data";
import { useStore, type Order } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/pedidos")({
  head: () => seo("Mis pedidos", "Pedidos activos, programados y anteriores."),
  component: Orders,
});

const statusText: Record<Order["status"], string> = {
  programado: "Programado",
  confirmado: "Confirmado",
  preparando: "Preparando",
  en_camino: "En camino",
  entregado: "Entregado",
  cancelado: "Cancelado",
};

function Orders() {
  const s = useStore();
  const navigate = useNavigate();
  const [tab, setTab] = useState<"activos" | "programados" | "anteriores">("activos");
  const list = s.orders.filter((o) =>
    tab === "activos" ? ["confirmado", "preparando", "en_camino"].includes(o.status) : tab === "programados" ? o.status === "programado" : ["entregado", "cancelado"].includes(o.status),
  );

  return (
    <Screen>
      <TopBar title="Mis pedidos" />
      <div className="flex gap-2 px-4">
        <Chip active={tab === "activos"} onClick={() => setTab("activos")}>Activos</Chip>
        <Chip active={tab === "programados"} onClick={() => setTab("programados")}>Programados</Chip>
        <Chip active={tab === "anteriores"} onClick={() => setTab("anteriores")}>Anteriores</Chip>
      </div>
      <div className="space-y-3 p-4">
        {!s.loggedIn ? (
          <Empty emoji="🔒" title="Inicia sesión para ver tus pedidos" action={<Link to="/login" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Iniciar sesión</Link>} />
        ) : list.length === 0 ? (
          <Empty emoji="🧾" title="No hay pedidos aquí" action={<Link to="/explorar" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Pedir algo</Link>} />
        ) : (
          list.map((o) => (
            <div key={o.id} className="rounded-2xl bg-card p-4 shadow-sm">
              <Link to="/pedido/$id" params={{ id: o.id }} className="block active:opacity-70">
                <div className="flex justify-between">
                  <p className="font-bold">{o.restaurantIds.map((id) => restaurantById(id)?.name).join(" + ")}</p>
                  <span className="text-sm font-bold text-primary">{statusText[o.status]}</span>
                </div>
                <p className="mt-1 truncate text-sm text-muted-foreground">{o.items.map((i) => `${i.qty}× ${dishById(i.dishId)?.name}`).join(", ")}</p>
                <p className="mt-1 text-sm">{o.scheduledFor ? "📅 " + new Date(o.scheduledFor).toLocaleString("es-CO", { weekday: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }) : "#" + o.id} · <b>{cop(o.total)}</b></p>
              </Link>
              <div className="mt-3 flex gap-2">
                {o.status === "programado" && (
                  <>
                    <button onClick={() => navigate({ to: "/pedido/$id", params: { id: o.id } })} className="flex-1 rounded-xl bg-muted py-2.5 text-sm font-semibold active:scale-95">Modificar hora</button>
                    <button onClick={() => { s.updateOrder(o.id, { status: "cancelado" }); s.addPoints(o.pointsUsed, "Reembolso de Gotas por cancelación"); toast("Pedido cancelado"); }} className="flex-1 rounded-xl bg-danger/10 py-2.5 text-sm font-semibold text-danger active:scale-95">Cancelar</button>
                  </>
                )}
                {["entregado", "cancelado"].includes(o.status) && (
                  <button onClick={() => { s.reorder(o.id); toast.success("Agregado al carrito"); navigate({ to: "/carrito" }); }} className="flex-1 rounded-xl bg-primary py-2.5 text-sm font-semibold text-primary-foreground active:scale-95">Pedir de nuevo</button>
                )}
                {["confirmado", "preparando", "en_camino"].includes(o.status) && (
                  <Link to="/pedido/$id" params={{ id: o.id }} className="flex-1 rounded-xl bg-primary py-2.5 text-center text-sm font-semibold text-primary-foreground active:scale-95">Seguir pedido</Link>
                )}
              </div>
            </div>
          ))
        )}
      </div>
    </Screen>
  );
}
