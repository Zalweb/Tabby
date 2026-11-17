import '../../../core/utils/currency_formatter.dart';
import 'models.dart';

class CustomSplit {
  CustomSplit({
    required Map<PartyRef, int> baseShares,
    this.taxBasisPoints = 0,
    this.serviceBasisPoints = 0,
  }) : baseShares = Map.unmodifiable(baseShares) {
    if (baseShares.isEmpty ||
        baseShares.length > 100 ||
        baseShares.keys.any((p) => p.id.isEmpty) ||
        baseShares.values.any((n) => n < 0) ||
        base <= 0 ||
        taxBasisPoints < 0 ||
        taxBasisPoints > 10000 ||
        serviceBasisPoints < 0 ||
        serviceBasisPoints > 10000 ||
        total > CurrencyFormatter.maxAmountCentavos) {
      throw const FormatException('Enter valid shares and rates.');
    }
  }
  final Map<PartyRef, int> baseShares;
  final int taxBasisPoints, serviceBasisPoints;
  static String key(PartyRef p) => '${p.kind.name}:${p.id}';
  int get base => baseShares.values.fold(0, (a, b) => a + b);
  int _charge(int rate) =>
      ((BigInt.from(base) * BigInt.from(rate) + BigInt.from(5000)) ~/
              BigInt.from(10000))
          .toInt();
  int get tax => _charge(taxBasisPoints);
  int get service => _charge(serviceBasisPoints);
  int get total => base + tax + service;
  Map<PartyRef, int> _allocate(int charge) {
    final denominator = BigInt.from(base);
    final product = {
      for (final p in baseShares.keys)
        p: BigInt.from(charge) * BigInt.from(baseShares[p]!),
    };
    final result = {
      for (final p in baseShares.keys) p: (product[p]! ~/ denominator).toInt(),
    };
    final order = baseShares.keys.toList()
      ..sort((a, b) {
        final remainder = (product[b]! % denominator).compareTo(
          product[a]! % denominator,
        );
        return remainder != 0 ? remainder : key(a).compareTo(key(b));
      });
    final remaining = charge - result.values.fold(0, (a, b) => a + b);
    for (var i = 0; i < remaining; i++) {
      result[order[i]] = result[order[i]]! + 1;
    }
    return result;
  }

  Map<PartyRef, int> get shares {
    final taxes = _allocate(tax), fees = _allocate(service);
    return {
      for (final p in baseShares.keys) p: baseShares[p]! + taxes[p]! + fees[p]!,
    };
  }

  Map<PartyRef, int> rescaleBase(int total) {
    if (total <= 0 || total > CurrencyFormatter.maxAmountCentavos) {
      throw const FormatException('Enter a valid base amount.');
    }
    return _allocate(total);
  }

  Map<String, dynamic> toCommand({
    required String actor,
    required String tabId,
    required PartyRef payer,
    required String description,
    String category = 'other',
    String? dueDate,
  }) {
    if (!baseShares.containsKey(payer) || description.trim().isEmpty) {
      throw const FormatException('Choose the payer and a description.');
    }
    final order = baseShares.keys.toList()
      ..sort((a, b) => key(a).compareTo(key(b)));
    final allocated = shares;
    return {
      'p_expected_actor': actor,
      'p_tab_id': tabId,
      'p_description': description.trim(),
      'p_category': category,
      'p_total_amount_centavos': total,
      'p_paid_by_user_id': payer.id,
      'p_due_date': dueDate,
      'p_receipt_url': null,
      'p_participants': [
        for (final p in order)
          {
            p.kind == PartyKind.user ? 'user_id' : 'contact_id': p.id,
            'participant_role': p == payer ? 'payer' : 'debtor',
            'share_amount_centavos': allocated[p],
            'acknowledged': false,
          },
      ],
      'split': {
        'base_centavos': base,
        'tax_basis_points': taxBasisPoints,
        'service_basis_points': serviceBasisPoints,
        'base_shares': [
          for (final p in order) {'party': p.toMap(), 'amount': baseShares[p]},
        ],
      },
    };
  }
}
