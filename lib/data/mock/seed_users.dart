import '../models/business.dart';
import '../models/user.dart';

/// Cuentas FICTICIAS de demostración (contraseña: biffy123).
const kDemoBuyerEmail = 'diego.demo@icesi.edu.co';
const kDemoNewBuyerEmail = 'camila.demo@biffy.co';
const kDemoCourierEmail = 'andres.repartidor@demo.biffy.co';
const kDemoCourier2Email = 'valentina.repartidora@demo.biffy.co';
const kDemoRestaurantEmail = 'qbano@demo.biffy.co';

/// Fotos de perfil de las personas ficticias de la demo (por id de usuario).
const kDemoAvatars = {
  'u-diego': 'assets/images/avatars/diego.jpg',
  'u-camila': 'assets/images/avatars/camila.jpg',
  'u-andres': 'assets/images/avatars/andres.jpg',
  'u-valentina': 'assets/images/avatars/valentina.jpg',
  'u-seed-daniel': 'assets/images/avatars/daniel.jpg',
  'u-seed-mario': 'assets/images/avatars/mario.jpg',
  'u-seed-sofia': 'assets/images/avatars/sofia.jpg',
  'u-seed-camilar': 'assets/images/avatars/camila-r.jpg',
};

/// Cuentas de demostración; una por negocio para el rol restaurante.
List<AppUser> seedUsers(List<Business> businesses) => [
  AppUser(
    id: 'u-diego',
    name: 'Diego (demo)',
    email: kDemoBuyerEmail,
    role: UserRole.buyer,
    phone: '300 000 0001',
    isDemo: true,
  ),
  AppUser(
    id: 'u-camila',
    name: 'Camila (demo)',
    email: kDemoNewBuyerEmail,
    role: UserRole.buyer,
    phone: '300 000 0002',
    isDemo: true,
  ),
  AppUser(
    id: 'u-andres',
    name: 'Andrés (repartidor demo)',
    email: kDemoCourierEmail,
    role: UserRole.courier,
    phone: '300 000 0003',
    isDemo: true,
  ),
  AppUser(
    id: 'u-valentina',
    name: 'Valentina (repartidora demo)',
    email: kDemoCourier2Email,
    role: UserRole.courier,
    phone: '300 000 0004',
    isDemo: true,
  ),
  for (final b in businesses)
    AppUser(
      id: 'u-owner-${b.id}',
      name: '${b.ownerName} · ${b.brand}',
      email: b.ownerEmail,
      role: UserRole.restaurant,
      phone: b.ownerPhone,
      businessId: b.id,
      isDemo: true,
    ),
];
