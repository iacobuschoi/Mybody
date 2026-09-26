import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 로컬 알림(끼니 · 간식 · 운동 독촉)이 앱을 쓰는 중에도 뜨고, 누르면 앱이 받도록
    // (flutter_local_notifications 의 iOS 설정). 앱 알림(firebase_messaging)도 이 대리자를
    // 그대로 씁니다 — 대리자가 FlutterAppDelegate 이면 그 플러그인은 자리를 바꾸지 않습니다.
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // 앱을 쓰는 중에 온 알림(로컬 · 원격)을 어떻게 보일지 여기서 한 번만 정합니다.
  // FlutterAppDelegate 는 이 물음을 등록된 플러그인 모두에게 차례로 넘기는데, 메시징 플러그인은
  // 로컬 알림에도 "안 보임" 으로 먼저 답합니다. 그대로 두면 끼니 · 간식 알림까지 앱 안에서 안 뜹니다.
  // 플러그인들이 할 일(앱 알림을 Dart 의 onMessage 로 넘기기)은 그대로 하게 하고, 답은 우리가 합니다.
  // 이렇게 하면 친구 알림도 시스템이 띄우므로 Dart 쪽은 아이폰에서 다시 띄우지 않습니다(native_push.dart).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    super.userNotificationCenter(center, willPresent: notification) { _ in }
    completionHandler([.banner, .list, .sound])
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
