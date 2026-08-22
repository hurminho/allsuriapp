import 'package:flutter/material.dart';
import '../services/announcement_service.dart';

/// 앱 상단 공지 배너 위젯
/// - 관리자 페이지에서 등록한 공지를 실시간 반영
/// - 닫기 버튼으로 개별 공지 숨기기 가능
class AnnouncementBanner extends StatefulWidget {
  const AnnouncementBanner({super.key});

  @override
  State<AnnouncementBanner> createState() => _AnnouncementBannerState();
}

class _AnnouncementBannerState extends State<AnnouncementBanner> {
  List<Announcement> _announcements = [];
  final Set<String> _dismissed = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await AnnouncementService().getActiveAnnouncements();
    if (mounted) {
      setState(() {
        _announcements = list;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();

    final visible = _announcements
        .where((a) => !_dismissed.contains(a.id))
        .toList();

    if (visible.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: visible
          .map((a) => _AnnouncementItem(
                announcement: a,
                onDismiss: () => setState(() => _dismissed.add(a.id)),
              ))
          .toList(),
    );
  }
}

class _AnnouncementItem extends StatelessWidget {
  final Announcement announcement;
  final VoidCallback onDismiss;

  const _AnnouncementItem({
    required this.announcement,
    required this.onDismiss,
  });

  Color _parseColor(String hex) {
    try {
      final h = hex.replaceAll('#', '');
      final full = h.length == 6 ? 'FF$h' : h;
      return Color(int.parse(full, radix: 16));
    } catch (_) {
      return const Color(0xFF0B2545);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _parseColor(announcement.bgColor);
    final tc = _parseColor(announcement.textColor);

    return Container(
      width: double.infinity,
      color: bg,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              announcement.message,
              style: TextStyle(
                color: tc,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
          if (announcement.isDismissible)
            GestureDetector(
              onTap: onDismiss,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(Icons.close, color: tc.withValues(alpha: 0.8), size: 18),
              ),
            ),
        ],
      ),
    );
  }
}
