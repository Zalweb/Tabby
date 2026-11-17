class SessionStamp {
  const SessionStamp(this.accountId, this.generation);
  final String? accountId;
  final int generation;
}

/// A logout/re-login of the same account is still a new result scope.
class SessionScope {
  String? _accountId;
  int _generation = 0;
  void advance(String? accountId) {
    _accountId = accountId;
    _generation++;
  }

  SessionStamp capture(String? accountId) {
    if (_accountId != accountId) advance(accountId);
    return SessionStamp(accountId, _generation);
  }

  bool isCurrent(SessionStamp stamp, String? accountId) =>
      stamp.accountId == accountId &&
      stamp.accountId == _accountId &&
      stamp.generation == _generation;
}
