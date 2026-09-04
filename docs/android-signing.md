# Android 릴리즈 서명 키 관리

현재 개발 PC에는 `android/key.properties`와 해당 keystore 파일이 모두 있습니다.
두 파일은 `.gitignore`에 포함되어 Git에 올라가지 않습니다. 릴리즈 빌드는 이제
서명 설정이 없으면 debug 키로 폴백하지 않고 즉시 실패합니다.

## 처음 키를 만들 때

Play Console에 이미 출시한 앱이라면 새 키를 만들기 전에 기존 업로드 키를
사용해야 합니다. Google Play App Signing을 사용 중인 경우 앱 서명 키와 업로드
키는 서로 다르며, 개발자는 **업로드 키**를 보관합니다.

```bash
keytool -genkeypair -v \
  -keystore android/upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload

cp android/key.properties.example android/key.properties
```

그다음 `android/key.properties`의 네 값을 실제 값으로 바꿉니다.

```properties
storeFile=../upload-keystore.jks
storePassword=실제_저장소_비밀번호
keyAlias=upload
keyPassword=실제_키_비밀번호
```

## 반드시 백업할 것

1. `upload-keystore.jks`
2. alias
3. store password
4. key password

keystore와 비밀번호는 서로 다른 비밀 저장소에 보관합니다. Git, 메신저,
공유 드라이브, 저장소의 `.env` 파일에는 올리지 않습니다.

## 기존 비밀번호 교체

과거 추적 문서에 서명 비밀번호가 평문으로 기록된 이력이 있으므로 현재 keystore의
인증정보를 교체해야 합니다. 비밀번호를 명령행 인자로 전달하지 말고 아래 명령의
대화형 입력을 사용합니다.

```bash
keytool -storepasswd -keystore android/upload-keystore.jks
keytool -keypasswd -keystore android/upload-keystore.jks -alias YOUR_ALIAS
```

교체 후 로컬 `android/key.properties`와 CI Secret을 함께 갱신합니다. 비밀번호
교체는 인증서 자체를 바꾸지 않으므로 기존 Play 앱의 업로드 키 인증서는 유지됩니다.
이미 원격 저장소에 과거 커밋이 올라갔다면 문서 삭제만으로 노출이 해소되지 않습니다.

## 로컬 검증

```bash
flutter build appbundle --release
```

성공 결과는 `build/app/outputs/bundle/release/app-release.aab`입니다.
Google Play에는 APK가 아니라 AAB 업로드를 권장합니다.

## CI 설정

CI에서는 keystore를 암호화된 secret 또는 Base64 secret으로 복원하고 아래 환경
변수를 빌드 작업에 전달할 수 있습니다.

```text
KEYSTORE_FILE
KEYSTORE_PASSWORD
KEY_ALIAS
KEY_PASSWORD
```

로그에 secret 값을 출력하지 말고, 작업이 끝나면 복원한 keystore를 삭제합니다.

## 키를 잃어버린 경우

- Google Play App Signing 사용 중: Play Console에서 업로드 키 재설정을 요청합니다.
- 미사용 상태에서 앱 서명 키를 잃어버림: 기존 앱 업데이트가 불가능할 수 있습니다.
- 이미 출시한 앱의 `applicationId`는 변경하지 않습니다. 변경하면 새 앱으로 인식됩니다.
