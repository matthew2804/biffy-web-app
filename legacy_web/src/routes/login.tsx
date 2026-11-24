import { createFileRoute, useNavigate, useRouter } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { PrimaryButton, TopBar } from "@/components/biffy/ui";
import { useStore } from "@/lib/store";
import { universities } from "@/lib/mock-data";

export const Route = createFileRoute("/login")({
  validateSearch: (s: Record<string, unknown>): { next?: string | undefined } => ({ next: typeof s["next"] === "string" ? s["next"] : undefined }),
  head: () => ({
    meta: [
      { title: "Iniciar sesión · Biffy" },
      { name: "description", content: "Entra a Biffy con tu correo universitario." },
      { property: "og:title", content: "Iniciar sesión · Biffy" },
      { property: "og:description", content: "Entra a Biffy con tu correo universitario." },
    ],
  }),
  component: Login,
});

function Login() {
  const s = useStore();
  const navigate = useNavigate();
  const router = useRouter();
  const { next } = Route.useSearch();
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [pass, setPass] = useState("");
  const [role, setRole] = useState<"student" | "courier" | "merchant">("student");

  const submit = (e: React.FormEvent): void => {
    e.preventDefault();
    if (!/^\S+@\S+\.\S+$/.test(email)) { toast.error("Correo inválido"); return; }
    if (pass.length < 6) { toast.error("La contraseña debe tener al menos 6 caracteres"); return; }
    s.login(email.trim(), name.trim());
    toast.success("¡Bienvenido a Biffy! +450 Gotas 💧");
    if (role === "merchant") { navigate({ to: "/empresario/registro" }); return; }
    if (role === "courier") { s.setMode("courier"); navigate({ to: "/repartidor" }); return; }
    if (next) router.history.push(next);
    else if (!s.surveyDone) navigate({ to: "/encuesta" });
    else navigate({ to: "/" });
  };

  return (
    <div className="min-h-dvh">
      <TopBar title="" />
      <form onSubmit={submit} className="space-y-4 px-6">
        <div className="grid size-16 place-items-center rounded-2xl bg-primary text-3xl font-extrabold text-primary-foreground">B</div>
        <h1 className="text-3xl font-extrabold">Entra a Biffy 🐝</h1>
        <p className="text-muted-foreground">{role === "student" ? "Usa tu correo universitario para verificar tu campus y desbloquear descuentos." : role === "merchant" ? "Registra tu restaurante: te pediremos datos del negocio, sedes, documentos legales y cuenta bancaria." : "Reparte en toda la ciudad. Con correo universitario también puedes repartir en tu campus."}</p>
        <div className="grid grid-cols-3 gap-2" role="radiogroup" aria-label="Tipo de cuenta">
          {([["student", "🍔", "Quiero pedir", "Comida cerca de ti"], ["courier", "🛵", "Quiero repartir", "Gana dinero entregando"], ["merchant", "🏪", "Tengo un restaurante", "Vende en Biffy"]] as const).map(([v, e, t1, t2]) => (
            <button key={v} type="button" role="radio" aria-checked={role === v} onClick={() => setRole(v)} className={"rounded-2xl border-2 p-3 text-left active:scale-95 " + (role === v ? "border-primary bg-accent" : "border-border bg-card")}>
              <span className="text-2xl">{e}</span><p className="font-bold">{t1}</p><p className="text-xs text-muted-foreground">{t2}</p>
            </button>
          ))}
        </div>
        <Field label="Nombre" value={name} onChange={setName} placeholder="Sofía Martínez" />
        <Field label="Correo" value={email} onChange={setEmail} placeholder={"tu@" + universities[0]!.domain} type="email" />
        <Field label="Contraseña" value={pass} onChange={setPass} placeholder="••••••" type="password" />
        <p className="text-xs text-muted-foreground">Dominios verificables: {universities.map((u) => "@" + u.domain).join(", ")}</p>
        <PrimaryButton type="submit">Continuar</PrimaryButton>
        <button type="button" onClick={() => navigate({ to: "/" })} className="w-full py-3 text-sm font-semibold text-muted-foreground">Seguir sin cuenta</button>
      </form>
    </div>
  );
}

function Field({ label, value, onChange, placeholder, type = "text" }: { label: string; value: string; onChange: (v: string) => void; placeholder: string; type?: string }) {
  return (
    <label className="block">
      <span className="text-sm font-semibold">{label}</span>
      <input type={type} value={value} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} className="mt-1 w-full rounded-2xl border bg-card px-4 py-3.5 outline-none focus:border-primary" />
    </label>
  );
}
