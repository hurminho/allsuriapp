import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:allsuriapp/app_navigator_key.dart';
import 'package:allsuriapp/screens/business/order_marketplace_screen.dart';
import 'package:allsuriapp/screens/web/personal_order_link_public_page.dart';
import 'package:allsuriapp/utils/personal_order_link_nav.dart';

bool _appDeepLinksInitialized = false;

/// 스플래시에서 홈으로 전환한 뒤 한 번만 호출합니다.
/// (초기화를 스플래시와 동시에 하면 [Splash, OrderMarketplace] 스택이 되어 뒤로가기 UX가 깨질 수 있음)
void initAppDeepLinksAfterSplash() {
  if (_appDeepLinksInitialized) return;
  _appDeepLinksInitialized = true;

  final appLinks = AppLinks();

  appLinks.uriLinkStream.listen((Uri uri) {
    debugPrint('🔗 [DeepLink] 수신: $uri');
    _handleDeepLink(uri);
  }, onError: (Object err) {
    debugPrint('❌ [DeepLink] 에러: $err');
  });

  appLinks.getInitialLink().then((Uri? uri) {
    if (uri != null) {
      debugPrint('🔗 [DeepLink] 초기 링크: $uri');
      _handleDeepLink(uri);
    }
  });
}

void _handleDeepLink(Uri uri) {
  if (uri.scheme.startsWith('kakao')) {
    debugPrint('🔗 [DeepLink] 카카오 리다이렉트 무시 (Kakao SDK 처리)');
    return;
  }

  debugPrint('🔗 [DeepLink] 처리 시작: ${uri.toString()}');

  final personalSlug = personalOrderLinkSlugFromUri(uri);
  if (personalSlug != null) {
    debugPrint('✅ [DeepLink] 개인 오더 링크: $personalSlug');
    Future.delayed(const Duration(milliseconds: 400), () {
      final navigator = navigatorKey.currentState;
      if (navigator == null) return;
      navigator.push(
        MaterialPageRoute(
          builder: (_) => PersonalOrderLinkPublicPage(slug: personalSlug),
        ),
      );
    });
    return;
  }

  if ((uri.scheme == 'allsuri' || uri.scheme == 'https') &&
      (uri.host == 'order' || uri.path.startsWith('/order'))) {
    String? orderId;
    if (uri.host == 'order') {
      orderId = uri.pathSegments.isNotEmpty ? uri.pathSegments[0] : null;
    } else {
      final segments = uri.pathSegments;
      orderId = segments.length > 1 ? segments[1] : null;
    }

    if (orderId != null) {
      debugPrint('✅ [DeepLink] 오더 ID: $orderId');
      Future.delayed(const Duration(milliseconds: 400), () {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => const OrderMarketplaceScreen(),
          ),
        );
      });
    }
  }
}
