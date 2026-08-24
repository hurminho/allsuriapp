import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ApiService extends ChangeNotifier {
  // API 기본 URL (dart-define로 덮어쓰기 가능)
  static const String baseUrl = String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'https://api.allsuri.app/api',
      );

  ApiService() {
    // 앱 시작 시 현재 API_BASE_URL 값을 로그로 출력
    // (release 빌드에선 로그가 보이지 않을 수 있으니 debug로 실행 권장)
    // ignore: avoid_print
    print('API_BASE_URL -> $baseUrl');
  }

  static String? _bearerToken;
  static void setBearerToken(String? token) {
    _bearerToken = token;
  }
  static String? get currentBearerToken => _bearerToken;
  Map<String, String> _headers() => {
        'Content-Type': 'application/json',
        if (_bearerToken != null && _bearerToken!.isNotEmpty) 'Authorization': 'Bearer $_bearerToken',
      };

  // GET 요청
  Future<Map<String, dynamic>> get(String endpoint) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl$endpoint'),
        headers: _headers(),
      );
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
          'message': 'Success',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
    } catch (e) {
      print('GET request error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // POST 요청
  Future<Map<String, dynamic>> post(String endpoint, Map<String, dynamic> data) async {
    try {
      final uri = Uri.parse('$baseUrl$endpoint');
      print('[API][POST] $uri body=${data.keys.toList()}');
      final response = await http.post(
        uri,
        headers: _headers(),
        body: json.encode(data),
      );
      print('[API][POST] ${response.statusCode} ${response.reasonPhrase}');
      print('[API][POST] Response body: ${response.body}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        print('[API][POST] Decoded response: $responseData');
        final nestedSuccess = responseData is Map && responseData['success'] == false
            ? false
            : true;
        return {
          'success': nestedSuccess,
          'data': responseData,
          'message': responseData is Map
              ? (responseData['message']?.toString() ?? 'Created successfully')
              : 'Created successfully',
        };
      } else {
        dynamic decoded;
        try {
          decoded = json.decode(response.body);
        } catch (_) {}
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          'message': decoded is Map ? decoded['message']?.toString() : null,
          'data': decoded,
        };
      }
    } catch (e) {
      print('POST request error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // PUT 요청
  Future<Map<String, dynamic>> put(String endpoint, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.parse('$baseUrl$endpoint'),
        headers: _headers(),
        body: json.encode(data),
      );
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(response.body),
          'message': 'Updated successfully',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        };
      }
    } catch (e) {
      print('PUT request error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // DELETE 요청
  Future<Map<String, dynamic>> delete(String endpoint) async {
    try {
      final response = await http.delete(
        Uri.parse('$baseUrl$endpoint'),
        headers: _headers(),
      );
      
      dynamic decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = json.decode(response.body);
        } catch (_) {}
      }
      final bodyMessage =
          decoded is Map ? decoded['message']?.toString() : null;

      if (response.statusCode == 200 || response.statusCode == 204) {
        return {
          'success': decoded is Map && decoded['success'] == false
              ? false
              : true,
          'data': decoded,
          'message': bodyMessage ?? 'Deleted successfully',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
          'message': bodyMessage,
          'data': decoded,
        };
      }
    } catch (e) {
      print('DELETE request error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // 파일 업로드
  Future<Map<String, dynamic>> uploadFile(String endpoint, File file) async {
    try {
      final request = http.MultipartRequest('POST', Uri.parse('$baseUrl$endpoint'));
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        return {
          'success': true,
          'data': json.decode(responseBody),
          'message': 'File uploaded successfully',
        };
      } else {
        return {
          'success': false,
          'error': 'HTTP ${response.statusCode}: Upload failed',
        };
      }
    } catch (e) {
      print('File upload error: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  // 에러 처리
  void handleError(dynamic error) {
    if (kDebugMode) {
      print('API Error: $error');
    }
  }

  // 알림 설정 관련 메서드들
  Future<Map<String, dynamic>> getNotificationSettings() async {
    return await get('/notifications/settings');
  }

  Future<void> updateNotificationSettings(Map<String, bool> settings) async {
    await put('/notifications/settings', settings);
  }

  Future<void> sendNotification(String userId, String title, String body) async {
    await post('/notifications/send', {
      'userId': userId,
      'title': title,
      'body': body,
    });
  }

  // 채팅 관련 메서드들
  Future<List<Map<String, dynamic>>> getChatRooms() async {
    final response = await get('/chat/rooms');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  // 광고 목록 조회 (활성 광고)
  Future<List<Map<String, dynamic>>> getActiveAds() async {
    final response = await get('/ads');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  Future<void> trackAdImpression(String adId) async {
    try {
      await post('/ads/$adId/impression', {});
    } catch (_) {}
  }

  Future<void> trackAdClick(String adId) async {
    try {
      await post('/ads/$adId/click', {});
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> getMessages(String chatRoomId) async {
    final response = await get('/chat/rooms/$chatRoomId/messages');
    if (response['success']) {
      return List<Map<String, dynamic>>.from(response['data'] ?? []);
    }
    return [];
  }

  Future<void> sendMessage(String chatRoomId, String message) async {
    await post('/chat/rooms/$chatRoomId/messages', {
      'message': message,
    });
  }

  // 채팅방 읽음 처리
  Future<void> markChatRead(String chatRoomId) async {
    await post('/chat/rooms/$chatRoomId/read', {});
  }
}
