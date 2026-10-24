import { createFileRoute, useNavigate } from "@tanstack/react-router";
import { useEffect } from "react";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/demo/qbano")({
  head: () => seo("Qbano en Icesi · Demostración", "Prueba una compra simulada de Qbano con Biffy AI y entrega dentro de Icesi."),
  component: QbanoDemo,
});

// Prepara la compradora de Icesi y entra directo al Inicio normal de la app (el splash de la abeja se ve al abrir).
function QbanoDemo() {
  const s = useStore();
  const navigate = useNavigate();
  useEffect(() => {
    s.startQbanoDemo();
    navigate({ to: "/", replace: true });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);
  return null;
}
