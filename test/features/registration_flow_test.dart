import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/auth/application/registration_flow.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void actor(String? id) { SupabaseConfig.debugUserIdOverride=id; SupabaseConfig.captureSession(); }
  setUp(() { actor(null); RegistrationFlow.reset(); FlutterSecureStorage.setMockInitialValues({}); actor('account-a'); });
  tearDown(() { actor(null); RegistrationFlow.reset(); });
  test('new Google account requires profile setup',() async {
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    expect(AppState.registrationCheckPending.value,isFalse);
    expect(AppState.profileCompletionRequired.value,isTrue);
  });
  test('completed existing profile opens the app on a fresh device',() async {
    await RegistrationFlow.refresh(profileCheck: (_) async=>false);
    expect(AppState.profileCompletionRequired.value,isFalse);
  });
  test('legacy account tour marker cannot bypass required profile setup', () async {
    const storage = FlutterSecureStorage();
    final key = RegistrationFlow.key('account-a');
    await storage.write(key: key, value: 'true');
    await RegistrationFlow.refresh(profileCheck: (_) async => true);
    expect(AppState.profileCompletionRequired.value, isTrue);
    expect(await storage.read(key: key), 'true');
  });
  test('unknown profile fails closed with retry instead of home',() async {
    await expectLater(RegistrationFlow.refresh(profileCheck: (_) async=>null),throwsStateError);
    expect(AppState.registrationCheckPending.value,isTrue);
    expect(AppState.registrationError.value,isNotNull);
    await RegistrationFlow.refresh(profileCheck: (_) async=>false);
    expect(AppState.registrationCheckPending.value,isFalse);
    expect(AppState.registrationError.value,isNull);
  });
  for(final change in ['account-switch','signout','same-account-relogin']) {
    test('late registration result cannot overwrite $change',() async {
      final response=Completer<bool?>();
      final old=RegistrationFlow.refresh(profileCheck: (_)=>response.future);
      actor(change=='account-switch'?'account-b':null);
      if(change=='same-account-relogin')actor('account-a');
      RegistrationFlow.reset();
      if(change!='signout') await RegistrationFlow.refresh(profileCheck: (_) async=>false);
      response.complete(true);
      await old;
      expect(AppState.profileCompletionRequired.value,isFalse);
    });
  }
  test('repeated auth notifications share one same-generation profile check',() async {
    final response=Completer<bool?>(); var calls=0;
    Future<bool?> check(String _) {calls++; return response.future;}
    final first=RegistrationFlow.refresh(profileCheck:check);
    final second=RegistrationFlow.refresh(profileCheck:check);
    expect(identical(first,second),isTrue); expect(calls,1);
    response.complete(true); await first; await second;
  });
}
