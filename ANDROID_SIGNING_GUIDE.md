# Android Signing Guide

Android 릴리즈 서명 절차는 [`docs/android-signing.md`](docs/android-signing.md)를
참고하세요.

이 파일에는 keystore 비밀번호, key 비밀번호, API 키 등 실제 비밀값을 기록하지
않습니다. 비밀값은 로컬 `android/key.properties` 또는 CI Secret에서만 관리합니다.
