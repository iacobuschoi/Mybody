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

## APK 는 깃허브가 만듭니다

여기에는 안드로이드 SDK 가 없습니다. 코드를 올리면 깃허브 컴퓨터가 앱
파일을 만들어 두고, Actions 탭 → Artifacts 에서 받습니다.
받는 법·폰에 넣는 법·서명 열쇠: [`../docs/APK.md`](../docs/APK.md)

`tools/test-android.js` 가 설정을 봅니다 (인터넷 권한, 앱 아이디, 이름,
아이콘, 서명, 빌드 번호). 빌드 쪽에서는 **나온 APK 를 열어서** 권한이
정말 들어갔는지 다시 봅니다 — 권한은 빠져도 빌드가 성공하기 때문입니다.

다만 **진짜 폰에서 켜 본 적은 아직 없습니다.**
