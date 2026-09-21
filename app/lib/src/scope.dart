/* =============================================================================
 * scope.dart — 화면들이 상태에 닿는 길
 *
 * 상태 관리 라이브러리를 안 씁니다. 코어가 이미 바뀜을 알려 주고 있고
 * (store.onChange), 화면이 할 일은 그때 다시 그리는 것뿐입니다.
 * 라이브러리를 하나 더 얹으면 "왜 안 그려지지" 를 두 군데서 찾게 됩니다.
 * ========================================================================== */
import 'package:flutter/widgets.dart';

import 'api.dart';
import 'app_state.dart';

class Scope extends InheritedNotifier<AppState> {
  const Scope({super.key, required AppState state, required this.api,
      required this.onServerChange, required super.child})
      : super(notifier: state);

  final Api api;

  /// 서버 주소를 바꾸면 Api 를 새로 만들어야 합니다 (토큰도 같이 다시 읽습니다).
  final Future<void> Function(String) onServerChange;

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Scope>()!.notifier!;

  static Api apiOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Scope>()!.api;

  static Future<void> Function(String) serverSetterOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Scope>()!.onServerChange;

  @override
  bool updateShouldNotify(covariant InheritedNotifier<AppState> oldWidget) => true;
}
