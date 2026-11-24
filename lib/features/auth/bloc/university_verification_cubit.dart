import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../shared/state/session_controller.dart';

/// Estado de la verificación del correo institucional.
class UniversityVerificationState {
  /// Crea el estado inicial; se sincroniza con la sesión al abrir Campus.
  const UniversityVerificationState({
    this.isVerified = false,
    this.expiresAt,
    this.codeSent = false,
    this.demoCode,
    this.sending = false,
    this.confirming = false,
    this.error,
  });

  /// `true` si la verificación está activa y no vencida.
  final bool isVerified;

  /// Fecha de vencimiento de la verificación.
  final DateTime? expiresAt;

  /// `true` cuando ya se envió un código y toca escribir el código.
  final bool codeSent;

  /// Código visible solo en modo demo.
  final String? demoCode;

  /// `true` mientras se envía el código.
  final bool sending;

  /// `true` mientras se confirma el código.
  final bool confirming;

  /// Último error para la pantalla.
  final String? error;

  /// Copia el estado cambiando solo lo indicado.
  UniversityVerificationState copyWith({
    bool? isVerified,
    DateTime? expiresAt,
    bool? codeSent,
    String? demoCode,
    bool? sending,
    bool? confirming,
    String? error,
  }) => UniversityVerificationState(
    isVerified: isVerified ?? this.isVerified,
    expiresAt: expiresAt ?? this.expiresAt,
    codeSent: codeSent ?? this.codeSent,
    demoCode: demoCode,
    sending: sending ?? this.sending,
    confirming: confirming ?? this.confirming,
    error: error,
  );
}

/// Cubit de Campus: envía el código, lo confirma y controla el vencimiento.
///
/// La lógica de negocio sigue en `SessionController`; este cubit solo expone
/// el estado de la pantalla y traduce los resultados a mensajes.
class UniversityVerificationCubit extends Cubit<UniversityVerificationState> {
  /// Sincroniza el estado inicial con la sesión actual.
  UniversityVerificationCubit(this._session)
    : super(
        UniversityVerificationState(
          isVerified: _session.isVerifiedStudent,
          expiresAt: _session.verificationExpiresAt,
        ),
      );

  final SessionController _session;

  /// Vuelve a leer el estado desde la sesión (por ejemplo al reabrir Campus).
  void refresh() {
    emit(
      state.copyWith(
        isVerified: _session.isVerifiedStudent,
        expiresAt: _session.verificationExpiresAt,
      ),
    );
  }

  /// Limpia el error al cambiar de campo.
  void clearError() {
    if (state.error != null) emit(state.copyWith(error: null));
  }

  /// Descarta el código pendiente al cambiar de universidad.
  void clearCode() =>
      emit(state.copyWith(codeSent: false, demoCode: null, error: null));

  /// Pide un código para el correo institucional.
  Future<void> sendCode({
    required String universityId,
    required String email,
    required bool renewal,
  }) async {
    if (state.sending) return;
    emit(state.copyWith(sending: true, error: null));
    final result = await _session.sendUniversityCodeAsync(
      universityId,
      email,
      renewal: renewal,
    );
    if (isClosed) return;

    if (result == VerifyResult.codeSent) {
      emit(
        state.copyWith(
          sending: false,
          codeSent: true,
          demoCode: _session.pendingUniversityCode,
        ),
      );
      return;
    }
    emit(state.copyWith(sending: false, error: _message(result)));
  }

  /// Confirma el código y activa Campus por 30 días.
  Future<void> confirmCode({
    required String universityId,
    required String email,
    required String code,
  }) async {
    if (state.confirming) return;
    emit(state.copyWith(confirming: true, error: null));
    final result = await _session.confirmUniversityCodeAsync(
      universityId: universityId,
      email: email,
      code: code,
    );
    if (isClosed) return;

    if (result == VerifyResult.ok) {
      emit(
        state.copyWith(
          confirming: false,
          codeSent: false,
          demoCode: null,
          isVerified: true,
          expiresAt: _session.verificationExpiresAt,
        ),
      );
      return;
    }
    emit(state.copyWith(confirming: false, error: _message(result)));
  }

  /// Traduce el resultado de la verificación a un mensaje en español.
  String _message(VerifyResult result) => switch (result) {
    VerifyResult.ok || VerifyResult.codeSent => '',
    VerifyResult.invalidEmail => 'Escribe un correo válido',
    VerifyResult.domainMismatch => 'El correo no pertenece a la universidad',
    VerifyResult.unknownUniversity => 'No encontramos esa universidad',
    VerifyResult.notAuthenticated ||
    VerifyResult.notLoggedIn => 'Inicia sesión primero',
    VerifyResult.invalidToken => 'El código no es correcto',
    VerifyResult.expiredToken => 'El código venció. Pide uno nuevo',
    VerifyResult.tooManyAttempts => 'Demasiados intentos. Pide un código nuevo',
    VerifyResult.notFound => 'No hay una verificación pendiente',
    VerifyResult.rateLimited => 'Espera un momento antes de pedir otro código',
    VerifyResult.tokenRequired => 'Primero pide el código a tu correo',
    VerifyResult.rpcError => 'No pudimos completar la verificación',
  };
}
