import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Send } from "lucide-react";
import { Screen, TopBar } from "@/components/biffy/ui";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/soporte")({
  head: () => seo("Soporte", "Ayuda con tus pedidos, pagos y cuenta en Biffy."),
  component: Support,
});

const faqs: [string, string][] = [
  ["Mi pedido no llegó", "Revisa el seguimiento. Si pasaron más de 15 min del tiempo estimado, escríbenos por el chat y te reembolsamos."],
  ["¿Cómo uso mis Gotas?", "En el carrito activa 'Usar mis Gotas'. 1 Gota = $10 COP."],
  ["¿Por qué no veo un restaurante?", "Solo mostramos locales cuyo radio de entrega cubre tu punto y que tienen repartidores cerca."],
  ["¿Cómo verifico mi universidad?", "En Mi campus ingresa tu correo institucional."],
];

function Support() {
  const [msgs, setMsgs] = useState<{ me: boolean; t: string }[]>([{ me: false, t: "Hola 👋 Soy Sara de soporte Biffy. ¿En qué te ayudo?" }]);
  const [v, setV] = useState("");
  return (
    <Screen nav={false}>
      <TopBar title="Ayuda y soporte" />
      <div className="space-y-4 px-4">
        <div className="grid grid-cols-2 gap-2">
          <a href="tel:+576015550000" className="rounded-2xl bg-card p-4 text-center font-semibold shadow-sm active:scale-95">📞 Llamar</a>
          <a href="https://wa.me/573005550000" target="_blank" rel="noreferrer" className="rounded-2xl bg-card p-4 text-center font-semibold shadow-sm active:scale-95">💬 WhatsApp</a>
        </div>
        <Accordion type="single" collapsible className="rounded-2xl bg-card px-4 shadow-sm">
          {faqs.map(([q, a]) => (
            <AccordionItem key={q} value={q}><AccordionTrigger>{q}</AccordionTrigger><AccordionContent>{a}</AccordionContent></AccordionItem>
          ))}
        </Accordion>
        <div className="rounded-2xl bg-card p-3 shadow-sm">
          <p className="mb-2 font-bold">Chat con soporte</p>
          <div className="space-y-2">
            {msgs.map((m, i) => <div key={i} className={m.me ? "ml-10 rounded-2xl bg-primary p-3 text-sm text-primary-foreground" : "mr-10 rounded-2xl bg-muted p-3 text-sm"}>{m.t}</div>)}
          </div>
          <form className="mt-3 flex gap-2" onSubmit={(e) => { e.preventDefault(); if (!v.trim()) return; setMsgs((m) => [...m, { me: true, t: v }]); setV(""); setTimeout(() => setMsgs((m) => [...m, { me: false, t: "Gracias, ya revisamos tu caso. Te responderemos en menos de 5 minutos." }]), 900); }}>
            <input value={v} onChange={(e) => setV(e.target.value)} placeholder="Escribe tu mensaje" className="min-w-0 flex-1 rounded-xl border p-3" />
            <button aria-label="Enviar" className="grid size-12 place-items-center rounded-xl bg-primary text-primary-foreground"><Send className="size-5" /></button>
          </form>
        </div>
      </div>
    </Screen>
  );
}
