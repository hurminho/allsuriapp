import 'package:flutter/material.dart';

import '../screens/business/personal_order_link_management_screen.dart';
import '../screens/web/personal_order_link_public_page.dart';

/// 사업자 마이페이지·홈에서 개인 오더 링크 관리 화면을 엽니다.
void openPersonalOrderLinkManagement(BuildContext context) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => const PersonalOrderLinkManagementScreen(),
    ),
  );
}

/// 고객용 공개 영업 페이지를 앱 안에서 엽니다.
void openPersonalOrderLinkPublicPage(BuildContext context, String slug) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => PersonalOrderLinkPublicPage(slug: slug),
    ),
  );
}

/// `https://host/allsuri/{slug}` 또는 `allsuri://allsuri/{slug}` 에서 slug를 추출합니다.
String? personalOrderLinkSlugFromUri(Uri uri) {
  final segments =
      uri.pathSegments.where((segment) => segment.isNotEmpty).toList();

  if (segments.length >= 2 && segments.first == 'allsuri') {
    final slug = segments[1].trim();
    return slug.isEmpty ? null : slug;
  }

  if (uri.host == 'allsuri' && segments.isNotEmpty) {
    final slug = segments.first.trim();
    return slug.isEmpty ? null : slug;
  }

  return null;
}
