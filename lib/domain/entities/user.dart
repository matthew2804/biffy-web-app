import 'address.dart';
import 'catalog.dart';

enum UserRole {
  buyer('Comprador', '🛍️'),
  courier('Repartidor', '🛵'),
  restaurant('Restaurante', '🍽️');

  const UserRole(this.label, this.emoji);
  final String label;
  final String emoji;
}

class AppUser {
  AppUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone = '',
    this.businessId,
    this.isDemo = false,
  });

  final String id;
  String name;
  final String email;

  /// Rol principal con el que se registró la cuenta.
  final UserRole role;
  String phone;
  String? businessId;
  final bool isDemo;
}

class Preferences {
  const Preferences({
    this.likes = const {},
    this.lifestyle = const {},
    this.allergies = const {},
    this.budget = 25000,
    this.universityId,
  });

  final Set<String> likes;
  final Set<String> lifestyle;
  final Set<String> allergies;
  final int budget;
  final String? universityId;

  bool get isEmpty => likes.isEmpty && lifestyle.isEmpty && allergies.isEmpty;

  Preferences copyWith({
    Set<String>? likes,
    Set<String>? lifestyle,
    Set<String>? allergies,
    int? budget,
    String? universityId,
    bool clearUniversity = false,
  }) {
    return Preferences(
      likes: likes ?? this.likes,
      lifestyle: lifestyle ?? this.lifestyle,
      allergies: allergies ?? this.allergies,
      budget: budget ?? this.budget,
      universityId: clearUniversity
          ? null
          : (universityId ?? this.universityId),
    );
  }
}

enum Vehicle {
  moto('Moto', '🏍️'),
  bicycle('Bicicleta', '🚲'),
  scooter('Patineta', '🛴'),
  walking('A pie', '🚶');

  const Vehicle(this.label, this.emoji);
  final String label;
  final String emoji;

  /// Distancia máxima simulada que cubre cada medio.
  double get maxKm => switch (this) {
    Vehicle.moto => 8,
    Vehicle.bicycle => 4,
    Vehicle.scooter => 3,
    Vehicle.walking => 1.5,
  };
}

class CourierProfile {
  const CourierProfile({
    required this.fullName,
    required this.docType,
    required this.docNumber,
    required this.phone,
    required this.vehicle,
    required this.contactEmail,
    this.plate,
    this.universityId,
  });

  final String fullName;
  final String docType;
  final String docNumber;
  final String phone;
  final Vehicle vehicle;
  final String? plate;
  final String? universityId;
  final String contactEmail;
}

enum CourierZone { general, campus }

enum CouponKind { freeDelivery, fixed }

class Coupon {
  Coupon({
    required this.id,
    required this.title,
    required this.kind,
    this.amount = 0,
  });
  final String id;
  final String title;
  final CouponKind kind;
  final int amount;
  bool used = false;
}

class GotasEntry {
  const GotasEntry(this.title, this.amount, this.at);
  final String title;
  final int amount;
  final DateTime at;
}

class AppSettings {
  const AppSettings({
    this.notifications = true,
    this.promotions = true,
    this.emailSummary = false,
    this.darkMode = false,
    this.demoLunch = false,
  });
  final bool notifications;
  final bool promotions;
  final bool emailSummary;
  final bool darkMode;

  /// Simula las 12:00 para que los restaurantes estén abiertos en la demo.
  final bool demoLunch;

  AppSettings copyWith({
    bool? notifications,
    bool? promotions,
    bool? emailSummary,
    bool? darkMode,
    bool? demoLunch,
  }) {
    return AppSettings(
      notifications: notifications ?? this.notifications,
      promotions: promotions ?? this.promotions,
      emailSummary: emailSummary ?? this.emailSummary,
      darkMode: darkMode ?? this.darkMode,
      demoLunch: demoLunch ?? this.demoLunch,
    );
  }
}

/// Datos personales de un usuario dentro de la sesión de demostración.
class UserData {
  Preferences prefs = const Preferences();
  bool prefsCompleted = false;
  bool surveyRewarded = false;
  bool welcomeGranted = false;
  int gotas = 0;
  final List<GotasEntry> gotasHistory = [];
  final Set<String> favoriteDishes = {};
  final Set<String> favoriteRestaurants = {};
  final List<Address> addresses = [];
  String? defaultAddressId;
  PaymentMethod defaultPayment = PaymentMethod.nequi;
  final List<Coupon> coupons = [];

  /// Verificación universitaria simulada (no comprueba control del correo).
  String? verifiedUniversityId;
  String? universityEmail;

  CourierProfile? courierProfile;
  bool courierOnline = false;
  CourierZone courierZone = CourierZone.general;

  Address? get defaultAddress {
    for (final a in addresses) {
      if (a.id == defaultAddressId) return a;
    }
    return addresses.isEmpty ? null : addresses.first;
  }
}
