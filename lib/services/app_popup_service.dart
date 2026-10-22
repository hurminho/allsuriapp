import 'package:supabase_flutter/supabase_flutter.dart';

import '../utils/app_logger.dart';

/// 관리자 페이지에서 등록한 앱 팝업(app_popups) 하나.
/// 대상(전체·공종·지정 사업자)과 빈도는 DB 함수 allsuri_my_app_popup() 이 골라 줍니다.
class AppPopup {
  final String id;
  final String title;
  final String body;
  final String? imageUrl;
  final String? buttonLabel;
  final String? buttonUrl;

  /// once(한 번만) | daily(하루 한 번) | always(열 때마다)
  final String frequency;

  const AppPopup({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl,
    this.buttonLabel,
    this.buttonUrl,
    this.frequency = 'once',
  });

  static String? _text(dynamic v) {
    final t = v?.toString().trim() ?? '';
    return t.isEmpty ? null : t;
  }

  factory AppPopup.fromRow(Map<String, dynamic> row) => AppPopup(
        id: row['id'].toString(),
        title: _text(row['title']) ?? '',
        body: _text(row['body']) ?? '',
        imageUrl: _text(row['image_url']),
        buttonLabel: _text(row['button_label']),
        buttonUrl: _text(row['button_url']),
        frequency: _text(row['frequency']) ?? 'once',
      );

  /// 한 번만 뜨는 팝업은 '다시 보지 않기'가 필요 없습니다.
  bool get canHide => frequency != 'once';
}

class AppPopupService {
  static const _tag = 'AppPopup';
  final SupabaseClient _sb;

  AppPopupService([SupabaseClient? client]) : _sb = client ?? Supabase.instance.client;

  /// 지금 띄울 팝업. 없거나 SQL 실행 전이면 null (앱 동작에 영향 없음).
  Future<AppPopup?> next() async {
    try {
      final rows = await _sb.rpc('allsuri_my_app_popup');
      if (rows is! List || rows.isEmpty) return null;
      final popup = AppPopup.fromRow(Map<String, dynamic>.from(rows.first as Map));
      return popup.title.isEmpty || popup.body.isEmpty ? null : popup;
    } catch (e) {
      AppLog.warn(_tag, '팝업 조회 실패(무시): $e');
      return null;
    }
  }

  /// seen(봤음) | click(버튼 누름) | hide(다시 보지 않기)
  Future<void> record(String popupId, String event) async {
    try {
      await _sb.rpc('allsuri_app_popup_event', params: {'p_popup_id': popupId, 'p_event': event});
    } catch (e) {
      AppLog.warn(_tag, '팝업 기록 실패(무시): $e');
    }
  }
}
