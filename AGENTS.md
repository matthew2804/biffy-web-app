<!-- LOVABLE:BEGIN -->
> [!IMPORTANT]
> This project is connected to [Lovable](https://lovable.dev). Avoid rewriting
> published git history — force pushing, or rebasing/amending/squashing commits
> that are already pushed — as it rewrites history on Lovable's side and the
> user will likely lose their project history.
>
> Commits you push to the connected branch sync back to Lovable and show up in
> the editor, so keep the branch in a working state.
<!-- LOVABLE:END -->

## Architecture rules
- The app is Flutter/Dart (root `lib/`); the previous React/Lovable web app lives in `legacy_web/` only as a behavior/design reference — do not add features there.
- The app is migrating to **Clean Architecture + Bloc**, one vertical slice at a time. **Orders are the first slice** (done): `lib/domain/` (entities, repository interfaces, ports, use cases — pure Dart, no Flutter/Supabase) ← `lib/data/repositories/` (in-memory + Supabase implementations of the domain interface) and `lib/features/orders/bloc/` (`OrdersBloc`: events → use cases → state). Dependencies only point inward; `test/architecture_test.dart` enforces it.
- Everything not yet migrated (session, catalog, cart, notifications) still uses the `ChangeNotifier` controllers of `lib/shared/state/` (wired in `AppServices`, the composition root) over repositories in `lib/data/repositories/`. Each repository has two implementations: in-memory (demo, used by the tests) and Supabase (real backend, enabled only when `AppConfig.hasSupabase`). Do not add a third source of truth. When touching one of those areas, prefer migrating it to the orders pattern instead of adding more `ChangeNotifier` code.
- HU-4 sigue el mismo patrón: Cubits (`flutter_bloc`) en `lib/features/**` → casos de uso en `lib/domain/usecases/` → interfaces en `lib/domain/repositories/` y puertos en `lib/domain/ports/`; las implementaciones viven en `lib/data/repositories/` y los adaptadores en `lib/shared/adapters/`, inyectados por `AppServices`. Cubits: `RateOrderCubit`, `RewardsCubit`, `MerchantBoxesCubit`, `NotificationsCubit`, `EarningsCubit`. Los widgets nunca llaman a Supabase directo. Con Supabase los avisos de pedido los crea la base (0022), así que el notificador de pedidos remoto no crea avisos locales.
- Visibility of restaurants/dishes must go through `isReachable` (radius + couriers nearby + campus-only) in `lib/domain/catalog_rules.dart`, exposed via `CatalogController.reachableRestaurants/reachableDishes` — single source for the distance rule.
- Business rules (pricing, filters, order transitions, scheduling, recommendations) are pure functions in `lib/domain/` with unit tests; widgets never duplicate them.
- Orders are shared by buyer, restaurant and courier through `OrdersBloc` → use cases (`lib/domain/usecases/orders/`) → `OrderRepository`. Screens dispatch events (`bloc.add(...)` or `await bloc.request(...)` when they need the result) and read via `context.watch<OrdersBloc>()`; they never touch repositories or mutate `Order`. Allowed transitions live in `kAllowedTransitions`; with Supabase the server (RPC) decides and every `result` code is translated by `lib/domain/order_errors.dart`.
- Merchant products are saved into the shared catalog repository via `CatalogController.saveDish`, so buyer screens and the radius rule see them without a second source.
- Mobile-first touch UI: shared pieces in `lib/core/widgets/`; yellow `#FCBD1A` primary, Sora/Manrope fonts bundled in `assets/fonts/`; every visible control must have a real action.
- Comment every class, function and widget with one short line saying what it is or does (Spanish, `///` for public members). New code without that comment is not done.
- Demo accounts (password `biffy123`) and the "Horario de demostración" setting keep the full three-role flow testable offline at any hour; `test/integration/full_flow.dart` drives that flow through the UI.

## Estado y pendientes
`HANDOFF.md` es la fuente de verdad: qué está hecho, qué falta por fase, reglas de trabajo (migraciones, secretos, RLS) y trampas conocidas. Léelo antes de implementar y mantenlo actualizado al cerrar cada fase.
