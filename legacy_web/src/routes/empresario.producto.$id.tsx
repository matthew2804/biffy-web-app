import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Camera, Trash2, X, Plus } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { TopBar, Chip, PrimaryButton } from "@/components/biffy/ui";
import { Card, NoMerchant, PhotoPicker, TextField, Toggle } from "@/components/biffy/merchant-ui";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useStore } from "@/lib/store";
import { allergyOptions, categories, lifestyleOptions } from "@/lib/mock-data";
import { cop } from "@/lib/format";
import { emptyProduct, incBreakdown, productErrors, type MerchantProduct } from "@/lib/merchant";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/empresario/producto/$id")({
  head: () => seo("Producto del menú", "Crea o edita un producto con foto, ingredientes, alérgenos, precio y sedes."),
  component: ProductEditor,
});

function ProductEditor() {
  const s = useStore();
  const { id } = Route.useParams();
  if (!s.merchant) return <NoMerchant />;
  const existing = s.products.find((p) => p.id === id);
  return <Editor key={id} initial={existing ?? emptyProduct("p" + Date.now().toString(36), s.merchant.sedes.map((x) => x.id))} isNew={!existing} />;
}

function Editor({ initial, isNew }: { initial: MerchantProduct; isNew: boolean }) {
  const s = useStore();
  const navigate = useNavigate();
  const m = s.merchant!;
  const [p, setP] = useState(initial);
  const [ing, setIng] = useState("");
  const [tried, setTried] = useState(false);
  const [confirmDel, setConfirmDel] = useState(false);
  const set = (x: Partial<MerchantProduct>) => setP((v) => ({ ...v, ...x }));
  const errs = productErrors(p, m.showsNutrition);
  const toggle = (arr: string[], v: string) => (arr.includes(v) ? arr.filter((x) => x !== v) : [...arr, v]);
  const tax = incBreakdown(p.price || 0, m.incResponsible);
  const nut = p.nutrition ?? { kcal: 0, protein: 0, carbs: 0, fat: 0 };

  const save = () => {
    setTried(true);
    if (errs.length) { toast.error(`Falta información: ${errs[0]}`); return; }
    s.saveProduct({ ...p, name: p.name.trim(), description: p.description.trim(), section: p.section.trim() });
    toast.success(isNew ? "Producto publicado en tu carta 🚀" : "Cambios guardados");
    navigate({ to: "/empresario/menu" });
  };
  const addIng = () => { const v = ing.trim(); if (v && !p.ingredients.includes(v)) set({ ingredients: [...p.ingredients, v] }); setIng(""); };

  return (
    <div className="min-h-dvh pb-40">
      <TopBar title={isNew ? "Crear producto" : "Editar producto"} />
      <div className="space-y-4 px-4">
        <Card title="Fotografía del plato" right={<span className="text-xs font-semibold text-danger">Obligatoria</span>}>
          <div className="flex gap-2">
            <PhotoPicker onPick={(u) => set({ photo: u })} className={cn("relative grid h-40 flex-1 place-items-center overflow-hidden rounded-2xl border-2 border-dashed active:scale-[0.99]", tried && !p.photo && "border-danger")}>
              {p.photo ? <><img src={p.photo} alt="Foto principal" className="absolute inset-0 size-full object-cover" /><span className="absolute bottom-2 left-2 rounded-full bg-card px-3 py-1 text-xs font-bold">Cambiar</span></> : <span className="text-center text-sm"><Camera className="mx-auto size-8 text-primary" /><b className="block">Subir foto principal</b><span className="text-xs text-muted-foreground">JPG/PNG/WEBP · mín. 600×600 px</span></span>}
            </PhotoPicker>
            <div className="flex w-20 flex-col gap-2">
              {p.extraPhotos.map((u, i) => <button key={i} aria-label="Quitar foto" onClick={() => set({ extraPhotos: p.extraPhotos.filter((_, k) => k !== i) })} className="relative h-[4.6rem] overflow-hidden rounded-xl"><img src={u} alt="" className="size-full object-cover" /><X className="absolute right-1 top-1 size-4 rounded-full bg-card" /></button>)}
              {p.extraPhotos.length < 2 && <PhotoPicker onPick={(u) => set({ extraPhotos: [...p.extraPhotos, u] })} className="grid h-[4.6rem] place-items-center rounded-xl bg-muted text-xs font-bold">+ Foto</PhotoPicker>}
            </div>
          </div>
        </Card>

        <Card title="Información básica">
          <div className="space-y-3">
            <TextField label="Nombre del producto" required max={40} value={p.name} onChange={(v) => set({ name: v })} placeholder="Teriyaki Chicken Bowl" />
            <div><span className="text-sm font-semibold">Categoría <span className="text-danger">*</span></span><div className="no-scrollbar mt-1 flex gap-1.5 overflow-x-auto">{categories.map((c) => <Chip key={c.id} active={p.category === c.id} onClick={() => set({ category: c.id })}>{c.emoji} {c.label}</Chip>)}</div></div>
            <TextField label="Sección en tu carta" required value={p.section} onChange={(v) => set({ section: v })} placeholder="Bowls, Combos, Bebidas…" hint={[...new Set(s.products.map((x) => x.section))].join(" · ") || undefined} />
            <label className="block"><span className="flex justify-between text-sm font-semibold"><span>Descripción <span className="text-danger">*</span></span><span className="text-xs text-muted-foreground">{p.description.length}/180</span></span>
              <textarea value={p.description} maxLength={180} onChange={(e) => set({ description: e.target.value })} rows={3} placeholder="Ingredientes principales, preparación y porción" className="mt-1 w-full rounded-2xl border bg-background p-3 outline-none focus:border-primary" /></label>
            <Toggle checked={p.featured} onChange={(v) => set({ featured: v })} label="⭐ Producto destacado" body="Aparece en 'Lo más pedido' y arriba de tu menú" />
          </div>
        </Card>

        <Card title="Ingredientes y alérgenos" right={<span className="text-xs text-muted-foreground">Visible para clientes</span>}>
          <div className="flex gap-2"><input value={ing} onChange={(e) => setIng(e.target.value)} onKeyDown={(e) => e.key === "Enter" && (e.preventDefault(), addIng())} placeholder="Ej. Pollo, arroz…" className="min-w-0 flex-1 rounded-2xl border bg-background px-3 py-2.5 outline-none" /><button onClick={addIng} className="rounded-2xl bg-accent px-4 font-bold text-accent-foreground active:scale-95">Añadir</button></div>
          <div className="mt-2 flex flex-wrap gap-1.5">{p.ingredients.map((x) => <button key={x} onClick={() => set({ ingredients: p.ingredients.filter((y) => y !== x) })} className="flex items-center gap-1 rounded-full bg-muted px-3 py-1 text-sm">{x} <X className="size-3" /></button>)}</div>
          <p className="mt-4 text-sm font-semibold">Alérgenos que contiene <span className="text-danger">*</span></p>
          <div className="mt-1 flex flex-wrap gap-1.5">{allergyOptions.map((a) => <Chip key={a} active={p.allergens.includes(a)} onClick={() => set({ allergens: toggle(p.allergens, a), noAllergens: false })}>{a}</Chip>)}<Chip active={p.noAllergens} onClick={() => set({ noAllergens: !p.noAllergens, allergens: [] })}>✓ Sin alérgenos</Chip></div>
          <p className="mt-4 text-sm font-semibold">Estilo de vida</p>
          <div className="mt-1 flex flex-wrap gap-1.5">{lifestyleOptions.map((a) => <Chip key={a} active={p.tags.includes(a)} onClick={() => set({ tags: toggle(p.tags, a) })}>{a}</Chip>)}</div>
        </Card>

        {m.showsNutrition && (
          <Card title="🥦 Calorías y nutrientes" right={<span className="text-xs font-semibold text-danger">Obligatorio</span>}>
            <p className="mb-2 text-xs text-muted-foreground">Tu restaurante muestra nutrición. Valores por porción.</p>
            <div className="grid grid-cols-2 gap-2">
              {([["kcal", "Calorías (kcal)"], ["protein", "Proteína (g)"], ["carbs", "Carbohidratos (g)"], ["fat", "Grasas (g)"]] as const).map(([k, l]) => (
                <TextField key={k} label={l} inputMode="numeric" value={nut[k] ? String(nut[k]) : ""} onChange={(v) => set({ nutrition: { ...nut, [k]: Number(v.replace(/\D/g, "")) } })} />
              ))}
            </div>
          </Card>
        )}

        <Card title="Precio y cocina">
          <div className="grid grid-cols-2 gap-2">
            <TextField label="Precio de venta (COP)" required inputMode="numeric" value={p.price ? String(p.price) : ""} onChange={(v) => set({ price: Number(v.replace(/\D/g, "")) })} placeholder="22500" />
            <label className="text-sm font-semibold">Tiempo de cocina<select value={p.prepMin} onChange={(e) => set({ prepMin: +e.target.value })} className="mt-1 w-full rounded-2xl border bg-background p-3">{[5, 10, 15, 20, 30, 45].map((x) => <option key={x} value={x}>{x} min</option>)}</select></label>
          </div>
          <p className="mt-3 rounded-2xl bg-muted p-3 text-xs">
            {m.incResponsible ? <>🔒 <b>INC 8% incluido · obligatorio DIAN</b> según tu RUT. Base {cop(tax.base)} + INC {cop(tax.inc)}.</> : <>Tu RUT indica que no eres responsable de INC. Si cambias de régimen, actualízalo en Perfil.</>}
          </p>
        </Card>

        <Card title="Extras y adiciones" right={<span className="text-xs text-muted-foreground">Opcional</span>}>
          <div className="space-y-2">{p.options.map((o, i) => (
            <div key={o.id} className="flex gap-2">
              <input value={o.label} onChange={(e) => set({ options: p.options.map((x, k) => (k === i ? { ...x, label: e.target.value } : x)) })} placeholder="Extra pollo" className="min-w-0 flex-1 rounded-xl border bg-background px-3 py-2" />
              <input value={o.price ? String(o.price) : ""} inputMode="numeric" onChange={(e) => set({ options: p.options.map((x, k) => (k === i ? { ...x, price: Number(e.target.value.replace(/\D/g, "")) } : x)) })} placeholder="+$" className="w-24 rounded-xl border bg-background px-3 py-2" />
              <button aria-label="Quitar extra" onClick={() => set({ options: p.options.filter((_, k) => k !== i) })} className="text-danger"><Trash2 className="size-5" /></button>
            </div>
          ))}</div>
          <button onClick={() => set({ options: [...p.options, { id: "x" + Date.now().toString(36), label: "", price: 0 }] })} className="mt-2 flex w-full items-center justify-center gap-1 rounded-2xl bg-muted py-2.5 text-sm font-bold text-primary active:scale-[0.99]"><Plus className="size-4" /> Agregar extra</button>
        </Card>

        <Card title="Sedes donde se vende" right={<span className="text-xs font-semibold text-danger">Mín. 1</span>}>
          <div className="space-y-2">{m.sedes.map((x) => {
            const on = p.sedeIds.includes(x.id);
            return <button key={x.id} onClick={() => set({ sedeIds: toggle(p.sedeIds, x.id) })} className={cn("flex w-full items-center gap-3 rounded-2xl border p-3 text-left active:scale-[0.99]", on && "border-primary bg-accent")}><span className={cn("grid size-5 place-items-center rounded-md border-2 text-xs", on && "border-primary bg-primary text-primary-foreground")}>{on && "✓"}</span><span><b className="block text-sm">{x.name}</b><span className="text-xs text-muted-foreground">{x.address} · {x.open}:00–{x.close}:00{x.campusId ? " · 🎓 campus" : ""}</span></span></button>;
          })}</div>
        </Card>

        <Card title="Disponibilidad">
          <div className="space-y-2">
            <Toggle checked={p.available} onChange={(v) => set({ available: v })} label="Disponible para venta" body="Si lo desactivas se oculta sin borrar su configuración" />
            <Toggle checked={p.dailyStock !== null} onChange={(v) => set({ dailyStock: v ? 30 : null })} label="Límite diario de porciones" body="Se oculta al llegar a 0" />
            {p.dailyStock !== null && (
              <div className="flex items-center justify-between rounded-2xl bg-muted p-3"><span className="text-sm font-semibold">Porciones hoy</span><span className="flex items-center gap-3"><button onClick={() => set({ dailyStock: Math.max(0, (p.dailyStock ?? 0) - 1) })} className="grid size-9 place-items-center rounded-full bg-card font-bold">−</button><b className="w-8 text-center">{p.dailyStock}</b><button onClick={() => set({ dailyStock: (p.dailyStock ?? 0) + 1 })} className="grid size-9 place-items-center rounded-full bg-card font-bold">+</button></span></div>
            )}
          </div>
        </Card>

        {tried && errs.length > 0 && (
          <div className="rounded-2xl bg-danger/10 p-3 text-sm text-danger"><b>No se puede publicar todavía:</b><ul className="mt-1 list-disc pl-5">{errs.map((e) => <li key={e}>{e}</li>)}</ul></div>
        )}
      </div>

      <div className="fixed inset-x-0 bottom-0 z-40 mx-auto max-w-md space-y-2 border-t bg-card p-4 pb-[max(env(safe-area-inset-bottom),1rem)]">
        <PrimaryButton onClick={save} className={errs.length ? "opacity-60" : ""}>{isNew ? "🚀 Publicar en la carta" : "✓ Guardar cambios"}</PrimaryButton>
        <div className="flex gap-2">
          <button onClick={() => navigate({ to: "/empresario/menu" })} className="flex-1 rounded-2xl bg-muted py-3 font-bold active:scale-95">Cancelar</button>
          {!isNew && <button onClick={() => setConfirmDel(true)} className="flex flex-1 items-center justify-center gap-1 rounded-2xl bg-danger/10 py-3 font-bold text-danger active:scale-95"><Trash2 className="size-4" /> Eliminar</button>}
        </div>
      </div>

      <Dialog open={confirmDel} onOpenChange={setConfirmDel}>
        <DialogContent className="max-w-sm rounded-3xl">
          <DialogHeader><DialogTitle>¿Eliminar “{p.name}”?</DialogTitle></DialogHeader>
          <p className="text-sm text-muted-foreground">Desaparecerá de todas tus sedes. Esta acción no se puede deshacer.</p>
          <PrimaryButton className="bg-danger" onClick={() => { s.deleteProduct(p.id); setConfirmDel(false); toast("Producto eliminado"); navigate({ to: "/empresario/menu" }); }}>Sí, eliminar</PrimaryButton>
        </DialogContent>
      </Dialog>
    </div>
  );
}
