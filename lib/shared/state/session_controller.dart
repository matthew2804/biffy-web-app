import 'package:flutter/foundation.dart';

import '../../core/constants/catalog_constants.dart';
import '../../core/utils/clock.dart';
import '../../data/models/address.dart';
import '../../data/models/catalog.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';
import 'notification_center.dart';

/// Beneficio canjeable con Gotas (valores de demostración).
class Benefit {
  const Benefit(
    this.id,
    this.title,
    this.description,
    this.cost,
    this.kind, [
    this.amount = 0,
  ]);
  final String id;
  final String title;
  final String description;
  final int cost;
  final CouponKind kind;
  final int amount;
}

const kBenefits = [
  Benefit(
    'free-delivery',
    'Envío gratis',
    'Cupón para un pedido sin tarifa de entrega.',
    300,
    CouponKind.freeDelivery,
  ),
  Benefit(
    'off-5000',
    r'$5.000 de descuento',
    'Cupón aplicable a tu próximo pedido.',
    500,
    CouponKind.fixed,
    5000,
  ),
  Benefit(
    'off-10000',
    r'$10.000 de descuento',
    'Cupón aplicable a tu próximo pedido.',
    950,
    CouponKind.fixed,
    10000,
  ),
];

enum VerifyResult { ok, invalidEmail, domainMismatch, notLoggedIn }

/// Sesión simulada: usuario, rol activo, datos personales y preferencias.
class SessionController extends ChangeNotifier {
  SessionController(this._auth, this._notifications, this._clock);

  final AuthRepository _auth;
  final NotificationCenter _notifications;
  final Clock _clock;

  AppUser? _user;
  UserRole _activeRole = UserRole.buyer;
  final Map<String, UserData> _data = {};
  final UserData _guest = UserData();
  AppSettings _settings = const AppSettings();
  String _pointId = 'icesi-biblioteca';
  int _seq = 0;

  AppUser? get user => _user;
  bool get isLoggedIn => _user != null;
  UserRole get activeRole => _activeRole;
  AppSettings get settings => _settings;
  AuthRepository get auth => _auth;

  UserData get data => _user == null ? _guest : dataFor(_user!.id);
  UserData dataFor(String userId) => _data.putIfAbsent(userId, UserData.new);

  Preferences get prefs => data.prefs;
  int get gotas => data.gotas;
  String? get verifiedUniversityId => data.verifiedUniversityId;
  bool get isVerifiedStudent => data.verifiedUniversityId != null;
  String? get universityId =>
      data.verifiedUniversityId ?? data.prefs.universityId;
  DeliveryPoint get point => pointById(_pointId);
  String get pointId => _pointId;
  bool get hasCourierProfile => data.courierProfile != null;
  String? get businessId => _user?.businessId;

  String _id(String prefix) => '$prefix-${++_seq}';

  // ---------------------------------------------------------------- Auth

  AppUser login(String email, String password) {
    final u = _auth.login(email, password);
    _startSession(u);
    return u;
  }

  /// Acceso rápido a cuentas de demostración.
  void loginAs(AppUser u) => _startSession(u);

  AppUser register({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) {
    final u = _auth.register(
      name: name,
      email: email,
      password: password,
      role: role,
      phone: phone,
    );
    final d = dataFor(u.id);
    if (role == UserRole.buyer) {
      final p = point;
      final a = Address(
        id: _id('addr'),
        label: 'Punto de entrega',
        line: p.name,
        details: p.detail,
        neighborhood: p.campusId == null ? 'Bogotá' : 'Campus',
        pointId: p.id,
      );
      d.addresses.add(a);
      d.defaultAddressId = a.id;
    }
    _startSession(u);
    return u;
  }

  void _startSession(AppUser u) {
    _user = u;
    _activeRole = u.role;
    final d = dataFor(u.id);
    // Las preferencias del modo invitado se conservan si la cuenta no tiene.
    if (!d.prefsCompleted && _guest.prefsCompleted) {
      d.prefs = _guest.prefs;
      d.prefsCompleted = true;
    }
    if (!d.welcomeGranted && u.role == UserRole.buyer) {
      d.welcomeGranted = true;
      _credit(d, kWelcomeGotas, 'Bienvenida a Biffy (demo)');
      _notifications.push(
        title: '¡Bienvenido a Biffy! 🐝',
        body: 'Te regalamos $kWelcomeGotas Gotas de demostración.',
        audience: 'user:${u.id}',
        route: '/recompensas',
      );
    }
    final addr = d.defaultAddress;
    if (addr != null) _pointId = addr.pointId;
    notifyListeners();
  }

  void logout() {
    _user = null;
    _activeRole = UserRole.buyer;
    notifyListeners();
  }

  void setActiveRole(UserRole role) {
    _activeRole = role;
    notifyListeners();
  }

  void updateProfile({String? name, String? phone}) {
    final u = _user;
    if (u == null) return;
    if (name != null && name.trim().isNotEmpty) u.name = name.trim();
    if (phone != null) u.phone = phone.trim();
    notifyListeners();
  }

  void linkBusiness(String businessId) {
    _user?.businessId = businessId;
    _activeRole = UserRole.restaurant;
    notifyListeners();
  }

  // ------------------------------------------------------- Ubicación

  void setPoint(String id) {
    if (_pointId == id) return;
    _pointId = id;
    notifyListeners();
  }

  // ---------------------------------------------------- Preferencias

  /// Guarda preferencias. Devuelve las Gotas acreditadas (300 solo la primera
  /// vez y únicamente con sesión iniciada).
  int savePreferences(Preferences p) {
    final d = data;
    d.prefs = p;
    d.prefsCompleted = true;
    var awarded = 0;
    if (isLoggedIn && !d.surveyRewarded) {
      d.surveyRewarded = true;
      awarded = kSurveyGotas;
      _credit(d, awarded, 'Completaste tus preferencias');
      _notifications.push(
        title: '+$kSurveyGotas Gotas 💧',
        body: 'Gracias por completar tus preferencias.',
        audience: 'user:${_user!.id}',
        route: '/recompensas',
      );
    }
    notifyListeners();
    return awarded;
  }

  VerifyResult verifyUniversity(String universityId, String email) {
    if (!isLoggedIn) return VerifyResult.notLoggedIn;
    final e = email.trim().toLowerCase();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e)) {
      return VerifyResult.invalidEmail;
    }
    final uni = universityById(universityId);
    if (uni == null || !e.endsWith('@${uni.domain}')) {
      return VerifyResult.domainMismatch;
    }
    final d = data;
    d.verifiedUniversityId = uni.id;
    d.universityEmail = e;
    d.prefs = d.prefs.copyWith(universityId: uni.id);
    _notifications.push(
      title: 'Universidad verificada (simulación) 🎓',
      body: 'Ya ves descuentos y secciones de ${uni.name}.',
      audience: 'user:${_user!.id}',
      route: '/campus',
    );
    notifyListeners();
    return VerifyResult.ok;
  }

  void setUniversity(String? universityId) {
    final d = data;
    d.prefs = universityId == null
        ? d.prefs.copyWith(clearUniversity: true)
        : d.prefs.copyWith(universityId: universityId);
    if (d.verifiedUniversityId != null &&
        d.verifiedUniversityId != universityId) {
      d.verifiedUniversityId = null;
    }
    notifyListeners();
  }

  // ------------------------------------------------------- Favoritos

  /// Devuelve `false` si hace falta iniciar sesión.
  bool toggleFavoriteDish(String id) {
    if (!isLoggedIn) return false;
    final f = data.favoriteDishes;
    f.contains(id) ? f.remove(id) : f.add(id);
    notifyListeners();
    return true;
  }

  bool toggleFavoriteRestaurant(String id) {
    if (!isLoggedIn) return false;
    final f = data.favoriteRestaurants;
    f.contains(id) ? f.remove(id) : f.add(id);
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------ Direcciones

  Address saveAddress(Address a, {bool makeDefault = false}) {
    final list = data.addresses;
    final i = list.indexWhere((x) => x.id == a.id);
    final saved = a.id.isEmpty
        ? Address(
            id: _id('addr'),
            label: a.label,
            line: a.line,
            details: a.details,
            neighborhood: a.neighborhood,
            reference: a.reference,
            pointId: a.pointId,
          )
        : a;
    if (i >= 0) {
      list[i] = saved;
    } else {
      list.add(saved);
    }
    if (makeDefault || data.defaultAddressId == null) {
      data.defaultAddressId = saved.id;
    }
    notifyListeners();
    return saved;
  }

  void deleteAddress(String id) {
    data.addresses.removeWhere((a) => a.id == id);
    if (data.defaultAddressId == id) {
      data.defaultAddressId = data.addresses.isEmpty
          ? null
          : data.addresses.first.id;
    }
    notifyListeners();
  }

  void setDefaultAddress(String id) {
    data.defaultAddressId = id;
    notifyListeners();
  }

  Address? addressById(String? id) {
    for (final a in data.addresses) {
      if (a.id == id) return a;
    }
    return null;
  }

  void setDefaultPayment(PaymentMethod m) {
    data.defaultPayment = m;
    notifyListeners();
  }

  // ------------------------------------------------------------ Gotas

  void _credit(UserData d, int amount, String reason) {
    d.gotas += amount;
    d.gotasHistory.insert(0, GotasEntry(reason, amount, _clock.now()));
  }

  void creditGotas(String userId, int amount, String reason) {
    if (amount <= 0) return;
    _credit(dataFor(userId), amount, reason);
    notifyListeners();
  }

  bool spendGotas(String userId, int amount, String reason) {
    final d = dataFor(userId);
    if (amount <= 0) return true;
    if (d.gotas < amount) return false;
    _credit(d, -amount, reason);
    notifyListeners();
    return true;
  }

  /// Canjea un beneficio si el saldo alcanza. Devuelve el cupón creado.
  Coupon? redeem(Benefit b) {
    if (!isLoggedIn || data.gotas < b.cost) return null;
    _credit(data, -b.cost, 'Canje: ${b.title}');
    final c = Coupon(
      id: _id('cup'),
      title: b.title,
      kind: b.kind,
      amount: b.amount,
    );
    data.coupons.add(c);
    notifyListeners();
    return c;
  }

  Coupon? couponById(String? id) {
    for (final c in data.coupons) {
      if (c.id == id) return c;
    }
    return null;
  }

  void setCouponUsed(String userId, String couponId, bool used) {
    for (final c in dataFor(userId).coupons) {
      if (c.id == couponId) c.used = used;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- Ajustes

  void updateSettings(AppSettings s) {
    _settings = s;
    _clock.simulateLunch = s.demoLunch;
    notifyListeners();
  }

  // ------------------------------------------------------- Repartidor

  void saveCourierProfile(CourierProfile p) {
    data.courierProfile = p;
    if (_user != null && p.phone.isNotEmpty && _user!.phone.isEmpty) {
      _user!.phone = p.phone;
    }
    _activeRole = UserRole.courier;
    notifyListeners();
  }

  void setCourierOnline(bool online) {
    if (!hasCourierProfile) return;
    data.courierOnline = online;
    notifyListeners();
  }

  /// El modo Campus exige universidad verificada (simulación).
  bool setCourierZone(CourierZone zone) {
    if (zone == CourierZone.campus && !isVerifiedStudent) return false;
    data.courierZone = zone;
    notifyListeners();
    return true;
  }
}
