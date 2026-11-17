import 'dart:async';
import 'dart:collection';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabby/core/config/app_state.dart';
import 'package:tabby/core/config/supabase_config.dart';
import 'package:tabby/features/auth/application/registration_flow.dart';

class _FailingMap extends MapBase<String,String> {
  final _values=<String,String>{};
  @override String? operator [](Object? key)=>_values[key];
  @override void operator []=(String key,String value)=>throw StateError('synthetic write failure');
  @override void clear()=>_values.clear();
  @override Iterable<String> get keys=>_values.keys;
  @override String? remove(Object? key)=>_values.remove(key);
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  void actor(String? id) { SupabaseConfig.debugUserIdOverride=id; SupabaseConfig.captureSession(); }
  setUp(() { actor(null); RegistrationFlow.reset(); FlutterSecureStorage.setMockInitialValues({}); actor('account-a'); });
  tearDown(() { actor(null); RegistrationFlow.reset(); });
  test('new Google account requires introduction and profile setup',() async {
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    expect(AppState.registrationCheckPending.value,isFalse);
    expect(AppState.introductionRequired.value,isTrue);
    expect(AppState.profileCompletionRequired.value,isTrue);
  });
  test('completed existing profile skips introduction even on a fresh device',() async {
    await RegistrationFlow.refresh(profileCheck: (_) async=>false);
    expect(AppState.introductionRequired.value,isFalse);
    expect(AppState.profileCompletionRequired.value,isFalse);
  });
  test('introduction acknowledgment resumes unfinished profile without repeating',() async {
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    expect(await RegistrationFlow.finishIntroduction(),isTrue);
    RegistrationFlow.reset();
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    expect(AppState.introductionRequired.value,isFalse);
    expect(AppState.profileCompletionRequired.value,isTrue);
    actor('account-b');
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    expect(AppState.introductionRequired.value,isTrue);
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
      expect(AppState.introductionRequired.value,isFalse);
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
  test('failed acknowledgment never skips setup or silently marks introduction complete',() async {
    FlutterSecureStorage.setMockInitialValues(_FailingMap());
    await RegistrationFlow.refresh(profileCheck: (_) async=>true);
    await expectLater(RegistrationFlow.finishIntroduction(),throwsStateError);
    expect(AppState.introductionRequired.value,isTrue);
    expect(AppState.profileCompletionRequired.value,isTrue);
  });
  test('signed-out introduction cannot write another account acknowledgment',() async {
    actor(null); expect(await RegistrationFlow.finishIntroduction(),isFalse);
  });
}
