import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/supabase_config.dart';
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
  })  : repository = repository ?? SupabaseTabbyRepository.instance,
        super(const PaymentMethodsState()) {
    load();
  }

  final String ownerUserId;
  final SupabaseTabbyRepository repository;
  final dynamic legacyUser;

  Future<void> load() async {
    state = state.copyWith(isLoading: true, clearError: true);
    final methods = await repository.fetchPaymentMethods(ownerUserId);
    if (!mounted) return;

    final fallback =
        methods.isEmpty && !SupabaseConfig.isInitialized && legacyUser != null
            ? PaymentMethod.fromLegacyUser(legacyUser.toMap())
            : const <PaymentMethod>[];
    state = state.copyWith(
      methods: PaymentMethod.defaultFirst(methods.isEmpty ? fallback : methods),
      isLoading: false,
    );
  }

  Future<bool> saveDraft(
    PaymentMethodDraft draft, {
    required bool makeDefault,
  }) async {
    if (!draft.isValid) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Add a payment method name before saving.',
      );
      return false;
    }

    state = state.copyWith(isSaving: true, clearError: true);
    final saved = await repository.createPaymentMethod(
      ownerUserId: ownerUserId,
      draft: draft,
      makeDefault: makeDefault || state.methods.isEmpty,
    );
    if (!mounted) return false;

    if (saved == null) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: SupabaseConfig.isInitialized
            ? 'Payment method could not be saved. Please try again.'
            : 'Payment methods require an internet connection to save.',
      );
      return false;
    }

    state = state.copyWith(
      methods: PaymentMethod.defaultFirst([
        ...state.methods.map((method) => method.copyWith(isDefault: false)),
        saved,
      ]),
      isSaving: false,
    );
    return true;
  }

  Future<bool> setPreferred(String methodId) async {
    final saved = await repository.setPreferredPaymentMethod(methodId);
    if (!saved || !mounted) return false;
    state = state.copyWith(
      methods: PaymentMethod.defaultFirst(state.methods.map(
        (method) => method.copyWith(isDefault: method.id == methodId),
      )),
    );
    return true;
  }

  Future<bool> remove(String methodId) async {
    final removed = await repository.deletePaymentMethod(methodId);
    if (!removed || !mounted) return false;
    final remaining =
        state.methods.where((method) => method.id != methodId).toList();
    if (remaining.isNotEmpty && !remaining.any((method) => method.isDefault)) {
      final promoted = remaining.first;
      await setPreferred(promoted.id);
      return true;
    }
    state = state.copyWith(methods: PaymentMethod.defaultFirst(remaining));
    return true;
  }
}

final paymentMethodsProvider = StateNotifierProvider.family<
    PaymentMethodsNotifier, PaymentMethodsState, String>((ref, ownerUserId) {
  final user = ref.watch(currentUserProvider);
  return PaymentMethodsNotifier(
    ownerUserId: ownerUserId,
    legacyUser: user.id == ownerUserId ? user : null,
  );
});

class TabPaymentMethodRequest {
  const TabPaymentMethodRequest(this.tabId, this.payeeUserId);

  final String tabId;
  final String payeeUserId;

  @override
  bool operator ==(Object other) {
    return other is TabPaymentMethodRequest &&
        other.tabId == tabId &&
        other.payeeUserId == payeeUserId;
  }

  @override
  int get hashCode => Object.hash(tabId, payeeUserId);
}

final tabPaymentMethodsProvider =
    FutureProvider.family<List<PaymentMethod>, TabPaymentMethodRequest>(
        (ref, request) {
  return SupabaseTabbyRepository.instance.fetchPaymentMethodsForTab(
    tabId: request.tabId,
    payeeUserId: request.payeeUserId,
  );
});
