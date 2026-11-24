import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Chip, PrimaryButton, TopBar } from "@/components/biffy/ui";
import { Slider } from "@/components/ui/slider";
import { allergyOptions, lifestyleOptions, tasteOptions } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { cop } from "@/lib/format";
import { seo } from "@/lib/seo";
import { cn } from "@/lib/utils";

export const Route = createFileRoute("/encuesta")({
  head: () => seo("Tus filtros", "Cuéntanos tus gustos, alergias y presupuesto."),
  component: Survey,
});

function Survey() {
  const s = useStore();
  const navigate = useNavigate();
  const [step, setStep] = useState(0);
  const [likes, setLikes] = useState<string[]>(s.prefs.likes);
  const [allergies, setAllergies] = useState<string[]>(s.prefs.allergies);
  const [lifestyle, setLifestyle] = useState<string[]>(s.prefs.lifestyle);
  const [budget, setBudget] = useState(s.prefs.budget);
  const tog = (set: React.Dispatch<React.SetStateAction<string[]>>, v: string) => set((x) => (x.includes(v) ? x.filter((y) => y !== v) : [...x, v]));

  const finish = () => {
    const first = !s.surveyDone;
    s.completeSurvey({ likes, allergies, lifestyle, budget });
    toast.success(first ? "¡Listo! Ganaste 300 Gotas 💧" : "Preferencias actualizadas");
    navigate({ to: "/" });
  };

  return (
    <div className="flex min-h-dvh flex-col">
      <TopBar title={`Paso ${step + 1} de 3`} />
      <div className="px-4">
        <div className="flex gap-1.5">{[0, 1, 2].map((i) => <div key={i} className={cn("h-1.5 flex-1 rounded-full", i <= step ? "bg-primary" : "bg-muted")} />)}</div>
        {!s.surveyDone && <p className="mt-3 rounded-xl bg-secondary/25 p-2 text-center text-sm font-semibold">Completa los 3 pasos y gana 300 Gotas 💧</p>}
      </div>
      <div className="flex-1 px-4 pt-4">
        {step === 0 && (
          <>
            <h1 className="text-2xl font-extrabold">¿Qué se te antoja normalmente?</h1>
            <p className="text-muted-foreground">Elige tus favoritos.</p>
            <div className="mt-4 grid grid-cols-2 gap-3">
              {tasteOptions.map((t) => (
                <button key={t.id} onClick={() => tog(setLikes, t.id)} className={cn("rounded-2xl border-2 bg-card p-4 text-left active:scale-95", likes.includes(t.id) && "border-primary bg-accent")}>
                  <span className="text-3xl">{t.emoji}</span>
                  <span className="mt-1 block font-semibold">{t.label}</span>
                </button>
              ))}
            </div>
          </>
        )}
        {step === 1 && (
          <>
            <h1 className="text-2xl font-extrabold">Estilo de vida y alergias</h1>
            <p className="text-muted-foreground">Tu seguridad es primero: ocultaremos o advertiremos platos con tus alérgenos.</p>
            <h2 className="mt-4 font-bold">Estilo de vida</h2>
            <div className="mt-2 flex flex-wrap gap-2">{lifestyleOptions.map((x) => <Chip key={x} active={lifestyle.includes(x)} onClick={() => tog(setLifestyle, x)}>{x}</Chip>)}</div>
            <h2 className="mt-5 font-bold">Alergias o intolerancias</h2>
            <div className="mt-2 flex flex-wrap gap-2">{allergyOptions.map((x) => <Chip key={x} active={allergies.includes(x)} onClick={() => tog(setAllergies, x)}>⚠️ {x}</Chip>)}</div>
          </>
        )}
        {step === 2 && (
          <>
            <h1 className="text-2xl font-extrabold">¿Cuál es tu presupuesto por comida?</h1>
            <p className="mt-8 text-center text-4xl font-extrabold text-primary">{cop(budget)}</p>
            <Slider className="mt-6" min={5000} max={50000} step={1000} value={[budget]} onValueChange={(v) => setBudget(v[0] ?? budget)} />
            <div className="mt-2 flex justify-between text-xs text-muted-foreground"><span>$5.000</span><span>$50.000</span></div>
          </>
        )}
      </div>
      <div className="flex gap-2 p-4 pb-[max(env(safe-area-inset-bottom),1rem)]">
        {step > 0 && <button onClick={() => setStep(step - 1)} className="rounded-2xl border px-5 font-semibold active:scale-95">Atrás</button>}
        <PrimaryButton disabled={step === 0 && !likes.length} onClick={() => (step < 2 ? setStep(step + 1) : finish())}>{step < 2 ? "Siguiente" : "Terminar"}</PrimaryButton>
      </div>
    </div>
  );
}
