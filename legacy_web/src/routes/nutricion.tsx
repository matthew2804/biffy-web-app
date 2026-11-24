import { createFileRoute } from "@tanstack/react-router";
import { useState } from "react";
import { Screen, TopBar, Carousel, Chip, DishCard, RestaurantCard, SectionTitle, Empty } from "@/components/biffy/ui";
import { useStore } from "@/lib/store";
import { restaurantById } from "@/lib/mock-data";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/nutricion")({
  head: () => seo("Calorías y nutrientes", "Restaurantes cerca de ti que muestran calorías, proteína, carbohidratos y grasas."),
  component: Nutricion,
});

const caps = [400, 600, 800, 1200] as const;
type Sort = "kcal" | "protein";

function Nutricion() {
  const s = useStore();
  const [cap, setCap] = useState<number | null>(null);
  const [minProtein, setMinProtein] = useState(false);
  const [sort, setSort] = useState<Sort>("kcal");
  const rests = s.reachableRestaurants.filter((r) => r.showsNutrition);
  const list = s.reachableDishes
    .filter((d) => d.nutrition && restaurantById(d.restaurantId)?.showsNutrition)
    .filter((d) => (cap ? d.nutrition!.kcal <= cap : true) && (minProtein ? d.nutrition!.protein >= 25 : true))
    .sort((a, b) => (sort === "kcal" ? a.nutrition!.kcal - b.nutrition!.kcal : b.nutrition!.protein - a.nutrition!.protein));

  return (
    <Screen>
      <TopBar title="Calorías y nutrientes" />
      <div className="px-4">
        <div className="rounded-3xl bg-success/15 p-4 text-sm"><b>🥦 Come con información.</b> Aquí solo aparecen restaurantes que reportan calorías y nutrientes de sus platos.</div>
        <Carousel className="mt-3">
          <Chip active={!cap} onClick={() => setCap(null)}>Todas las kcal</Chip>
          {caps.map((c) => <Chip key={c} active={cap === c} onClick={() => setCap(c)}>≤ {c} kcal</Chip>)}
          <Chip active={minProtein} onClick={() => setMinProtein(!minProtein)}>💪 25 g+ proteína</Chip>
        </Carousel>
        <Carousel className="mt-2">
          <Chip active={sort === "kcal"} onClick={() => setSort("kcal")}>↑ Menos calorías</Chip>
          <Chip active={sort === "protein"} onClick={() => setSort("protein")}>↓ Más proteína</Chip>
        </Carousel>
        {rests.length === 0 ? <Empty emoji="📍" title="No hay restaurantes con nutrición cerca" body="Cambia tu punto de entrega." /> : (
          <>
            <SectionTitle title="Restaurantes" />
            <Carousel>{rests.map((r) => <RestaurantCard key={r.id} r={r} />)}</Carousel>
            <SectionTitle title={`${list.length} platos`} />
            {list.length === 0 ? <Empty emoji="🔍" title="Ningún plato cumple el filtro" /> : (
              <div className="grid grid-cols-2 gap-3">{list.map((d) => (
                <div key={d.id}>
                  <DishCard dish={d} wide />
                  <p className="mt-1 px-1 text-[11px] font-semibold text-muted-foreground">{d.nutrition!.kcal} kcal · P {d.nutrition!.protein} g · C {d.nutrition!.carbs} g · G {d.nutrition!.fat} g</p>
                </div>
              ))}</div>
            )}
          </>
        )}
      </div>
    </Screen>
  );
}
