import 'package:flutter/material.dart';
import '../../services/api_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({Key? key}) : super(key: key);

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final ApiService _apiService = ApiService();
  bool _isLoading = true;
  Map<String, bool> _settings = {
    'new_estimate': true,
    'estimate_accepted': true,
    'estimate_rejected': true,
    'order_status_changed': true,
    'order_completed': true,
    'review_request': true,
    'chat_message': true,
  };

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await _apiService.getNotificationSettings();
      setState(() {
        _settings = Map<String, bool>.from(settings);
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정을 불러오는데 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }

  Future<void> _updateSetting(String key, bool value) async {
    setState(() => _settings[key] = value);
    try {
      await _apiService.updateNotificationSettings(_settings);
    } catch (e) {
      if (mounted) {
        setState(() => _settings[key] = !value); // Revert on error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('설정 저장에 실패했습니다: ${e.toString()}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림 설정'),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _buildSection(
                  '견적 알림',
                  [
                    _buildSwitchTile(
                      '새로운 견적',
                      '새로운 견적이 도착하면 알림을 받습니다',
                      'new_estimate',
                    ),
                    _buildSwitchTile(
                      '견적 수락',
                      '견적이 수락되면 알림을 받습니다',
                      'estimate_accepted',
                    ),
                    _buildSwitchTile(
                      '견적 거절',
                      '견적이 거절되면 알림을 받습니다',
                      'estimate_rejected',
                    ),
                  ],
                ),
                _buildSection(
                  '작업 알림',
                  [
                    _buildSwitchTile(
                      '작업 상태 변경',
                      '작업 상태가 변경되면 알림을 받습니다',
                      'order_status_changed',
                    ),
                    _buildSwitchTile(
                      '작업 완료',
                      '작업이 완료되면 알림을 받습니다',
                      'order_completed',
                    ),
                    _buildSwitchTile(
                      '후기/평점 작성 안내',
                      '내 오더가 완료되면 후기·평점 작성 안내 알림을 받습니다',
                      'review_request',
                    ),
                  ],
                ),
                _buildSection(
                  '기타 알림',
                  [
                    _buildSwitchTile(
                      '채팅 메시지',
                      '새로운 채팅 메시지가 오면 알림을 받습니다',
                      'chat_message',
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, String settingKey) {
    return SwitchListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      value: _settings[settingKey] ?? false,
      onChanged: (bool value) => _updateSetting(settingKey, value),
    );
  }
} 