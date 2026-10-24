import { createFileRoute } from "@tanstack/react-router";
import { useEffect } from "react";
import { toast } from "sonner";
import { Screen, TopBar } from "@/components/biffy/ui";
import { PointPicker } from "@/components/biffy/point-picker";
import { Switch } from "@/components/ui/switch";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/ajustes")({
  head: () => seo("Configuración", "Notificaciones, apariencia, ubicación y seguridad."),
  component: Settings,
});

function Settings() {
  const s = useStore();
  useEffect(() => {
    document.documentElement.classList.toggle("dark", s.settings.dark);
  }, [s.settings.dark]);
  const rows: { k: keyof typeof s.settings; l: string }[] = [
    { k: "push", l: "Notificaciones push" },
    { k: "promos", l: "Promociones y descuentos" },
    { k: "email", l: "Resumen por correo" },
    { k: "dark", l: "Modo oscuro" },
  ];
  return (
    <Screen nav={false}>
      <TopBar title="Configuración" />
      <div className="space-y-4 px-4">
        <div className="overflow-hidden rounded-2xl bg-card shadow-sm">
          {rows.map((r) => (
            <label key={r.k} className="flex min-h-14 items-center justify-between border-b px-4 last:border-0">
              <span className="font-semibold">{r.l}</span>
              <Switch checked={s.settings[r.k]} onCheckedChange={(v) => s.setSettings((x) => ({ ...x, [r.k]: v }))} />
            </label>
          ))}
        </div>
        <div className="rounded-2xl bg-card p-4 shadow-sm">
          <p className="mb-2 font-bold">Ubicación de entrega</p>
          <PointPicker />
        </div>
        <div className="overflow-hidden rounded-2xl bg-card shadow-sm">
          <button onClick={() => toast("Te enviamos un enlace para cambiar tu contraseña")} className="min-h-14 w-full border-b px-4 text-left font-semibold active:bg-muted">🔑 Cambiar contraseña</button>
          <button onClick={() => toast("Sesiones de otros dispositivos cerradas")} className="min-h-14 w-full border-b px-4 text-left font-semibold active:bg-muted">📱 Cerrar sesión en otros dispositivos</button>
          <button onClick={() => toast("Solicitud de eliminación enviada. Te contactaremos por correo.")} className="min-h-14 w-full px-4 text-left font-semibold text-danger active:bg-muted">🗑️ Eliminar mi cuenta</button>
        </div>
        <p className="text-center text-xs text-muted-foreground">Biffy v1.0 · Términos · Privacidad</p>
      </div>
    </Screen>
  );
}
