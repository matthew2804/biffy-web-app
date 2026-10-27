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
- All app state lives in the `ChangeNotifier` controllers of `lib/shared/state/` (wired in `AppServices`) over repositories in `lib/data/repositories/`. There are two implementations of each repository: in-memory (demo, used by the 104 tests) and Supabase (real backend, enabled only when `AppConfig.hasSupabase`). Do not add a third source of truth.
- Visibility of restaurants/dishes must go through `isReachable` (radius + couriers nearby + campus-only) in `lib/domain/catalog_rules.dart`, exposed via `CatalogController.reachableRestaurants/reachableDishes` — single source for the distance rule.
- Business rules (pricing, filters, order transitions, scheduling, recommendations) are pure functions in `lib/domain/` with unit tests; widgets never duplicate them.
- Orders are shared by buyer, restaurant and courier through `OrderService`; every status change goes through its methods (allowed transitions in `kAllowedTransitions`), never by mutating `Order` from a widget.
- Merchant products are saved into the shared catalog repository via `CatalogController.saveDish`, so buyer screens and the radius rule see them without a second source.
- Mobile-first touch UI: shared pieces in `lib/core/widgets/`; yellow `#FCBD1A` primary, Sora/Manrope fonts bundled in `assets/fonts/`; every visible control must have a real action.
- Demo accounts (password `biffy123`) and the "Horario de demostración" setting keep the full three-role flow testable offline at any hour; `test/integration/full_flow.dart` drives that flow through the UI.

## Estado y pendientes
`HANDOFF.md` es la fuente de verdad: qué está hecho, qué falta por fase, reglas de trabajo (migraciones, secretos, RLS) y trampas conocidas. Léelo antes de implementar y mantenlo actualizado al cerrar cada fase.
