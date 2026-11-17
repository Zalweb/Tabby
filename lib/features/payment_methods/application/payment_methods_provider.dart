import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
import '../../../core/config/session_scope.dart';
import '../../tabs/application/tabby_providers.dart';
import '../../tabs/data/supabase_tabby_repository.dart';
import '../domain/payment_method.dart';

class PaymentMethodsState {
  const PaymentMethodsState({
    this.methods = const [],
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
  });

  final List<PaymentMethod> methods;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;

  PaymentMethodsState copyWith({
    List<PaymentMethod>? methods,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PaymentMethodsState(
      methods: methods ?? this.methods,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class PaymentMethodsNotifier extends StateNotifier<PaymentMethodsState> {
  PaymentMethodsNotifier({
    required this.ownerUserId,
    SupabaseTabbyRepository? repository,
    this.legacyUser,
    SessionStamp Function()? captureSession,
    bool Function(SessionStamp)? sessionIsCurrent,
  })  : repository = repository ?? SupabaseTabbyRepository.instance,
        _captureSession = captureSession ?? SupabaseConfig.captureSession,
        _sessionIsCurrent = sessionIsCurrent ?? SupabaseConfig.isCurrentSession,
        super(const PaymentMethodsState()) {
    load();
  }

  final String ownerUserId;
  final SupabaseTabbyRepository repository;
  final dynamic legacyUser;
  final SessionStamp Function() _captureSession;
  final bool Function(SessionStamp) _sessionIsCurrent;

  int _loadGeneration = 0;

  Future<bool> load() async {
    final session = _captureSession();
    final generation = ++_loadGeneration;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final methods = await repository.fetchPaymentMethods(ownerUserId);
      if (!mounted ||
          !_sessionIsCurrent(session) ||
          generation != _loadGeneration) {
        return false;
      }

      final fallback =
          methods.isEmpty && !SupabaseConfig.isInitialized && legacyUser != null
              ? PaymentMethod.fromLegacyUser(legacyUser.toMap())
              : const <PaymentMethod>[];
      state = state.copyWith(
        methods:
            PaymentMethod.defaultFirst(methods.isEmpty ? fallback : methods),
        isLoading: false,
      );
      return true;
    } catch (_) {
      if (mounted &&
          _sessionIsCurrent(session) &&
          generation == _loadGeneration) {
        state = state.copyWith(
            methods: const [],
            isLoading: false,
            errorMessage:
                'Could not refresh payment methods. Try again before using a QR.');
      }
      return false;
    }
  }

  Future<bool> saveDraft(PaymentMethodDraft draft,
          {required bool makeDefault}) =>
      _save(draft, makeDefault: makeDefault);

  Future<bool> updateDraft(PaymentMethod current, PaymentMethodDraft draft) =>
      _save(draft, makeDefault: current.isDefault, current: current);

  Future<bool> _save(PaymentMethodDraft draft,
      {required bool makeDefault, PaymentMethod? current}) async {
    if (state.isSaving) return false;
    final session = _captureSession();
    if (!draft.isValid) {
      state = state.copyWith(
          errorMessage: 'Add a payment method name before saving.');
      return false;
    }
    ++_loadGeneration;
    state = state.copyWith(isSaving: true, isLoading: false, clearError: true);
    try {
      final saved = current == null
          ? await repository.createPaymentMethod(
              ownerUserId: ownerUserId,
              draft: draft,
              makeDefault: makeDefault || state.methods.isEmpty)
          : await repository.updatePaymentMethod(
              current: current, draft: draft);
      if (!mounted || !_sessionIsCurrent(session)) return false;
      if (saved == null) {
        state = state.copyWith(
            errorMessage:
                'Could not verify the save. Your draft is kept. Refresh before retrying.');
        return false;
      }
      state = state.copyWith(
          methods: PaymentMethod.defaultFirst([
        ...state.methods.where((method) => method.id != saved.id).map(
            (method) =>
                saved.isDefault ? method.copyWith(isDefault: false) : method),
        saved,
      ]));
      await load();
      return true;
    } catch (_) {
      if (mounted && _sessionIsCurrent(session)) {
        state = state.copyWith(
            errorMessage:
                'Payment method could not be saved. Please try again.');
      }
      return false;
    } finally {
      if (mounted && _sessionIsCurrent(session)) {
        state = state.copyWith(isSaving: false);
      }
    }
  }

  Future<bool> setPreferred(String methodId) =>
      _mutate(methodId, remove: false);
  Future<bool> remove(String methodId) => _mutate(methodId, remove: true);

  Future<bool> _mutate(String methodId, {required bool remove}) async {
    if (state.isSaving) return false;
    final session = _captureSession();
    ++_loadGeneration;
    state = state.copyWith(isSaving: true, isLoading: false, clearError: true);
    try {
      final success = remove
          ? await repository.deletePaymentMethod(methodId)
          : await repository.setPreferredPaymentMethod(methodId);
      if (!mounted || !_sessionIsCurrent(session)) return false;
      if (!success) {
        state = state.copyWith(
            errorMessage:
                'Payment method could not be updated. Please try again.');
        return false;
      }
      // Remove immediately after acknowledgment; never select from the stale list.
      state = state.copyWith(
          methods: PaymentMethod.defaultFirst(state.methods
              .where((method) => !remove || method.id != methodId)
              .map((method) => remove
                  ? method
                  : method.copyWith(isDefault: method.id == methodId))));
      await load(); // Read the server's atomic successor/preference and revisions.
      return mounted && _sessionIsCurrent(session);
    } catch (_) {
      if (mounted && _sessionIsCurrent(session)) {
        state = state.copyWith(
            errorMessage:
                'Payment method could not be updated. Refresh and try again.');
      }
      return false;
    } finally {
      if (mounted && _sessionIsCurrent(session)) {
        state = state.copyWith(isSaving: false);
      }
    }
  }
}

final paymentMethodsProvider = StateNotifierProvider.family<
    PaymentMethodsNotifier, PaymentMethodsState, String>((ref, ownerUserId) {
  void sessionChanged() => ref.invalidateSelf();
  SupabaseConfig.sessionRevision.addListener(sessionChanged);
  ref.onDispose(
      () => SupabaseConfig.sessionRevision.removeListener(sessionChanged));
  final user = ref.watch(currentUserProvider);
  return PaymentMethodsNotifier(
    ownerUserId: ownerUserId,
    legacyUser: user.id == ownerUserId ? user : null,
  );
});

class TabPaymentMethodRequest {
  const TabPaymentMethodRequest(this.tabId, this.payeeUserId,
      {this.sessionKey = ''});
  final String sessionKey;

  final String tabId;
  final String payeeUserId;

  @override
  bool operator ==(Object other) {
    return other is TabPaymentMethodRequest &&
        other.tabId == tabId &&
        other.payeeUserId == payeeUserId &&
        other.sessionKey == sessionKey;
  }

  @override
  int get hashCode => Object.hash(tabId, payeeUserId, sessionKey);
}

final tabPaymentMethodsProvider = FutureProvider.autoDispose
    .family<List<PaymentMethod>, TabPaymentMethodRequest>((ref, request) async {
  ref.watch(currentUserProvider);
  final session = SupabaseConfig.captureSession();
  final methods =
      await SupabaseTabbyRepository.instance.fetchPaymentMethodsForTab(
    tabId: request.tabId,
    payeeUserId: request.payeeUserId,
  );
  return SupabaseConfig.isCurrentSession(session) ? methods : const [];
});
