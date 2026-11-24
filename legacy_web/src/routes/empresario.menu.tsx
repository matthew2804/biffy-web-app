import { createFileRoute, Link } from "@tanstack/react-router";
import { Plus, Search } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, Carousel, Chip, Empty } from "@/components/biffy/ui";
import { MerchantHeader, NoMerchant, Toggle } from "@/components/biffy/merchant-ui";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/empresario/menu")({
  head: () => seo("Mi menú", "Crea, edita y elimina los productos de tu restaurante en Biffy."),
  component: Menu,
});

function Menu() {
  const s = useStore();
  const [q, setQ] = useState("");
  const [sec, setSec] = useState<string | null>(null);
  if (!s.merchant) return <NoMerchant />;
  const sections = [...new Set(s.products.map((p) => p.section))];
  const t = q.trim().toLowerCase();
  const list = s.products.filter((p) => (!sec || p.section === sec) && (!t || p.name.toLowerCase().includes(t)));

  return (
    <Screen>
      <MerchantHeader
        title="Mi menú"
        subtitle={`${s.products.length} productos · ${sections.length} secciones`}
        right={<Link to="/empresario/producto/$id" params={{ id: "nuevo" }} aria-label="Crear producto" className="grid size-14 place-items-center rounded-full bg-primary text-primary-foreground shadow-lg active:scale-95"><Plus className="size-7" /></Link>}
      />
      <div className="px-4">
        <label className="mt-4 flex items-center gap-2 rounded-2xl bg-card px-3 shadow-sm"><Search className="size-5 text-muted-foreground" /><input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Buscar productos…" className="min-w-0 flex-1 bg-transparent py-3 outline-none" /></label>
        <Carousel className="mt-3"><Chip active={!sec} onClick={() => setSec(null)}>Todos ({s.products.length})</Chip>{sections.map((x) => <Chip key={x} active={sec === x} onClick={() => setSec(x)}>{x} ({s.products.filter((p) => p.section === x).length})</Chip>)}</Carousel>
        <div className="mt-4 space-y-3">
          {list.length === 0 && <Empty emoji="🍽️" title="Sin productos" body="Crea tu primer producto con foto e información completa." />}
          {list.map((p) => {
            const soldOut = p.dailyStock === 0;
            return (
              <article key={p.id} className="rounded-3xl bg-card p-3 shadow-sm">
                <Link to="/empresario/producto/$id" params={{ id: p.id }} className="flex gap-3 active:scale-[0.99]">
                  <img src={p.photo} alt={p.name} className={"size-20 rounded-2xl object-cover " + (!p.available ? "grayscale" : "")} />
                  <span className="min-w-0 flex-1">
                    <span className="flex items-center justify-between gap-2"><span className="text-xs font-semibold uppercase text-muted-foreground">{p.section}</span><span className={"rounded-full px-2 py-0.5 text-[11px] font-bold " + (p.available && !soldOut ? "bg-success/15 text-success" : "bg-danger/15 text-danger")}>{p.available ? (soldOut ? "Agotado hoy" : "Activo") : "Pausado"}</span></span>
                    <b className="block truncate">{p.name}</b>
                    <span className="flex justify-between"><span className="font-extrabold text-primary">{cop(p.price)}</span><span className="text-sm font-bold text-primary">Editar ✏️</span></span>
                    <span className="block truncate text-xs text-muted-foreground">📍 {p.sedeIds.map((id) => s.merchant!.sedes.find((x) => x.id === id)?.name).join(", ")}</span>
                  </span>
                </Link>
                <div className="mt-2"><Toggle checked={p.available} onChange={(v) => { s.saveProduct({ ...p, available: v }); toast(v ? "Visible para clientes" : "Ocultado temporalmente"); }} label={p.available ? "Disponible: Sí" : "Disponible: No"} /></div>
              </article>
            );
          })}
        </div>
        <Link to="/empresario/producto/$id" params={{ id: "nuevo" }} className="mt-4 flex items-center justify-center gap-2 rounded-2xl bg-primary py-4 font-bold text-primary-foreground active:scale-[0.98]"><Plus className="size-5" /> Crear producto</Link>
      </div>
    </Screen>
  );
}
