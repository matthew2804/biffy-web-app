import { createFileRoute, Link } from "@tanstack/react-router";
import { useState } from "react";
import { toast } from "sonner";
import { Screen, TopBar, Empty, RestaurantCard, DishCard, SectionTitle, Carousel, PrimaryButton } from "@/components/biffy/ui";
import { useStore } from "@/lib/store";
import { universities } from "@/lib/mock-data";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/campus")({
  head: () => seo("Mi campus", "Pide de los locales de tu universidad con descuento de estudiante."),
  component: Campus,
});

function Campus() {
  const s = useStore();
  const [email, setEmail] = useState("");

  if (!s.loggedIn)
    return <Screen nav={false}><TopBar title="Mi campus" /><Empty emoji="🎓" title="Inicia sesión para entrar a tu campus" action={<Link to="/login" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Iniciar sesión</Link>} /></Screen>;

  if (!s.user?.verified)
    return (
      <Screen nav={false}>
        <TopBar title="Mi campus" />
        <div className="px-4">
          <div className="rounded-3xl bg-primary p-5 text-primary-foreground">
            <p className="text-4xl">🔒🎓</p>
            <p className="mt-2 text-xl font-extrabold">Verifica tu universidad</p>
            <p className="mt-1 text-sm opacity-90">Solo estudiantes verificados pueden pedir en los locales de su campus y obtener descuentos exclusivos.</p>
          </div>
          <label className="mt-4 block text-sm font-semibold">Correo institucional</label>
          <input value={email} onChange={(e) => setEmail(e.target.value)} type="email" placeholder={"tu@" + universities[0]!.domain} className="mt-1 w-full rounded-2xl border bg-card px-4 py-3.5 outline-none focus:border-primary" />
          <p className="mt-2 text-xs text-muted-foreground">Aceptamos: {universities.map((u) => "@" + u.domain).join(", ")}</p>
          <PrimaryButton className="mt-4" onClick={() => (s.verifyUniversity(email) ? toast.success("¡Universidad verificada! 🎉") : toast.error("Ese correo no pertenece a una universidad aliada"))}>Verificar mi universidad</PrimaryButton>
        </div>
      </Screen>
    );

  const campusRests = s.reachableRestaurants.filter((r) => r.campusId === s.user!.universityId);
  const campusDishes = s.reachableDishes.filter((d) => campusRests.some((r) => r.id === d.restaurantId));

  return (
    <Screen nav={false}>
      <TopBar title="Mi campus" />
      <div className="px-4">
        <div className="rounded-3xl bg-primary p-5 text-primary-foreground">
          <p className="text-sm font-semibold opacity-90">✅ Estudiante verificado</p>
          <p className="text-xl font-extrabold">{s.university?.name}</p>
          <p className="mt-1 text-sm opacity-90">Descuentos exclusivos en {campusRests.length} locales del campus.</p>
        </div>
        {campusRests.length === 0 ? (
          <Empty emoji="📍" title="No hay locales de tu campus que lleguen aquí" body="Cambia tu punto de entrega a uno dentro del campus." />
        ) : (
          <>
            <SectionTitle title="Locales del campus" />
            <div className="space-y-3">{campusRests.map((r) => <RestaurantCard key={r.id} r={r} wide />)}</div>
            <SectionTitle title="Con descuento hoy" action={<Link to="/explorar" search={{ campus: true }} className="text-sm font-bold text-primary">Ver todo</Link>} />
            <Carousel>{campusDishes.map((d) => <DishCard key={d.id} dish={d} />)}</Carousel>
          </>
        )}
      </div>
    </Screen>
  );
}
