import '../../core/constants/catalog_constants.dart';
import '../../domain/catalog_rules.dart';
import '../../domain/order_rules.dart';
import '../../domain/pricing.dart';
import '../../shared/state/order_service.dart';
import '../../shared/state/session_controller.dart';
import '../models/address.dart';
import '../models/cart.dart';
import '../models/catalog.dart';
import '../models/order.dart';
import '../models/user.dart';

/// Datos personales y pedidos semilla para probar las pantallas antes de
/// crear un pedido nuevo. Todo es ficticio.
void applyDemoSeed(SessionController session, OrderService orders) {
  final now = orders.clock.now();

  // Comprador con historial, preferencias y verificación simulada.
  final diego = session.dataFor('u-diego')
    ..prefs = const Preferences(
      likes: {'sandwich', 'saludable'},
      budget: 30000,
      universityId: 'icesi',
    )
    ..prefsCompleted = true
    ..surveyRewarded = true
    ..welcomeGranted = true
    ..verifiedUniversityId = 'icesi'
    ..universityEmail = 'diego.demo@icesi.edu.co'
    ..gotas = 750
    ..defaultPayment = PaymentMethod.nequi;
  diego.gotasHistory.addAll([
    GotasEntry(
      'Completaste tus preferencias',
      kSurveyGotas,
      now.subtract(const Duration(days: 6)),
    ),
    GotasEntry(
      'Bienvenida a Biffy (demo)',
      kWelcomeGotas,
      now.subtract(const Duration(days: 7)),
    ),
  ]);
  diego.addresses.addAll(const [
    Address(
      id: 'addr-diego-1',
      label: 'Biblioteca Icesi',
      line: 'Universidad Icesi · Biblioteca',
      details: 'Entrada principal, segundo piso',
      neighborhood: 'Pance',
      reference: 'Junto a los casilleros',
      pointId: 'icesi-biblioteca',
    ),
    Address(
      id: 'addr-diego-2',
      label: 'Plazoleta Icesi',
      line: 'Universidad Icesi · Plazoleta',
      details: 'Mesas al lado de la cafetería',
      neighborhood: 'Pance',
      pointId: 'icesi-plazoleta',
    ),
    Address(
      id: 'addr-diego-3',
      label: 'Casa (Bogotá)',
      line: 'Cra 7 #60-20',
      details: 'Apto 302',
      neighborhood: 'Chapinero',
      reference: 'Portería principal',
      pointId: 'chapinero',
    ),
  ]);
  diego.defaultAddressId = 'addr-diego-1';
  diego.favoriteDishes.addAll({'qbano-especial', 'bowl-proteico'});
  diego.favoriteRestaurants.add('qbano-icesi');

  session.dataFor('u-andres')
    ..verifiedUniversityId = 'icesi'
    ..courierProfile = const CourierProfile(
      fullName: 'Andrés Repartidor (demo)',
      docType: 'CC',
      docNumber: '1000000003',
      phone: '300 000 0003',
      vehicle: Vehicle.moto,
      plate: 'ABC12D',
      universityId: 'icesi',
      contactEmail: 'andres.repartidor@demo.biffy.co',
    );
  session.dataFor('u-valentina').courierProfile = const CourierProfile(
    fullName: 'Valentina Repartidora (demo)',
    docType: 'CC',
    docNumber: '1000000004',
    phone: '300 000 0004',
    vehicle: Vehicle.bicycle,
    contactEmail: 'valentina.repartidora@demo.biffy.co',
  );

  final campusAddress = diego.addresses.first;
  Order seed(
    String id,
    String buyerId,
    String buyerName,
    String restaurantId,
    List<(String, int, DishSelection, String)> items,
    Duration ago,
    OrderStatus status, {
    String? courierId,
    String? courierName,
    PaymentMethod payment = PaymentMethod.nequi,
    String? reject,
  }) {
    final r = orders.catalog.restaurantById(restaurantId)!;
    final point = pointById(campusAddress.pointId);
    final lines = [
      for (final (dishId, qty, sel, note) in items)
        () {
          final d = orders.catalog.dishById(dishId)!;
          return OrderLine(
            dishId: d.id,
            name: d.name,
            emoji: d.emoji,
            qty: qty,
            unitPrice: unitPrice(d, sel),
            selection: sel,
            detail: selectionDetail(d, sel),
            note: note,
          );
        }(),
    ];
    final subtotal = lines.fold<int>(0, (s, l) => s + l.total);
    final campus = buyerId == 'u-diego'
        ? campusDiscount(subtotal, r, 'icesi')
        : 0;
    final fee = deliveryFee(r, point);
    final km = distanceTo(r, point);
    final created = now.subtract(ago);
    final o = Order(
      id: id,
      buyerId: buyerId,
      buyerName: buyerName,
      restaurantId: r.id,
      restaurantName: r.name,
      lines: lines,
      address: campusAddress,
      pointId: point.id,
      payment: payment,
      createdAt: created,
      subtotal: subtotal,
      campusDiscount: campus,
      couponDiscount: 0,
      deliveryFee: fee,
      gotasUsed: 0,
      tip: 0,
      total: subtotal - campus + fee,
      deliveryCode: '4821',
      pickupCode: '8492',
      etaMin: etaMinutes(r, point),
      courierPay: courierPayFor(km),
      distanceKm: double.parse(km.toStringAsFixed(2)),
    );
    o.status = status;
    o.courierId = courierId;
    o.courierName = courierName;
    o.rejectReason = reject;
    o.gotasCredited = status == OrderStatus.delivered;
    if (status == OrderStatus.delivered) {
      o.deliveredAt = created.add(const Duration(minutes: 22));
      o.evidence = 'Foto de demostración';
    }
    o.history.add(
      StatusEvent(status, created.add(const Duration(minutes: 5)), 'Semilla'),
    );
    orders.insertSeed(o);
    return o;
  }

  const queso = DishSelection(sizeId: 'qe-30', extraIds: {'qe-queso'});
  const qe = DishSelection(sizeId: 'qe-30');
  const qp = DishSelection(sizeId: 'qp-30');
  seed(
    'BF-1830',
    'u-diego',
    'Diego (demo)',
    'qbano-icesi',
    [
      ('qbano-especial', 1, queso, ''),
      ('qbano-limonada', 1, const DishSelection(), ''),
    ],
    const Duration(days: 3, hours: 2),
    OrderStatus.delivered,
    courierId: 'u-andres',
    courierName: 'Andrés (repartidor demo)',
  );
  seed(
    'BF-1834',
    'u-diego',
    'Diego (demo)',
    'qbano-icesi',
    [
      ('qbano-especial', 1, queso, ''),
      ('qbano-limonada', 1, const DishSelection(), ''),
    ],
    const Duration(days: 2, hours: 1),
    OrderStatus.delivered,
    courierId: 'u-andres',
    courierName: 'Andrés (repartidor demo)',
  );
  seed(
    'BF-1837',
    'u-diego',
    'Diego (demo)',
    'verde-bowl',
    [
      (
        'bowl-proteico',
        1,
        const DishSelection(sizeId: 'bp-r'),
        'Sin tomate cherry, por favor',
      ),
    ],
    const Duration(days: 1, hours: 3),
    OrderStatus.delivered,
    courierId: 'u-valentina',
    courierName: 'Valentina (repartidora demo)',
  );
  seed(
    'BF-1838',
    'u-diego',
    'Diego (demo)',
    'horno-campus',
    [('pizza-pepperoni', 1, const DishSelection(sizeId: 'pp-p'), '')],
    const Duration(days: 1, hours: 1),
    OrderStatus.cancelled,
    reject: 'Sin pepperoni disponible (demo)',
  );
  seed(
    'BF-1839',
    'u-seed-mario',
    'Mario L. (ficticio)',
    'qbano-icesi',
    [('qbano-pollo', 2, qp, '')],
    const Duration(hours: 2),
    OrderStatus.delivered,
    courierId: 'u-andres',
    courierName: 'Andrés (repartidor demo)',
    payment: PaymentMethod.pse,
  );
  seed(
    'BF-1840',
    'u-seed-sofia',
    'Sofía P. (ficticio)',
    'qbano-icesi',
    [('qbano-especial', 1, qe, '')],
    const Duration(minutes: 25),
    OrderStatus.ready,
    payment: PaymentMethod.card,
  );
  seed(
    'BF-1841',
    'u-seed-daniel',
    'Daniel S. (ficticio)',
    'qbano-icesi',
    [('qbano-vegetariano', 1, const DishSelection(), 'Sin cebolla')],
    const Duration(minutes: 11),
    OrderStatus.preparing,
    payment: PaymentMethod.cash,
  );
  seed(
    'BF-1842',
    'u-seed-camilar',
    'Camila R. (ficticio)',
    'qbano-icesi',
    [('qbano-especial', 2, qe, 'Salsa aparte')],
    const Duration(minutes: 3),
    OrderStatus.pending,
  );
  seed(
    'BF-1843',
    'u-seed-sofia',
    'Sofía P. (ficticio)',
    'wokroll-icesi',
    [('teriyaki-bowl', 1, const DishSelection(), '')],
    const Duration(minutes: 30),
    OrderStatus.ready,
    payment: PaymentMethod.cash,
  );
}
