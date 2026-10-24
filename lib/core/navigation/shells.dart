import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../app/theme/app_colors.dart';
import '../../shared/state/cart_controller.dart';
import '../utils/format.dart';
import '../widgets/ui.dart';

class NavItem {
  const NavItem(this.icon, this.selectedIcon, this.label);
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const kBuyerNav = [
  NavItem(Icons.home_outlined, Icons.home, 'Inicio'),
  NavItem(Icons.search, Icons.manage_search, 'Explorar'),
  NavItem(Icons.auto_awesome_outlined, Icons.auto_awesome, 'Biffy AI'),
  NavItem(Icons.person_outline, Icons.person, 'Perfil'),
];

const kCourierNav = [
  NavItem(Icons.delivery_dining_outlined, Icons.delivery_dining, 'Inicio'),
  NavItem(Icons.payments_outlined, Icons.payments, 'Ganancias'),
  NavItem(Icons.person_outline, Icons.person, 'Perfil'),
];

const kRestaurantNav = [
  NavItem(Icons.storefront_outlined, Icons.storefront, 'Inicio'),
  NavItem(Icons.receipt_long_outlined, Icons.receipt_long, 'Pedidos'),
  NavItem(Icons.restaurant_menu_outlined, Icons.restaurant_menu, 'Menú'),
  NavItem(Icons.bar_chart_outlined, Icons.bar_chart, 'Estadísticas'),
  NavItem(Icons.person_outline, Icons.person, 'Perfil'),
];

/// Contenedor con navegación inferior fija por rol. Conserva el estado de
/// cada pestaña gracias a StatefulShellRoute.
class RoleShell extends StatelessWidget {
  const RoleShell({
    super.key,
    required this.shell,
    required this.items,
    this.showCartBar = false,
  });

  final StatefulNavigationShell shell;
  final List<NavItem> items;
  final bool showCartBar;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: MobileFrame(child: shell),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showCartBar) const CartBar(),
          DecoratedBox(
            decoration: BoxDecoration(
              color: p.surface,
              border: Border(top: BorderSide(color: p.border)),
            ),
            child: NavigationBar(
              selectedIndex: shell.currentIndex,
              onDestinationSelected: (i) =>
                  shell.goBranch(i, initialLocation: i == shell.currentIndex),
              destinations: [
                for (final it in items)
                  NavigationDestination(
                    icon: Icon(it.icon),
                    selectedIcon: Icon(it.selectedIcon, color: AppColors.text),
                    label: it.label,
                    tooltip: it.label,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Barra flotante del carrito: visible cuando hay productos.
class CartBar extends StatelessWidget {
  const CartBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    if (cart.isEmpty) return const SizedBox.shrink();
    return SafeArea(
      top: false,
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: MobileFrame(
          child: Material(
            color: AppColors.text,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              key: const Key('cart-bar'),
              borderRadius: BorderRadius.circular(18),
              onTap: () => context.push('/carrito'),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${cart.count}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.text,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Ver carrito · ${cart.restaurant?.name ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      cop(cart.subtotal),
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
