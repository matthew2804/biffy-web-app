import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../domain/repositories/auth_repository.dart';
import '../../../domain/entities/user.dart';
import '../../../shared/state/session_controller.dart';

/// Etapa del inicio de sesión.
enum LoginStatus { idle, submitting, success, error }

/// Estado del formulario de login: envío, error, usuario y visibilidad.
class LoginState {
  /// Crea el estado inicial.
  const LoginState({
    this.status = LoginStatus.idle,
    this.error,
    this.user,
    this.obscure = true,
  });

  /// Etapa actual del envío.
  final LoginStatus status;

  /// Mensaje de error para la pantalla.
  final String? error;

  /// Usuario autenticado cuando el login termina bien.
  final AppUser? user;

  /// `true` si la contraseña se muestra oculta.
  final bool obscure;

  /// `true` mientras se espera la respuesta del backend.
  bool get isSubmitting => status == LoginStatus.submitting;

  /// Copia el estado cambiando solo lo indicado.
  LoginState copyWith({
    LoginStatus? status,
    String? error,
    AppUser? user,
    bool? obscure,
  }) => LoginState(
    status: status ?? this.status,
    error: error,
    user: user ?? this.user,
    obscure: obscure ?? this.obscure,
  );
}

/// Cubit del login: valida el formulario, llama a la sesión y publica el error.
///
/// Flujo: pantalla → [LoginCubit] → [SessionController.loginAsync] →
/// `AuthRepository` (memoria o Supabase).
class LoginCubit extends Cubit<LoginState> {
  /// Recibe la sesión que ejecuta el login real.
  LoginCubit(this._session) : super(const LoginState());

  final SessionController _session;

  /// Alterna la visibilidad de la contraseña.
  void toggleObscure() => emit(state.copyWith(obscure: !state.obscure));

  /// Limpia el error al volver a escribir.
  void clearError() {
    if (state.error != null) emit(state.copyWith(status: LoginStatus.idle));
  }

  /// Inicia sesión y devuelve el usuario, o `null` si falló.
  Future<AppUser?> submit(String email, String password) async {
    if (state.isSubmitting) return null;
    emit(state.copyWith(status: LoginStatus.submitting));
    try {
      final user = await _session.loginAsync(email, password);
      if (isClosed) return user;
      emit(state.copyWith(status: LoginStatus.success, user: user));
      return user;
    } on AuthException catch (e) {
      if (!isClosed) {
        emit(state.copyWith(status: LoginStatus.error, error: e.message));
      }
      return null;
    } on Object {
      if (!isClosed) {
        emit(
          state.copyWith(
            status: LoginStatus.error,
            error: 'No pudimos iniciar sesión. Revisa tu conexión.',
          ),
        );
      }
      return null;
    }
  }
}
