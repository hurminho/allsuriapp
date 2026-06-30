import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

class MediaService {
  final ImagePicker _picker = ImagePicker();
  
  // Supabase 클라이언트를 getter로 변경하여 항상 최신 세션 사용
  SupabaseClient get _sb => Supabase.instance.client;

  static const int maxBytes = 5 * 1024 * 1024; // 5MB
  static const List<String> allowedExt = [
    '.jpg',
    '.jpeg',
    '.png',
    '.heic',
    '.webp',
  ];

  Future<File?> pickImageFromCamera() async {
    final x = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (x == null) return null;
    final file = File(x.path);
    return _validate(file) ? file : null;
  }

  Future<File?> pickImageFromGallery() async {
    final x = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (x == null) return null;
    final file = File(x.path);
    return _validate(file) ? file : null;
  }

  /// 갤러리에서 여러 장의 이미지를 한 번에 선택합니다.
  /// image_picker 1.x 의 pickMultiImage 사용.
  Future<List<File>?> pickMultipleImages() async {
    final picked = await _picker.pickMultiImage(imageQuality: 85);
    if (picked.isEmpty) return null;

    final List<File> valid = [];
    for (final x in picked) {
      final file = File(x.path);
      if (_validate(file)) {
        valid.add(file);
      }
    }

    return valid.isEmpty ? null : valid;
  }

  bool _validate(File file) {
    try {
      final size = file.lengthSync();
      if (size > maxBytes) {
        debugPrint('파일 용량 초과: ${size}B');
        return false;
      }
      final ext = p.extension(file.path).toLowerCase();
      // iOS/Android 임시 경로에 확장자가 없는 경우가 있어 용량만 통과시 허용
      if (ext.isNotEmpty && !allowedExt.contains(ext)) {
        debugPrint('허용되지 않은 확장자: $ext');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('파일 검증 실패: $e');
      return false;
    }
  }

  String _contentTypeForExt(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  /// 동영상 선택 (갤러리에서)
  Future<File?> pickVideoFromGallery() async {
    final video = await _picker.pickVideo(source: ImageSource.gallery);
    if (video == null) return null;
    final file = File(video.path);
    return _validateVideo(file) ? file : null;
  }

  /// 동영상 유효성 검사
  bool _validateVideo(File file) {
    try {
      final size = file.lengthSync();
      // 동영상은 최대 50MB로 제한
      const maxVideoBytes = 50 * 1024 * 1024;
      if (size > maxVideoBytes) {
        debugPrint('동영상 용량 초과: ${size}B (최대 50MB)');
        return false;
      }
      final ext = p.extension(file.path).toLowerCase();
      const allowedVideoExt = ['.mp4', '.mov', '.avi', '.mkv'];
      if (!allowedVideoExt.contains(ext)) {
        debugPrint('허용되지 않은 동영상 확장자: $ext');
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('동영상 검증 실패: $e');
      return false;
    }
  }

  Future<String?> uploadProfileImage({required String userId, required File file}) async {
    try {
      final fileName = 'avatar_${userId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      final path = 'profiles/$userId/$fileName';
      await _sb.storage.from('profiles').upload(
        path, 
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      final publicUrl = _sb.storage.from('profiles').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('프로필 업로드 실패: $e');
      return null;
    }
  }

  Future<String?> uploadMessageImage({required String roomId, required String userId, required File file}) async {
    try {
      // 인증 상태 확인
      final session = _sb.auth.currentSession;
      debugPrint('🔐 [uploadMessageImage] 인증 상태: ${session != null ? "인증됨" : "인증 안됨"}');
      if (session != null) {
        debugPrint('   User ID: ${session.user.id}');
        debugPrint('   Access Token: ${session.accessToken.substring(0, 20)}...');
      }
      
      final fileName = 'msg_${userId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      final path = 'attachments_messages/$roomId/$fileName';
      debugPrint('📤 [uploadMessageImage] 업로드 시작: $path');
      
      await _sb.storage.from('attachments_messages').upload(
        path, 
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      
      final publicUrl = _sb.storage.from('attachments_messages').getPublicUrl(path);
      debugPrint('✅ [uploadMessageImage] 업로드 성공: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ [uploadMessageImage] 메시지 이미지 업로드 실패: $e');
      debugPrint('   에러 타입: ${e.runtimeType}');
      return null;
    }
  }

  /// 채팅 동영상 업로드
  Future<String?> uploadMessageVideo({required String roomId, required String userId, required File file}) async {
    try {
      final fileName = 'video_${userId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      final path = 'attachments_messages/$roomId/$fileName';
      debugPrint('🎬 동영상 업로드 시작: $path');
      await _sb.storage.from('attachments_messages').upload(
        path, 
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      final publicUrl = _sb.storage.from('attachments_messages').getPublicUrl(path);
      debugPrint('✅ 동영상 업로드 완료: $publicUrl');
      return publicUrl;
    } catch (e) {
      debugPrint('❌ 메시지 동영상 업로드 실패: $e');
      return null;
    }
  }

  Future<String?> uploadAiImage({required File file}) async {
    try {
      final fileName = 'ai_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      final path = 'ai/$fileName';
      await _sb.storage.from('attachments_messages').upload(
        path, 
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      final publicUrl = _sb.storage.from('attachments_messages').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      debugPrint('AI 이미지 업로드 실패: $e');
      return null;
    }
  }

  /// 견적/공사 이미지 업로드
  /// 실패 시 null 대신 예외를 throw하여 호출부에서 실제 원인을 표시할 수 있게 합니다.
  Future<String> uploadEstimateImage({required File file}) async {
    debugPrint('🔍 [uploadEstimateImage] 시작');
    debugPrint('   파일: ${file.path}');
    debugPrint('   파일 크기: ${file.lengthSync()} bytes');

    final session = _sb.auth.currentSession;
    debugPrint('🔐 인증 상태: ${session != null ? "인증됨 (${session.user.id})" : "비인증(anon)"}');

    var ext = p.extension(file.path).toLowerCase();
    if (ext.isEmpty || !allowedExt.contains(ext)) {
      ext = '.jpg';
    }
    final fileName =
        'job_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}$ext';
    final storagePath = fileName;
    debugPrint('   경로: attachments_estimates/$storagePath');

    final fileOptions = FileOptions(
      cacheControl: '3600',
      upsert: true, // 중복 파일명 오류 방지
      contentType: _contentTypeForExt(ext),
    );

    debugPrint('   → Supabase 업로드 중...');
    try {
      await _sb.storage
          .from('attachments_estimates')
          .upload(storagePath, file, fileOptions: fileOptions);
    } catch (uploadErr) {
      debugPrint('⚠️ upload() 실패, uploadBinary() 재시도: $uploadErr');
      final Uint8List bytes = await file.readAsBytes();
      await _sb.storage
          .from('attachments_estimates')
          .uploadBinary(storagePath, bytes, fileOptions: fileOptions);
    }

    final publicUrl =
        _sb.storage.from('attachments_estimates').getPublicUrl(storagePath);
    debugPrint('✅ [uploadEstimateImage] 완료: $publicUrl');
    return publicUrl;
  }

  Future<String?> uploadAdImage(File file) async {
    try {
      debugPrint('🔍 [uploadAdImage] 시작');
      debugPrint('   파일: ${file.path}');
      debugPrint('   파일 크기: ${file.lengthSync()} bytes');
      
      final fileName = 'ad_${DateTime.now().millisecondsSinceEpoch}${p.extension(file.path)}';
      debugPrint('   생성된 파일명: $fileName');
      
      final path = 'ads/$fileName';
      debugPrint('   경로: $path');
      debugPrint('   버킷: public');
      
      debugPrint('   → Supabase에 업로드 중...');
      await _sb.storage.from('public').upload(
        path, 
        file,
        fileOptions: const FileOptions(
          cacheControl: '3600',
          upsert: false,
        ),
      );
      debugPrint('   ✅ 업로드 완료');
      
      debugPrint('   → Public URL 생성 중...');
      final publicUrl = _sb.storage.from('public').getPublicUrl(path);
      debugPrint('   ✅ Public URL: $publicUrl');
      
      return publicUrl;
    } catch (e) {
      debugPrint('❌ [uploadAdImage] 실패: $e');
      return null;
    }
  }
}
