import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/entities/user.dart';
import '../../../domain/repositories/auth_repository.dart';
import '../../../shared/state/session_controller.dart';

/// Etapa del registro de una cuenta.
enum RegisterStatus { idle, submitting, success, error }

/// Estado del registro: rol elegido, envío, error y siguiente pantalla.
class RegisterState {
  /// Crea el estado inicial como comprador.
  const RegisterState({
    this.role = UserRole.buyer,
    this.status = RegisterStatus.idle,
    this.error,
    this.user,
    this.nextLocation,
  });

  /// Rol que se está registrando.
  final UserRole role;

  /// Etapa actual del envío.
  final RegisterStatus status;

  /// Mensaje de error para la pantalla.
  final String? error;

  /// Usuario creado cuando el registro termina bien.
  final AppUser? user;

  /// Ruta a la que debe ir la pantalla después del registro.
  final String? nextLocation;

  /// `true` mientras se espera la respuesta del backend.
  bool get isSubmitting => status == RegisterStatus.submitting;

  /// Copia el estado cambiando solo lo indicado.
  RegisterState copyWith({
    UserRole? role,
    RegisterStatus? status,
    String? error,
    AppUser? user,
    String? nextLocation,
  }) => RegisterState(
    role: role ?? this.role,
    status: status ?? this.status,
    error: error,
    user: user ?? this.user,
    nextLocation: nextLocation,
  );
}

/// Cubit del registro: elige el rol, valida y crea la cuenta.
///
/// El restaurante no crea la cuenta aquí: pasa al formulario ampliado del
/// negocio, que es quien termina el alta.
class RegisterCubit extends Cubit<RegisterState> {
  /// Recibe la sesión que ejecuta el registro real.
  RegisterCubit(this._session) : super(const RegisterState());

  final SessionController _session;

  /// Cambia el rol que se va a registrar.
  void roleChanged(UserRole role) {
    if (state.isSubmitting) return;
    emit(state.copyWith(role: role));
  }

  /// Limpia el error al volver a escribir.
  void clearError() {
    if (state.error != null) emit(state.copyWith(status: RegisterStatus.idle));
  }

  /// Crea la cuenta y devuelve [RegisterState] con el usuario o el error.
  Future<RegisterState> submit({
    required String name,
    required String email,
    required String password,
    required String phone,
  }) async {
    if (state.isSubmitting) return state;

    // El comercio se registra en el formulario ampliado de negocio.
    if (state.role == UserRole.restaurant) {
      emit(
        state.copyWith(
          status: RegisterStatus.success,
          nextLocation: '/negocio/registro',
        ),
      );
      return state;
    }

    emit(state.copyWith(status: RegisterStatus.submitting));
    try {
      final user = await _session.registerAsync(
        name: name,
        email: email,
        password: password,
        role: state.role,
        phone: phone,
      );
      if (isClosed) return state;
      final next = state.role == UserRole.courier
          ? '/repartidor/registro'
          : null;
      emit(
        state.copyWith(
          status: RegisterStatus.success,
          user: user,
          nextLocation: next,
        ),
      );
      return state;
    } on AuthException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: RegisterStatus.error, error: e.message));
      }
      return state;
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: RegisterStatus.error,
            error: 'No pudimos crear la cuenta. Revisa tu conexión.',
          ),
        );
      }
      return state;
    }
  }
}
