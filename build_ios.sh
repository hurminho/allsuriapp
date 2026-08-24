#!/bin/bash

# 올수리 iOS IPA 빌드 스크립트
# 사용법: ./build_ios.sh [dev|prod] [build_number]
#
# 사전 요구사항:
#   - Xcode 설치 및 로그인
#   - Apple Developer Program 가입
#   - Xcode에서 Signing 설정 완료

ENV=${1:-prod}
BUILD_NUMBER=${2:-}

echo ""
echo "📱 올수리 iOS 빌드 시작"
echo "───────────────────────────────"

# Flutter pub get
echo "📦 패키지 업데이트 중..."
flutter pub get

if [ "$ENV" == "dev" ]; then
    echo "🔨 개발 환경 iOS 빌드 중..."
    DEFINES_FILE="dart_defines.dev.json"
elif [ "$ENV" == "prod" ]; then
    echo "🚀 프로덕션 환경 iOS 빌드 중..."
    DEFINES_FILE="dart_defines.json"
else
    echo "❌ 잘못된 환경: $ENV"
    echo "사용법: ./build_ios.sh [dev|prod] [build_number]"
    exit 1
fi

# 빌드 번호 옵션
BUILD_NUM_OPT=""
if [ -n "$BUILD_NUMBER" ]; then
    BUILD_NUM_OPT="--build-number=$BUILD_NUMBER"
    echo "🔢 빌드 번호: $BUILD_NUMBER"
fi

echo ""
echo "⚙️  Flutter iOS 빌드 실행 중..."
echo "   (시간이 다소 걸립니다 - 약 5~10분)"
echo ""

flutter build ipa \
    --release \
    --dart-define-from-file=$DEFINES_FILE \
    --export-method=app-store \
    $BUILD_NUM_OPT

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ iOS IPA 빌드 완료!"
    echo "📁 파일 위치: build/ios/ipa/*.ipa"
    echo ""
    echo "📤 다음 단계:"
    echo "   1. Xcode > Organizer 를 열거나"
    echo "   2. Transporter 앱으로 .ipa 파일을 App Store Connect에 업로드"
    echo ""
    ls -lh build/ios/ipa/*.ipa 2>/dev/null || echo "   (ipa 파일 위치 확인 필요)"
else
    echo ""
    echo "❌ 빌드 실패!"
    echo ""
    echo "💡 일반적인 해결 방법:"
    echo "   1. Xcode에서 Signing 설정 확인"
    echo "   2. Apple Developer 계정 연결 확인"
    echo "   3. Bundle ID 변경 여부 확인 (com.example → 실제 ID)"
    exit 1
fi
