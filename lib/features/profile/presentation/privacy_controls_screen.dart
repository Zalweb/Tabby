import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/config/supabase_config.dart';
import '../application/privacy_export.dart';

class PrivacyControlsScreen extends StatefulWidget {
  const PrivacyControlsScreen({super.key, this.exporter});

  final PrivacyExport? exporter;

  @override
  State<PrivacyControlsScreen> createState() => _PrivacyControlsScreenState();
}

class _PrivacyControlsScreenState extends State<PrivacyControlsScreen> {
  late final PrivacyExport _exporter;
  late final bool Function() _current;
  String? _snapshot;
  String? _error;
  bool _loading = false;
  String? _requestId;
  String? _requestStatus;
  bool _statusChecked = false;
  String _section = 'expenses';
  String? _nextCursor;
  bool _hasLedgerPage = false;

  @override
  void initState() {
    super.initState();
    _exporter = widget.exporter ?? PrivacyExport.production();
    _current = _exporter.captureCurrent();
    SupabaseConfig.sessionRevision.addListener(_sessionChanged);
  }

  void _sessionChanged() {
    if (!_current() && mounted) {
      setState(() {
        _snapshot = null;
        _requestId = null;
        _requestStatus = null;
        _nextCursor = null;
        _error = 'The account changed. Open privacy controls again.';
      });
    }
  }

  @override
  void dispose() {
    SupabaseConfig.sessionRevision.removeListener(_sessionChanged);
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_loading || !_current()) return;
    setState(() {
      _loading = true;
      _snapshot = null;
      _hasLedgerPage = false;
      _nextCursor = null;
      _error = null;
    });
    try {
      final snapshot = await _exporter.load();
      if (mounted && _current()) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = _current()
              ? 'Could not prepare your copy. Please try again.'
              : 'The account changed. Open privacy controls again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _requestDeletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: const Text(
          'This submits a request for review. It does not immediately delete your account. Shared financial audit records must be retained while personal information is handled separately. Sign in again first if your last sign-in was more than five minutes ago.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Submit request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || !_current() || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _exporter.submitDeletionRequest();
      if (mounted && _current()) {
        setState(() {
          _requestId = result['id'] as String;
          _requestStatus = result['status'] as String;
          _statusChecked = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Request not confirmed. Sign in again and retry. Server privacy controls must also be available.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkStatus() async {
    if (_loading || !_current()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _exporter.deletionStatus();
      if (mounted && _current()) {
        setState(() {
          _requestId = result?['id'] as String?;
          _requestStatus = result?['status'] as String?;
          _statusChecked = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not check request status. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _ledgerPage({bool next = false}) async {
    if (_loading || !_current()) return;
    final after = next ? _nextCursor : null;
    if (next && after == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await _exporter.ledgerPage(_section, after: after);
      if (mounted && _current()) {
        setState(() {
          _snapshot = const JsonEncoder.withIndent('  ').convert(page);
          _nextCursor = page['next_cursor'] as String?;
          _hasLedgerPage = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not prepare this page. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Privacy & Your Data')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'What Tabby stores',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Text(
          'Tabby stores your profile, connections, shared expenses, payment '
          'submissions and attachments to keep your tabs in sync. Pending '
          'changes and private drafts may also be stored on your device.',
        ),
        const SizedBox(height: 20),
        const Text(
          'Who can see it',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Shared tab participants can see the records in their tabs. '
          'Saved receiving QR codes are intended for their owner, accepted '
          'friends on profiles and actual debtors in payment flows. '
          'A QR code or uploaded proof never confirms payment.',
        ),
        const SizedBox(height: 20),
        const Text(
          'A copy of your profile and contacts',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Prepare a server copy of your profile and contacts you created. '
          'This limited copy excludes shared ledger history, saved payment '
          'methods, media, notifications, authentication records and local '
          'drafts. It requires a connection and the privacy server update. '
          'You can select and copy the result. Keep it private: it contains '
          'personal information about you and your contacts.',
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _loading || !_current() ? null : _prepare,
          child: Text(_loading ? 'Preparing copy…' : 'Prepare profile copy'),
        ),
        const SizedBox(height: 20),
        const Text(
          'A copy of your records',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Choose shared history or your private receiving details, '
          'connection preferences, contacts and notices. Read up to 50 records at a time. '
          'Copy each page before continuing. Pages reflect the current server '
          'state and may change while you browse; they are not one frozen snapshot. '
          'Media files, authentication credentials and local drafts '
          'are excluded. This does not change your balances.',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _section,
          decoration: const InputDecoration(labelText: 'History records'),
          items: const [
            DropdownMenuItem(value: 'tabs', child: Text('Tabs')),
            DropdownMenuItem(value: 'expenses', child: Text('Expenses')),
            DropdownMenuItem(value: 'shares', child: Text('Expense shares')),
            DropdownMenuItem(value: 'payments', child: Text('Payments')),
            DropdownMenuItem(
              value: 'receiving_methods',
              child: Text('Your receiving details'),
            ),
            DropdownMenuItem(
              value: 'connections',
              child: Text('Your connection preferences'),
            ),
            DropdownMenuItem(value: 'contacts', child: Text('Your contacts')),
            DropdownMenuItem(
              value: 'notifications',
              child: Text('Your notifications'),
            ),
            DropdownMenuItem(value: 'reminders', child: Text('Your reminders')),
          ],
          onChanged: _loading || !_current()
              ? null
              : (value) {
                  if (value == null) return;
                  setState(() {
                    _section = value;
                    _snapshot = null;
                    _hasLedgerPage = false;
                    _nextCursor = null;
                  });
                },
        ),
        TextButton(
          onPressed: _loading || !_current() ? null : () => _ledgerPage(),
          child: const Text('Prepare first history page'),
        ),
        if (_hasLedgerPage)
          TextButton(
            onPressed: _loading || !_current() || _nextCursor == null
                ? null
                : () => _ledgerPage(next: true),
            child: const Text('Next history page'),
          ),
        if (_hasLedgerPage && _nextCursor == null)
          const Text('End of this history section.'),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Semantics(liveRegion: true, child: Text(_error!)),
        ],
        if (_snapshot != null && _current()) ...[
          const SizedBox(height: 12),
          SelectableText(_snapshot!),
          TextButton(
            onPressed: () => setState(() {
              _snapshot = null;
              _hasLedgerPage = false;
              _nextCursor = null;
            }),
            child: const Text('Clear displayed copy'),
          ),
        ],
        const SizedBox(height: 20),
        const Text(
          'Account deletion',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'A deletion request requires a sign-in within the last five minutes '
          'and the server privacy update. Submitting a request does not '
          'delete your account or shared financial history. Requests need '
          'review; no completion date is promised. Logging out or unfriending '
          'does not delete debts.',
        ),
        const SizedBox(height: 8),
        const Text(
          'After review, personal profile and receiving details are '
          'redacted, personal avatar/receiving QR images are removed and '
          'sign-in is disabled through Auth soft deletion. An anonymized '
          'service identity and shared financial records, descriptions, '
          'receipts and payment proofs are retained for audit. Copies '
          'already saved by other participants and local device drafts '
          'cannot be recalled by this request.',
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _loading || !_current() ? null : _requestDeletion,
          child: const Text('Request account deletion'),
        ),
        TextButton(
          onPressed: _loading || !_current() ? null : _checkStatus,
          child: const Text('Check deletion request status'),
        ),
        if (_statusChecked && _requestId == null && _current())
          const Text('No deletion request recorded for this account.'),
        if (_requestId != null && _current())
          SelectableText(
            'Deletion request: $_requestId. Status: $_requestStatus. '
            '${_requestStatus == 'requested' ? 'Your account has not been deleted.' : 'This is the latest status recorded by the service.'}',
          ),
      ],
    ),
  );
}
