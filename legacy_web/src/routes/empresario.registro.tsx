import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { Plus, Trash2 } from "lucide-react";
import { useState } from "react";
import { toast } from "sonner";
import { PrimaryButton, TopBar, Chip } from "@/components/biffy/ui";
import { Card, FilePicker, PhotoPicker, TextField, Toggle } from "@/components/biffy/merchant-ui";
import { useStore } from "@/lib/store";
import { categories, universities } from "@/lib/mock-data";
import { banks, docCatalog, sedeLocations, BIFFY_COMMISSION, type MerchantProfile, type Sede } from "@/lib/merchant";
import { demoProducts, demoProfile } from "@/lib/merchant-demo";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/empresario/registro")({
  head: () => seo("Registra tu restaurante", "Vende en Biffy: datos del negocio, sedes, documentos legales y cuenta bancaria."),
  component: Registro,
});

const steps = ["Responsable", "Negocio", "Sedes", "Legal y DIAN", "Pagos", "Confirmar"];
const days = ["Dom", "Lun", "Mar", "Mié", "Jue", "Vie", "Sáb"];

const blankSede = (id: string): Sede => ({ id, name: "", address: "", city: "Bogotá", locId: "", phone: "", open: 10, close: 21, closedDays: [], radiusKm: 3, campusId: undefined, discount: 0.1 });

function Registro() {
  const s = useStore();
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [terms, setTerms] = useState(false);
  const [data, setData] = useState(false);
  const [m, setM] = useState<MerchantProfile>({
    ownerName: s.user?.name ?? "", docType: "CC", docNumber: "", ownerRole: "Propietario", phone: "", email: s.user?.email ?? "",
    brand: "", legalName: "", nit: "", personType: "natural", cuisine: "almuerzo", description: "", logo: "",
    sedes: [blankSede("s1")], incResponsible: true, docs: {}, bank: { bank: "", type: "ahorros", number: "", holder: "" },
    showsNutrition: false, paused: false,
  });
  const set = (p: Partial<MerchantProfile>) => setM((x) => ({ ...x, ...p }));
  const setSede = (id: string, p: Partial<Sede>) => set({ sedes: m.sedes.map((x) => (x.id === id ? { ...x, ...p } : x)) });

  const errors = (): string[] => {
    const e: string[] = [];
    if (step === 0) {
      if (m.ownerName.trim().length < 5) e.push("Nombre completo del responsable");
      if (!/^\d{6,10}$/.test(m.docNumber)) e.push("Número de documento (6 a 10 dígitos)");
      if (!/^3\d{9}$/.test(m.phone)) e.push("Celular colombiano de 10 dígitos");
      if (!/^\S+@\S+\.\S+$/.test(m.email)) e.push("Correo de contacto");
    }
    if (step === 1) {
      if (m.brand.trim().length < 2) e.push("Nombre comercial");
      if (m.legalName.trim().length < 3) e.push("Razón social / nombre en el RUT");
      if (!/^\d{9,10}-\d$/.test(m.nit)) e.push("NIT con dígito de verificación (ej. 901234567-8)");
      if (m.description.trim().length < 15) e.push("Descripción del restaurante (mín. 15 caracteres)");
      if (!m.logo) e.push("Logo o foto de portada");
    }
    if (step === 2) {
      m.sedes.forEach((x, i) => {
        if (!x.name.trim() || !x.address.trim() || !x.locId) e.push(`Sede ${i + 1}: nombre, dirección y zona`);
        if (!/^3\d{9}$|^60\d{8}$/.test(x.phone)) e.push(`Sede ${i + 1}: teléfono válido`);
        if (x.close <= x.open) e.push(`Sede ${i + 1}: la hora de cierre debe ser después de la apertura`);
        if (x.closedDays.length === 7) e.push(`Sede ${i + 1}: debe abrir al menos un día`);
      });
    }
    if (step === 3) {
      for (const d of docCatalog) if ((!d.onlyJuridica || m.personType === "juridica") && !m.docs[d.id]) e.push(d.label);
    }
    if (step === 4) {
      if (!m.bank.bank) e.push("Banco");
      if (!/^\d{6,20}$/.test(m.bank.number)) e.push("Número de cuenta (solo dígitos)");
      if (m.bank.holder.trim().length < 3) e.push("Titular de la cuenta");
    }
    if (step === 5) {
      if (!terms) e.push("Acepta los términos para comercios");
      if (!data) e.push("Autoriza el tratamiento de datos");
    }
    return e;
  };
  const errs = errors();

  const next = () => {
    if (errs.length) { toast.error("Completa: " + errs[0]); return; }
    if (step < steps.length - 1) { setStep(step + 1); window.scrollTo(0, 0); return; }
    if (!s.loggedIn) s.login(m.email, m.ownerName);
    s.registerMerchant(m);
    toast.success("¡Restaurante registrado! Ahora crea tus productos 🍽️");
    navigate({ to: "/empresario/menu" });
  };

  const demo = () => {
    if (!s.loggedIn) s.login("laura@wokroll.co", demoProfile.ownerName);
    s.registerMerchant({ ...demoProfile, email: "laura@wokroll.co" }, demoProducts);
    toast.success("Demo cargada: Wok & Roll");
    navigate({ to: "/empresario" });
  };

  return (
    <div className="min-h-dvh pb-32">
      <TopBar title="Registra tu restaurante" />
      <div className="px-4">
        <div className="flex gap-1">{steps.map((x, i) => <span key={x} className={cn("h-1.5 flex-1 rounded-full", i <= step ? "bg-primary" : "bg-border")} />)}</div>
        <p className="mt-2 text-xs font-semibold text-muted-foreground">Paso {step + 1} de {steps.length} · {steps[step]}</p>
        {step === 0 && <button onClick={demo} className="mt-2 text-sm font-bold text-primary underline">Autocompletar con restaurante demo</button>}

        <div className="mt-4 space-y-4">
          {step === 0 && (
            <Card title="Responsable de la cuenta">
              <div className="space-y-3">
                <TextField label="Nombre completo" required value={m.ownerName} onChange={(v) => set({ ownerName: v })} placeholder="Laura Gómez" />
                <div>
                  <span className="text-sm font-semibold">Tipo de documento</span>
                  <div className="mt-1 flex gap-2">{(["CC", "CE", "PPT"] as const).map((t) => <Chip key={t} active={m.docType === t} onClick={() => set({ docType: t })}>{t}</Chip>)}</div>
                </div>
                <TextField label="Número de documento" required inputMode="numeric" value={m.docNumber} onChange={(v) => set({ docNumber: v.replace(/\D/g, "") })} />
                <TextField label="Cargo" value={m.ownerRole} onChange={(v) => set({ ownerRole: v })} />
                <TextField label="Celular" required inputMode="numeric" value={m.phone} onChange={(v) => set({ phone: v.replace(/\D/g, "").slice(0, 10) })} placeholder="3001234567" />
                <TextField label="Correo de contacto" required type="email" value={m.email} onChange={(v) => set({ email: v })} />
              </div>
            </Card>
          )}

          {step === 1 && (
            <Card title="Datos del negocio">
              <div className="space-y-3">
                <PhotoPicker minPx={300} onPick={(u) => set({ logo: u })} className="flex w-full items-center gap-3 rounded-2xl border-2 border-dashed p-3 text-left active:scale-[0.99]">
                  {m.logo ? <img src={m.logo} alt="Logo" className="size-16 rounded-2xl object-cover" /> : <span className="grid size-16 place-items-center rounded-2xl bg-accent text-2xl">📷</span>}
                  <span><b className="block text-sm">Logo o portada <span className="text-danger">*</span></b><span className="text-xs text-muted-foreground">JPG/PNG, mín. 300×300 px</span></span>
                </PhotoPicker>
                <TextField label="Nombre comercial" required value={m.brand} onChange={(v) => set({ brand: v })} max={30} placeholder="Wok & Roll" />
                <div>
                  <span className="text-sm font-semibold">Tipo de persona</span>
                  <div className="mt-1 flex gap-2"><Chip active={m.personType === "natural"} onClick={() => set({ personType: "natural" })}>Persona natural</Chip><Chip active={m.personType === "juridica"} onClick={() => set({ personType: "juridica" })}>Persona jurídica</Chip></div>
                </div>
                <TextField label="Razón social (como aparece en el RUT)" required value={m.legalName} onChange={(v) => set({ legalName: v })} />
                <TextField label="NIT" required value={m.nit} onChange={(v) => set({ nit: v.replace(/[^\d-]/g, "") })} placeholder="901234567-8" hint="Incluye el dígito de verificación" />
                <div>
                  <span className="text-sm font-semibold">Tipo de cocina principal</span>
                  <div className="no-scrollbar mt-1 flex gap-2 overflow-x-auto">{categories.map((c) => <Chip key={c.id} active={m.cuisine === c.id} onClick={() => set({ cuisine: c.id })}>{c.emoji} {c.label}</Chip>)}</div>
                </div>
                <TextField label="Descripción corta" required value={m.description} onChange={(v) => set({ description: v })} max={80} placeholder="Bowls asiáticos hechos al momento" />
              </div>
            </Card>
          )}

          {step === 2 && (
            <>
              {m.sedes.map((x, i) => (
                <Card key={x.id} title={`Sede ${i + 1}`} right={m.sedes.length > 1 && <button aria-label="Quitar sede" onClick={() => set({ sedes: m.sedes.filter((y) => y.id !== x.id) })} className="text-danger"><Trash2 className="size-5" /></button>}>
                  <div className="space-y-3">
                    <TextField label="Nombre de la sede" required value={x.name} onChange={(v) => setSede(x.id, { name: v })} placeholder="Chapinero" />
                    <TextField label="Dirección" required value={x.address} onChange={(v) => setSede(x.id, { address: v })} placeholder="Calle 45 #18-22" />
                    <TextField label="Ciudad" value={x.city} onChange={(v) => setSede(x.id, { city: v })} />
                    <div>
                      <span className="text-sm font-semibold">Ubicación en el mapa <span className="text-danger">*</span></span>
                      <div className="mt-1 space-y-1.5">{sedeLocations.map((l) => (
                        <button key={l.id} type="button" onClick={() => setSede(x.id, { locId: l.id })} className={cn("flex w-full items-center gap-2 rounded-xl border p-2.5 text-left text-sm active:scale-[0.99]", x.locId === l.id && "border-primary bg-accent font-bold")}>📍 {l.label}</button>
                      ))}</div>
                    </div>
                    <TextField label="Teléfono de la sede" required inputMode="numeric" value={x.phone} onChange={(v) => setSede(x.id, { phone: v.replace(/\D/g, "").slice(0, 10) })} />
                    <div className="grid grid-cols-2 gap-2">
                      <label className="text-sm font-semibold">Abre<select value={x.open} onChange={(e) => setSede(x.id, { open: +e.target.value })} className="mt-1 w-full rounded-2xl border bg-background p-3">{Array.from({ length: 24 }, (_, h) => <option key={h} value={h}>{h}:00</option>)}</select></label>
                      <label className="text-sm font-semibold">Cierra<select value={x.close} onChange={(e) => setSede(x.id, { close: +e.target.value })} className="mt-1 w-full rounded-2xl border bg-background p-3">{Array.from({ length: 24 }, (_, h) => <option key={h} value={h + 1}>{h + 1}:00</option>)}</select></label>
                    </div>
                    <div>
                      <span className="text-sm font-semibold">Días cerrado</span>
                      <div className="mt-1 flex flex-wrap gap-1.5">{days.map((d, di) => <Chip key={d} active={x.closedDays.includes(di)} onClick={() => setSede(x.id, { closedDays: x.closedDays.includes(di) ? x.closedDays.filter((y) => y !== di) : [...x.closedDays, di] })}>{d}</Chip>)}</div>
                    </div>
                    <label className="block text-sm font-semibold">Radio de entrega: {x.radiusKm} km
                      <input type="range" min={1} max={8} step={0.5} value={x.radiusKm} onChange={(e) => setSede(x.id, { radiusKm: +e.target.value })} className="mt-2 w-full accent-[var(--color-primary)]" />
                    </label>
                    <div>
                      <span className="text-sm font-semibold">¿Está dentro de una universidad?</span>
                      <div className="mt-1 flex flex-wrap gap-1.5">
                        <Chip active={!x.campusId} onClick={() => setSede(x.id, { campusId: undefined })}>No</Chip>
                        {universities.map((u) => <Chip key={u.id} active={x.campusId === u.id} onClick={() => setSede(x.id, { campusId: u.id })}>🎓 {u.name}</Chip>)}
                      </div>
                      {x.campusId && <label className="mt-2 block text-sm">Descuento a estudiantes verificados: <b>{Math.round(x.discount * 100)}%</b><input type="range" min={0.05} max={0.3} step={0.05} value={x.discount} onChange={(e) => setSede(x.id, { discount: +e.target.value })} className="mt-1 w-full" /></label>}
                    </div>
                  </div>
                </Card>
              ))}
              <button onClick={() => set({ sedes: [...m.sedes, blankSede("s" + (Date.now() % 100000))] })} className="flex w-full items-center justify-center gap-2 rounded-2xl border-2 border-dashed p-3 font-bold text-primary active:scale-[0.99]"><Plus className="size-5" /> Agregar otra sede</button>
            </>
          )}

          {step === 3 && (
            <>
              <Card title="Responsabilidad tributaria (DIAN)">
                <p className="text-xs text-muted-foreground">Según tu RUT. Los restaurantes responsables del Impuesto Nacional al Consumo deben cobrar el 8% incluido en el precio; no es opcional.</p>
                <div className="mt-3 space-y-2">
                  <button onClick={() => set({ incResponsible: true })} className={cn("w-full rounded-2xl border p-3 text-left text-sm active:scale-[0.99]", m.incResponsible && "border-primary bg-accent")}><b>Responsable de INC (8%)</b><br /><span className="text-xs">Se aplicará obligatoriamente a todos tus productos.</span></button>
                  <button onClick={() => set({ incResponsible: false })} className={cn("w-full rounded-2xl border p-3 text-left text-sm active:scale-[0.99]", !m.incResponsible && "border-primary bg-accent")}><b>No responsable de INC</b><br /><span className="text-xs">Ingresos menores a 3.500 UVT y no franquicia. Debe constar en tu RUT.</span></button>
                </div>
                <p className="mt-3 rounded-xl bg-secondary/20 p-2 text-xs font-semibold">🧾 Facturación electrónica: Biffy emite la factura de cada pedido a nombre de tu NIT (obligatorio DIAN).</p>
              </Card>
              <Card title="Documentos legales">
                <div className="space-y-2">
                  {docCatalog.filter((d) => !d.onlyJuridica || m.personType === "juridica").map((d) => (
                    <FilePicker key={d.id} label={d.label} hint={d.hint} value={m.docs[d.id]} onPick={(n) => set({ docs: { ...m.docs, [d.id]: n } })} />
                  ))}
                </div>
              </Card>
            </>
          )}

          {step === 4 && (
            <Card title="Cuenta para recibir pagos">
              <p className="mb-3 text-xs text-muted-foreground">Biffy liquida tus ventas cada quincena, descontando la comisión ({Math.round(BIFFY_COMMISSION * 100)}%). La cuenta debe estar a nombre del titular del RUT.</p>
              <div className="space-y-3">
                <div><span className="text-sm font-semibold">Banco <span className="text-danger">*</span></span><div className="mt-1 flex flex-wrap gap-1.5">{banks.map((b) => <Chip key={b} active={m.bank.bank === b} onClick={() => set({ bank: { ...m.bank, bank: b } })}>{b}</Chip>)}</div></div>
                <div><span className="text-sm font-semibold">Tipo de cuenta</span><div className="mt-1 flex gap-2"><Chip active={m.bank.type === "ahorros"} onClick={() => set({ bank: { ...m.bank, type: "ahorros" } })}>Ahorros</Chip><Chip active={m.bank.type === "corriente"} onClick={() => set({ bank: { ...m.bank, type: "corriente" } })}>Corriente</Chip></div></div>
                <TextField label="Número de cuenta" required inputMode="numeric" value={m.bank.number} onChange={(v) => set({ bank: { ...m.bank, number: v.replace(/\D/g, "") } })} />
                <TextField label="Titular" required value={m.bank.holder} onChange={(v) => set({ bank: { ...m.bank, holder: v } })} placeholder={m.legalName} />
              </div>
            </Card>
          )}

          {step === 5 && (
            <>
              <Card title="Preferencias del menú">
                <Toggle checked={m.showsNutrition} onChange={(v) => set({ showsNutrition: v })} label="Mostrar calorías y nutrientes" body="Al activarlo, cada producto deberá incluir calorías, proteína, carbohidratos y grasas. Aparecerás en la sección de nutrición para clientes." />
              </Card>
              <Card title="Resumen">
                <ul className="space-y-1 text-sm">
                  <li>🏪 <b>{m.brand}</b> · {m.legalName} · NIT {m.nit}</li>
                  <li>📍 {m.sedes.length} sede(s): {m.sedes.map((x) => x.name).join(", ")}</li>
                  <li>🧾 {m.incResponsible ? "INC 8% incluido (obligatorio)" : "No responsable de INC"}</li>
                  <li>🏦 {m.bank.bank} {m.bank.type} ••••{m.bank.number.slice(-4)}</li>
                </ul>
              </Card>
              <label className="flex items-start gap-3 text-sm"><input type="checkbox" checked={terms} onChange={(e) => setTerms(e.target.checked)} className="mt-1 size-5" />Acepto los términos y condiciones para comercios aliados, incluida la comisión del {Math.round(BIFFY_COMMISSION * 100)}% por pedido.</label>
              <label className="flex items-start gap-3 text-sm"><input type="checkbox" checked={data} onChange={(e) => setData(e.target.checked)} className="mt-1 size-5" />Autorizo el tratamiento de mis datos personales (Ley 1581 de 2012).</label>
            </>
          )}
        </div>
      </div>

      <div className="fixed inset-x-0 bottom-0 z-40 mx-auto flex max-w-md gap-2 border-t bg-card p-4 pb-[max(env(safe-area-inset-bottom),1rem)]">
        {step > 0 && <button onClick={() => setStep(step - 1)} className="rounded-2xl bg-muted px-5 font-bold active:scale-95">Atrás</button>}
        <PrimaryButton onClick={next} className={errs.length ? "opacity-60" : ""}>{step === steps.length - 1 ? "Enviar y activar restaurante" : "Siguiente"}</PrimaryButton>
      </div>
    </div>
  );
}
