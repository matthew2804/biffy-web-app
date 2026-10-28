import 'package:flutter/foundation.dart';

import '../../core/constants/catalog_constants.dart';
import '../../core/utils/clock.dart';
import '../../data/models/address.dart';
import '../../data/models/catalog.dart';
import '../../data/models/user.dart';
import '../../data/repositories/auth_repository.dart';
import '../../data/repositories/supabase_profile_repository.dart';
import 'notification_center.dart';

/// Beneficio canjeable con Gotas (valores de demostración).
class Benefit {
  /// Crea un beneficio canjeable con sus datos de cupón.
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

/// Resultado de verificar el correo universitario.
enum VerifyResult { ok, invalidEmail, domainMismatch, notLoggedIn }

/// Sesión simulada: usuario, rol activo, datos personales y preferencias.
class SessionController extends ChangeNotifier {
  /// Recibe el repositorio de auth, las notificaciones y el reloj.
  SessionController(
    this._auth,
    this._notifications,
    this._clock, {
    SupabaseProfileRepository? profile,
  }) : _profile = profile; // ignore: prefer_initializing_formals

  final AuthRepository _auth;
  final NotificationCenter _notifications;
  final Clock _clock;

  /// Repositorio de datos personales; null en modo demo.
  final SupabaseProfileRepository? _profile;

  AppUser? _user;
  UserRole _activeRole = UserRole.buyer;
  final Map<String, UserData> _data = {};
  final UserData _guest = UserData();
  AppSettings _settings = const AppSettings();
  String _pointId = 'icesi-biblioteca';
  int _seq = 0;

  /// Usuario con sesión iniciada, si hay.
  AppUser? get user => _user;
  /// `true` si hay una cuenta activa.
  bool get isLoggedIn => _user != null;
  /// Rol con el que se está usando la app.
  UserRole get activeRole => _activeRole;
  /// Ajustes locales vigentes.
  AppSettings get settings => _settings;
  /// Repositorio de autenticación en uso.
  AuthRepository get auth => _auth;

  /// Datos del usuario activo o del invitado.
  UserData get data => _user == null ? _guest : dataFor(_user!.id);
  /// Datos de un usuario, creándolos si no existen.
  UserData dataFor(String userId) => _data.putIfAbsent(userId, UserData.new);

  /// Preferencias del usuario activo.
  Preferences get prefs => data.prefs;
  /// Saldo de Gotas del usuario activo.
  int get gotas => data.gotas;
  /// Universidad verificada, si la hay.
  String? get verifiedUniversityId => data.verifiedUniversityId;
  /// `true` si el comprador verificó su universidad.
  bool get isVerifiedStudent => data.verifiedUniversityId != null;
  /// Universidad verificada o la elegida en preferencias.
  String? get universityId =>
      data.verifiedUniversityId ?? data.prefs.universityId;
  /// Punto de entrega activo.
  DeliveryPoint get point => pointById(_pointId);
  /// Id del punto de entrega activo.
  String get pointId => _pointId;
  /// `true` si el usuario ya registró perfil de repartidor.
  bool get hasCourierProfile => data.courierProfile != null;
  /// Negocio vinculado a la cuenta, si es restaurante.
  String? get businessId => _user?.businessId;

  /// Genera un id único con el prefijo indicado.
  String _id(String prefix) => '$prefix-${++_seq}';

  // ---------------------------------------------------------------- Auth

  /// Inicia sesión de forma síncrona (modo demo).
  AppUser login(String email, String password) {
    final u = _auth.login(email, password);
    _startSession(u);
    return u;
  }

  /// Acceso rápido a cuentas de demostración.
  void loginAs(AppUser u) => _startSession(u);

  /// Registra la cuenta y crea su dirección inicial.
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

  /// Activa la cuenta, hereda preferencias y acredita bienvenida.
  void _startSession(AppUser u, {bool localWelcome = true}) {
    _user = u;
    _activeRole = u.role;
    final d = dataFor(u.id);
    // Las preferencias del modo invitado se conservan si la cuenta no tiene.
    if (!d.prefsCompleted && _guest.prefsCompleted) {
      d.prefs = _guest.prefs;
      d.prefsCompleted = true;
    }
    // En modo remoto las Gotas de bienvenida las acredita la base.
    if (localWelcome && !d.welcomeGranted && u.role == UserRole.buyer) {
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

  /// Cierra la sesión local y vuelve al modo invitado.
  void logout() {
    _user = null;
    _activeRole = UserRole.buyer;
    notifyListeners();
  }

  // ----------------------------------------------------- Auth asíncrona
  // Las pantallas usan esta ruta: con Supabase habla con Auth; en demo
  // resuelve al instante contra los datos en memoria.

  /// Inicia sesión contra el backend y trae los datos remotos.
  Future<AppUser> loginAsync(String email, String password) async {
    final u = await _auth.signIn(email, password);
    _startSession(u, localWelcome: !_auth.isRemote);
    await _hydrateRemote(u);
    return u;
  }

  /// Registra la cuenta por la ruta asíncrona.
  Future<AppUser> registerAsync({
    required String name,
    required String email,
    required String password,
    required UserRole role,
    String phone = '',
  }) async {
    final u = await _auth.signUp(
      name: name,
      email: email,
      password: password,
      role: role,
      phone: phone,
    );

    if (_auth.isRemote) {
      _startSession(u, localWelcome: false);
      await _hydrateRemote(u);
      return u;
    }

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

  /// Cierra la sesión remota y la local.
  Future<void> logoutAsync() async {
    await _auth.signOut();
    logout();
  }

  /// Recupera la sesión persistida al abrir la app (solo backend real).
  Future<AppUser?> restoreAsync() async {
    final u = await _auth.restoreSession();
    if (u == null) return null;
    _startSession(u, localWelcome: !_auth.isRemote);
    await _hydrateRemote(u);
    return u;
  }

  /// Vuelve a leer saldo, direcciones y perfil desde el backend.
  ///
  /// Se usa después de canjear Gotas o de completar preferencias.
  Future<void> refreshRemote() async {
    final u = _user;
    if (u == null || !_auth.isRemote) return;
    await _hydrateRemote(u);
  }

  /// Trae saldo, direcciones y perfil de repartidor del backend.
  Future<void> _hydrateRemote(AppUser u) async {
    final balance = await _auth.gotasBalance(u.id);
    final saved = await _auth.addresses(u.id);
    final d = dataFor(u.id);

    if (balance != null) {
      d.gotas = balance;
      d.welcomeGranted = true;
    }

    // Las direcciones del backend fijan el punto de entrega (regla de radio).
    if (saved.isNotEmpty) {
      d.addresses
        ..clear()
        ..addAll(saved);
      d.defaultAddressId = saved.first.id;
      _pointId = saved.first.pointId;
    }

    // Perfil de repartidor: evita pedirle el registro a una cuenta que ya lo tiene.
    final courier = await _auth.courierProfile(u.id);
    if (courier != null) {
      d.courierProfile = courier;
      d.courierOnline = true;
      d.courierZone = courier.universityId == null
          ? CourierZone.general
          : CourierZone.campus;
    }

    // Preferencias, ajustes y favoritos del usuario.
    final profile = _profile;
    if (profile != null) {
      final p = await profile.preferences(u.id);
      if (p.prefs != null) d.prefs = p.prefs!;
      d.prefsCompleted = p.completed;
      d.surveyRewarded = p.rewarded;

      final favs = await profile.favorites(u.id);
      d.favoriteDishes
        ..clear()
        ..addAll(favs.dishes);
      d.favoriteRestaurants
        ..clear()
        ..addAll(favs.branches);

      final s = await profile.settings(u.id);
      if (s != null) {
        _settings = s;
        _clock.simulateLunch = s.demoLunch;
      }

      // Cupones generados por las cajas y notificaciones guardadas.
      d.coupons
        ..clear()
        ..addAll(await profile.coupons(u.id));
      _notifications.seed(await profile.notifications(u.id));
    }

    notifyListeners();
  }

  /// Cambia el rol activo de la sesión.
  void setActiveRole(UserRole role) {
    _activeRole = role;
    notifyListeners();
  }

  /// Actualiza nombre y teléfono del usuario.
  void updateProfile({String? name, String? phone}) {
    final u = _user;
    if (u == null) return;
    if (name != null && name.trim().isNotEmpty) u.name = name.trim();
    if (phone != null) u.phone = phone.trim();
    notifyListeners();
  }

  /// Vincula la cuenta a un negocio y pasa al rol restaurante.
  void linkBusiness(String businessId) {
    _user?.businessId = businessId;
    _activeRole = UserRole.restaurant;
    notifyListeners();
  }

  // ------------------------------------------------------- Ubicación

  /// Cambia el punto de entrega activo.
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

    // Persistencia remota: preferencias + recompensa única de la encuesta.
    final u = _user;
    final profile = _profile;
    if (u != null && profile != null) {
      profile.savePreferences(u.id, p, completed: true);
      if (awarded > 0) profile.completeSurvey();
    }

    notifyListeners();
    return awarded;
  }

  /// Verifica el correo universitario de forma simulada.
  ///
  /// TODO equipo: con Supabase debe llamar al RPC `verify_university` (ya
  /// existe y valida el dominio) y refrescar `profiles.verified` y
  /// `university_email`. Hoy solo cambia el estado en memoria.
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

  /// Elige la universidad y descarta una verificación previa.
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
    final on = !f.contains(id);
    on ? f.add(id) : f.remove(id);
    final u = _user;
    if (u != null && _profile != null) _profile.setFavoriteDish(u.id, id, on);
    notifyListeners();
    return true;
  }

  /// Agrega o quita un restaurante de favoritos.
  bool toggleFavoriteRestaurant(String id) {
    if (!isLoggedIn) return false;
    final f = data.favoriteRestaurants;
    final on = !f.contains(id);
    on ? f.add(id) : f.remove(id);
    final u = _user;
    if (u != null && _profile != null) {
      _profile.setFavoriteBranch(u.id, id, on);
    }
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------ Direcciones

  /// Guarda una dirección nueva o editada.
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

    // Persistencia remota: alta (guarda su uuid) o edición.
    final u = _user;
    final profile = _profile;
    if (u != null && profile != null) {
      if (saved.dbId == null) {
        profile
            .addAddress(
              u.id,
              saved,
              makeDefault: data.defaultAddressId == saved.id,
            )
            .then((dbId) {
              if (dbId == null) return;
              saved.dbId = dbId;
              notifyListeners();
            });
      } else {
        profile.updateAddress(saved.dbId!, saved);
      }
    }

    notifyListeners();
    return saved;
  }

  /// Elimina una dirección y ajusta la predeterminada.
  void deleteAddress(String id) {
    // Se busca el uuid antes de quitarla de la lista local.
    String? dbId;
    for (final a in data.addresses) {
      if (a.id == id) {
        dbId = a.dbId;
        break;
      }
    }
    data.addresses.removeWhere((a) => a.id == id);
    if (data.defaultAddressId == id) {
      data.defaultAddressId = data.addresses.isEmpty
          ? null
          : data.addresses.first.id;
    }
    if (dbId != null && _profile != null) _profile.deleteAddress(dbId);
    notifyListeners();
  }

  /// Marca una dirección como predeterminada.
  void setDefaultAddress(String id) {
    data.defaultAddressId = id;
    final u = _user;
    String? dbId;
    for (final a in data.addresses) {
      if (a.id == id) {
        dbId = a.dbId;
        break;
      }
    }
    if (u != null && dbId != null && _profile != null) {
      _profile.setDefaultAddress(u.id, dbId);
    }
    notifyListeners();
  }

  /// Busca una dirección guardada por id.
  Address? addressById(String? id) {
    for (final a in data.addresses) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Guarda el medio de pago preferido.
  void setDefaultPayment(PaymentMethod m) {
    data.defaultPayment = m;
    notifyListeners();
  }

  // ------------------------------------------------------------ Gotas

  /// Suma Gotas y registra el movimiento en el historial.
  void _credit(UserData d, int amount, String reason) {
    d.gotas += amount;
    d.gotasHistory.insert(0, GotasEntry(reason, amount, _clock.now()));
  }

  /// Acredita Gotas a un usuario.
  void creditGotas(String userId, int amount, String reason) {
    if (amount <= 0) return;
    _credit(dataFor(userId), amount, reason);
    notifyListeners();
  }

  /// Descuenta Gotas si el saldo alcanza.
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

  /// Busca un cupón del usuario por id.
  Coupon? couponById(String? id) {
    for (final c in data.coupons) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Marca un cupón como usado o disponible.
  void setCouponUsed(String userId, String couponId, bool used) {
    for (final c in dataFor(userId).coupons) {
      if (c.id == couponId) c.used = used;
    }
    notifyListeners();
  }

  // ---------------------------------------------------------- Ajustes

  /// Guarda los ajustes y aplica el horario de demostración.
  void updateSettings(AppSettings s) {
    _settings = s;
    _clock.simulateLunch = s.demoLunch;
    final u = _user;
    if (u != null && _profile != null) _profile.saveSettings(u.id, s);
    notifyListeners();
  }

  // ------------------------------------------------------- Repartidor

  /// Guarda el perfil de repartidor y activa ese rol.
  void saveCourierProfile(CourierProfile p) {
    data.courierProfile = p;
    if (_user != null && p.phone.isNotEmpty && _user!.phone.isEmpty) {
      _user!.phone = p.phone;
    }
    _activeRole = UserRole.courier;
    notifyListeners();
  }

  /// Cambia la disponibilidad del repartidor.
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
