import { createFileRoute, Link } from "@tanstack/react-router";
import { Screen, TopBar, Empty, DishCard, RestaurantCard, SectionTitle } from "@/components/biffy/ui";
import { dishes, restaurants } from "@/lib/mock-data";
import { useStore } from "@/lib/store";
import { seo } from "@/lib/seo";

export const Route = createFileRoute("/favoritos")({
  head: () => seo("Favoritos", "Tus platos y restaurantes guardados."),
  component: Favs,
});

function Favs() {
  const s = useStore();
  const ds = dishes.filter((d) => s.favorites.includes(d.id));
  const rs = restaurants.filter((r) => s.favorites.includes(r.id));
  return (
    <Screen nav={false}>
      <TopBar title="Favoritos" />
      <div className="px-4">
        {!ds.length && !rs.length ? (
          <Empty emoji="❤️" title="Aún no tienes favoritos" body="Toca el corazón en un plato o restaurante." action={<Link to="/explorar" className="rounded-2xl bg-primary px-5 py-3 font-bold text-primary-foreground">Explorar</Link>} />
        ) : (
          <>
            {rs.length > 0 && <><SectionTitle title="Restaurantes" /><div className="space-y-3">{rs.map((r) => <RestaurantCard key={r.id} r={r} wide />)}</div></>}
            {ds.length > 0 && <><SectionTitle title="Platos" /><div className="grid grid-cols-2 gap-3">{ds.map((d) => <DishCard key={d.id} dish={d} wide />)}</div></>}
          </>
        )}
      </div>
    </Screen>
  );
}
