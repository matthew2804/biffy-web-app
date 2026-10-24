import { Link } from "@tanstack/react-router";
import { Bell, Store } from "lucide-react";
import { useRef, type ReactNode } from "react";
import { toast } from "sonner";
import { useStore } from "@/lib/store";
import { cn } from "@/lib/utils";

export function MerchantHeader({ title, subtitle, right }: { title: string; subtitle?: string; right?: ReactNode }) {
  const s = useStore();
  const unread = s.notifications.filter((n) => !n.read).length;
  return (
    <header className="px-4 pt-[max(env(safe-area-inset-top),1rem)]">
      <div className="flex items-center justify-between gap-2">
        <span className="flex min-w-0 items-center gap-2 rounded-full bg-accent px-3 py-2 text-sm font-bold text-accent-foreground">
          <Store className="size-4 shrink-0" /> <span className="truncate">{s.merchant?.brand ?? "Mi restaurante"}</span>
        </span>
        <Link to="/notificaciones" aria-label="Notificaciones" className="relative grid size-11 place-items-center rounded-full bg-card shadow-sm active:scale-95">
          <Bell className="size-5" />
          {unread > 0 && <span className="absolute right-1.5 top-1.5 size-2.5 rounded-full bg-danger" />}
        </Link>
      </div>
      <div className="mt-4 flex items-end justify-between gap-3">
        <div className="min-w-0">
          <h1 className="text-2xl font-extrabold">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
        </div>
        {right}
      </div>
    </header>
  );
}

export function NoMerchant() {
  return (
    <div className="flex min-h-dvh flex-col items-center justify-center px-6 text-center">
      <p className="text-5xl">🏪</p>
      <p className="mt-3 text-lg font-bold">Aún no tienes un restaurante registrado</p>
      <p className="mt-1 text-sm text-muted-foreground">Completa el registro para vender en Biffy.</p>
      <Link to="/empresario/registro" className="mt-5 rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Registrar mi restaurante</Link>
    </div>
  );
}

export function Card({ children, className, title, right }: { children: ReactNode; className?: string; title?: string; right?: ReactNode }) {
  return (
    <section className={cn("rounded-3xl bg-card p-4 shadow-sm", className)}>
      {title && <div className="mb-3 flex items-center justify-between gap-2"><h2 className="font-bold">{title}</h2>{right}</div>}
      {children}
    </section>
  );
}

export function TextField({ label, value, onChange, placeholder, type = "text", required, hint, max, inputMode }: { label: string; value: string; onChange: (v: string) => void; placeholder?: string; type?: string; required?: boolean; hint?: string | undefined; max?: number; inputMode?: React.HTMLAttributes<HTMLInputElement>["inputMode"] }) {
  return (
    <label className="block">
      <span className="flex justify-between text-sm font-semibold"><span>{label}{required && <span className="text-danger"> *</span>}</span>{max && <span className="text-xs text-muted-foreground">{value.length}/{max}</span>}</span>
      <input type={type} inputMode={inputMode} value={value} maxLength={max} onChange={(e) => onChange(e.target.value)} placeholder={placeholder} className="mt-1 w-full rounded-2xl border bg-background px-4 py-3 outline-none focus:border-primary" />
      {hint && <span className="mt-1 block text-xs text-muted-foreground">{hint}</span>}
    </label>
  );
}

export function Toggle({ checked, onChange, label, body, disabled }: { checked: boolean; onChange: (v: boolean) => void; label: string; body?: string; disabled?: boolean }) {
  return (
    <button type="button" role="switch" aria-checked={checked} disabled={disabled} onClick={() => onChange(!checked)} className="flex w-full items-center gap-3 rounded-2xl bg-muted p-3 text-left active:scale-[0.99] disabled:opacity-70">
      <span className="min-w-0 flex-1"><span className="block text-sm font-bold">{label}</span>{body && <span className="block text-xs text-muted-foreground">{body}</span>}</span>
      <span className={cn("flex h-7 w-12 shrink-0 items-center rounded-full p-1 transition-colors", checked ? "justify-end bg-success" : "justify-start bg-border")}>
        <span className="size-5 rounded-full bg-card shadow" />
      </span>
    </button>
  );
}

/** Reads an image file into a data URL after checking type, size and minimum resolution. */
export function PhotoPicker({ onPick, children, className, minPx = 600 }: { onPick: (url: string) => void; children: ReactNode; className?: string; minPx?: number }) {
  const ref = useRef<HTMLInputElement>(null);
  const handle = (f: File | undefined) => {
    if (!f) return;
    if (!["image/jpeg", "image/png", "image/webp"].includes(f.type)) { toast.error("Usa una imagen JPG, PNG o WEBP"); return; }
    if (f.size > 5 * 1024 * 1024) { toast.error("La imagen debe pesar menos de 5 MB"); return; }
    const reader = new FileReader();
    reader.onload = () => {
      const url = String(reader.result);
      const img = new Image();
      img.onload = () => {
        if (img.width < minPx || img.height < minPx) { toast.error(`La foto debe medir al menos ${minPx}×${minPx} px (la tuya: ${img.width}×${img.height})`); return; }
        onPick(url);
      };
      img.src = url;
    };
    reader.readAsDataURL(f);
  };
  return (
    <>
      <button type="button" onClick={() => ref.current?.click()} className={className}>{children}</button>
      <input ref={ref} type="file" accept="image/jpeg,image/png,image/webp" className="hidden" onChange={(e) => { handle(e.target.files?.[0]); e.target.value = ""; }} />
    </>
  );
}

export function FilePicker({ value, onPick, label, hint }: { value?: string | undefined; onPick: (name: string) => void; label: string; hint: string }) {
  const ref = useRef<HTMLInputElement>(null);
  return (
    <div className={cn("flex items-center gap-3 rounded-2xl border p-3", value ? "border-success bg-success/10" : "bg-background")}>
      <span className="text-2xl">{value ? "✅" : "📄"}</span>
      <span className="min-w-0 flex-1"><span className="block text-sm font-bold">{label} <span className="text-danger">*</span></span><span className="block truncate text-xs text-muted-foreground">{value ?? hint}</span></span>
      <button type="button" onClick={() => ref.current?.click()} className="rounded-xl bg-primary px-3 py-2 text-xs font-bold text-primary-foreground active:scale-95">{value ? "Cambiar" : "Subir"}</button>
      <input ref={ref} type="file" accept="application/pdf,image/*" className="hidden" onChange={(e) => { const f = e.target.files?.[0]; if (f) { if (f.size > 10 * 1024 * 1024) toast.error("Máximo 10 MB"); else onPick(f.name); } e.target.value = ""; }} />
    </div>
  );
}

export const statusMeta: Record<string, { label: string; cls: string }> = {
  nuevo: { label: "⚡ Nuevo", cls: "bg-secondary text-secondary-foreground" },
  preparando: { label: "🍳 En preparación", cls: "bg-danger/15 text-danger" },
  listo: { label: "✅ Listo · buscando repartidor", cls: "bg-success/15 text-success" },
  en_camino: { label: "🛵 En camino (Biffy)", cls: "bg-accent text-accent-foreground" },
  entregado: { label: "✔ Entregado", cls: "bg-muted text-muted-foreground" },
  rechazado: { label: "✕ Rechazado", cls: "bg-danger/15 text-danger" },
};
