# app — 설치하는 앱 (Flutter)

웹 앱(`prototype/`)과 **같은 서버를 봅니다.** 그래서 옮기는 동안에도
친구들은 쓰던 걸 계속 쓰면 됩니다.

옮기는 일이 어디까지 왔는지, 무엇을 어떻게 검증했는지는
[`docs/FLUTTER.md`](../docs/FLUTTER.md) 에 적혀 있습니다.

## 여기 있는 것

```
lib/main.dart        앱이 서는 자리 — 상태·서버 주소·오류 화면
lib/src/ui/          화면 조각 (카드 · 숫자 · 차트 · 기호)
lib/src/screens/     화면
assets/fonts/        글꼴 — 앱 안에 넣어 둡니다 (아래 참고)
test/                화면이 서는지 보는 시험
```

**계산은 여기 없습니다.** 엔진·검산·모드 선택·식품표는 전부
`packages/mybody_core/` 에 있습니다. Flutter 를 안 깔아도 `dart test` 로
돌아가야 검증이 빨라서 그렇게 나눠 뒀습니다.

## 돌려 보기

```sh
cd app && flutter test          # 화면이 서는가
node ../tools/difftest.js       # 계산이 웹 앱과 같은 답을 내는가
node ../tools/test-fontcover.js # 그리는 글자가 앱 안에 다 있는가
```

웹으로 띄워서 눈으로 보기:

```sh
node tools/build-flutter-web.js
STATIC=app/build/web node tools/serve.js
```

## 글꼴을 앱 안에 넣어 두는 이유

Flutter 는 글꼴에 없는 글자를 `fonts.gstatic.com` 에서 받아 오려 합니다.
망이 막힌 곳에서는 그 자리가 네모가 되고, 안 막힌 곳에서는 **몸 관리 앱을
켤 때마다 구글에 신호가 갑니다.**

그래서 한글을 통째로 넣고(11,172자), 화면에 나갈 수 있는 글자가 전부
들어 있는지 시험으로 봅니다. 빠진 게 있으면 `node tools/fix-fonts.js` 가
채웁니다.

`Roboto` 라는 이름표가 붙은 48KB 짜리도 하나 있습니다. CanvasKit 은 그
이름의 글꼴이 없으면 **쓰든 안 쓰든** 구글에서 Roboto 를 받아 오기
때문입니다. 알맹이는 NotoSansKR 에서 라틴만 떼어낸 것입니다.

## APK 는 여기서 만들어 본 적이 없습니다

개발 컨테이너에 안드로이드 SDK 가 없어서 `flutter build apk` 를 **한 번도
돌려 보지 못했습니다.** 웹으로 빌드해서 화면을 도는 것까지만 확인했습니다.
폰에 올리기 전에 SDK 가 있는 곳에서 한 번 빌드해 봐야 합니다.
