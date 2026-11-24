import { useState, type ReactNode } from "react";
import { MapPin, Check } from "lucide-react";
import { Sheet, SheetContent, SheetHeader, SheetTitle } from "@/components/ui/sheet";
import { deliveryPoints } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { toast } from "sonner";
import { cn } from "@/lib/utils";

export function PointPicker({ trigger }: { trigger?: (open: () => void) => ReactNode }) {
  const [open, setOpen] = useState(false);
  const { point, pointId, setPointId } = useStore();
  return (
    <>
      {trigger ? (
        trigger(() => setOpen(true))
      ) : (
        <button onClick={() => setOpen(true)} className="flex min-w-0 items-center gap-1.5 text-left active:opacity-70">
          <MapPin className="size-4 shrink-0 text-primary" />
          <span className="min-w-0">
            <span className="block text-[11px] text-muted-foreground">Entregar en</span>
            <span className="block truncate text-sm font-bold">{point.name} ▾</span>
          </span>
        </button>
      )}
      <Sheet open={open} onOpenChange={setOpen}>
        <SheetContent side="bottom" className="mx-auto max-w-md rounded-t-3xl">
          <SheetHeader>
            <SheetTitle>¿Dónde te entregamos?</SheetTitle>
          </SheetHeader>
          <p className="px-4 text-xs text-muted-foreground">Solo verás comidas de locales que cubren este punto y tienen repartidores cerca.</p>
          <ul className="space-y-2 p-4">
            {deliveryPoints.map((p) => (
              <li key={p.id}>
                <button
                  onClick={() => {
                    setPointId(p.id);
                    setOpen(false);
                    toast(`Entregando en ${p.name}`);
                  }}
                  className={cn("flex w-full items-center gap-3 rounded-2xl border p-3 text-left active:scale-[0.98]", pointId === p.id && "border-primary bg-accent")}
                >
                  <MapPin className="size-5 text-primary" />
                  <span className="min-w-0 flex-1">
                    <span className="block font-semibold">{p.name}</span>
                    <span className="block text-xs text-muted-foreground">{p.detail}</span>
                  </span>
                  {pointId === p.id && <Check className="size-5 text-primary" />}
                </button>
              </li>
            ))}
          </ul>
        </SheetContent>
      </Sheet>
    </>
  );
}
