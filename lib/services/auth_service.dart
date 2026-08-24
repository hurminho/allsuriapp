import 'dart:async' show TimeoutException;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
// Supabase Auth 전환: Firebase/GoogleSignIn 제거
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:kakao_flutter_sdk_user/kakao_flutter_sdk_user.dart' as kakao;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'api_service.dart';
import 'fcm_service.dart';
import 'notification_service.dart';
import '../config.dart';
import '../supabase_config.dart';
import '../models/user.dart' as app_models;

class AuthService extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;
  
  app_models.User? _currentUser;
  bool _isLoading = false;
  String? _supabaseAccessToken; // Supabase 세션 설정 실패 시 FCM 푸시용 fallback

  app_models.User? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null;
  bool get isLoading => _isLoading;
  /// FCM 푸시 전송에 사용할 access token (세션이 없을 때 사용)
  String? get accessToken => _sb.auth.currentSession?.accessToken ?? _supabaseAccessToken;

  bool _isLoadingFromKakao = false; // 카카오 로그인 중 onAuthStateChange 중복 방지
  bool _isLoadingFromApple = false; // Sign in with Apple 중 onAuthStateChange 중복 방지
  bool _isLoadingManually = false;  // 수동 loadUserData 호출 중 중복 방지

  AuthService() {
    _sb.auth.onAuthStateChange.listen((event) async {
      final session = event.session;
      final supaUserId = session?.user.id;
      if (supaUserId != null) {
        // 카카오 로그인 또는 수동 로드 중 중복 호출 방지
        if (_isLoadingFromKakao || _isLoadingFromApple || _isLoadingManually) {
          debugPrint('ℹ️ [onAuthStateChange] 수동 로드 중 - 중복 _loadUserData 스킵');
          return;
        }
        await _loadUserData(supaUserId);
      } else {
        _currentUser = null;
      }
      notifyListeners();
    });
  }

  Future<void> _loadUserData(String uid) async {
    try {
      print('=== _loadUserData 시작 ===');
      print('UID: $uid');
      
      final row = await _sb.from('users').select().eq('id', uid).maybeSingle();
      print('데이터베이스 결과: $row');
      
      // Google 메타데이터 동기화 (full_name)
      final supaUser = _sb.auth.currentUser;
      final Map<String, dynamic>? meta = (supaUser?.userMetadata is Map<String, dynamic>)
          ? (supaUser!.userMetadata as Map<String, dynamic>)
          : null;
      final String? fullName = meta != null ? (meta['full_name'] as String?) : null;
      print('Google 메타데이터 full_name: $fullName');
      
      if (row != null) {
        // 필요 시 이름 갱신
        if (fullName != null && fullName.isNotEmpty && row['name'] != fullName) {
          await _sb.from('users').update({'name': fullName}).eq('id', uid);
          row['name'] = fullName;
        }
        
        // 사용자 역할이 설정되어 있는지 확인
        final userRole = row['role'] as String?;
        print('데이터베이스에서 읽은 역할: $userRole');
        print('🔍 DB에서 가져온 사업자 정보:');
        print('   - businessstatus: ${row['businessstatus']}');
        print('   - businessname: ${row['businessname']}');
        print('   - businessnumber: ${row['businessnumber']}');
        print('   - business_verify_status: ${row['business_verify_status']}');
        print('   - business_grace_until: ${row['business_grace_until']}');
        
        _currentUser = app_models.User.fromMap(Map<String, dynamic>.from(row));
        print('사용자 로드됨: role=$userRole');
        print('🔍 User 객체 생성 후:');
        print('   - businessStatus: ${_currentUser?.businessStatus}');
        print('   - businessName: ${_currentUser?.businessName}');
        print('   - businessNumber: ${_currentUser?.businessNumber}');
        print('   - businessVerifyStatus: ${_currentUser?.businessVerifyStatus}');
        
        // FCM 토큰 저장 (실패해도 로그인은 성공)
        try {
          await FCMService().saveFCMToken(uid);
        } catch (e) {
          print('⚠️ FCM 토큰 저장 실패 (무시됨): $e');
        }

        // 사업자 진위확인 안내 알림은 사용자 요청에 따라 비활성화.
        // 사업자번호 등록은 프로필에서 자율적으로 진행.

        return;
      }
      
      // 새 사용자인 경우 기본 역할 설정
      final fallbackUser = app_models.User(
        id: uid,
        name: fullName ?? '사용자',
        email: _sb.auth.currentUser?.email ?? '',
        role: 'customer', // 기본 역할을 customer로 설정
        phoneNumber: null,
        createdAt: DateTime.now(),
      );
      await _sb.from('users').insert(fallbackUser.toMap());
      _currentUser = fallbackUser;
      print('새 사용자 생성됨, 기본 역할: customer');
      
      // FCM 토큰 저장 (실패해도 로그인은 성공)
      try {
        await FCMService().saveFCMToken(uid);
      } catch (e) {
        print('⚠️ FCM 토큰 저장 실패 (무시됨): $e');
      }
    } catch (e) {
      print('사용자 데이터 로드/생성 오류: $e');
      _currentUser = null;
    }
  }

  Future<void> signInAnonymously() async {
    // Supabase Auth는 익명 로그인을 지원하지 않습니다.
    throw UnsupportedError('Anonymous sign-in is not supported with Supabase Auth.');
  }

  Future<void> signInWithGoogle({String? redirectUrl}) async {
    throw UnsupportedError('Google sign-in is disabled. Use signInWithKakao instead.');
  }

  /// App Store Guideline 4.8: Sign in with Apple (iOS/iPadOS 전용, Supabase Apple 프로바이더 필요)
  Future<bool> signInWithApple() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      debugPrint('⚠️ [signInWithApple] iOS에서만 지원됩니다.');
      return false;
    }
    _isLoading = true;
    _isLoadingFromApple = true;
    notifyListeners();
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null || idToken.isEmpty) {
        debugPrint('❌ [signInWithApple] identityToken 없음');
        return false;
      }

      await _sb.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      final uid = _sb.auth.currentUser?.id;
      if (uid != null) {
        await _loadUserData(uid);
        return true;
      }
      return false;
    } catch (e, st) {
      debugPrint('❌ [signInWithApple] $e\n$st');
      return false;
    } finally {
      _isLoading = false;
      _isLoadingFromApple = false;
      notifyListeners();
    }
  }

  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(length, (_) => charset[random.nextInt(charset.length)]).join();
  }

  Future<bool> signInWithKakao() async {
    _isLoading = true;
    _isLoadingFromKakao = true; // onAuthStateChange 중복 방지 시작
    notifyListeners();
    try {
      // Kakao SDK는 main.dart에서 이미 초기화됨
      final nativeAppKey = AppConfig.kakaoNativeAppKey;
      if (nativeAppKey.isEmpty) {
        if (const bool.fromEnvironment('ALLOW_TEST_KAKAO', defaultValue: false)) {
          final api = ApiService();
          final resp = await api.post('/auth/kakao/login', { 'access_token': 'TEST_BYPASS' });
          if (resp['success'] == true) {
            final data = resp['data'] as Map<String, dynamic>;
            final backendToken = data['token'] as String?;
            if (backendToken != null && backendToken.isNotEmpty) {
              ApiService.setBearerToken(backendToken);
              final user = data['user'] as Map<String, dynamic>?;
              if (user != null) {
                final uid = user['id'] as String;
                await _loadUserData(uid);
              }
              return true;
            }
          }
        }
        throw StateError('카카오 앱 키가 없어 로그인할 수 없습니다.');
      }

      // Kakao 로그인: iOS는 WebAuthenticationSession 이슈로 웹뷰 우선, Android는 톡 우선
      kakao.OAuthToken token;
      final isIOS = !kIsWeb && Platform.isIOS;
      if (isIOS) {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        } catch (e) {
          final msg = e.toString().toLowerCase();
          if (msg.contains('cancel')) rethrow;
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        }
      } else {
        try {
          token = await kakao.UserApi.instance.loginWithKakaoTalk();
        } catch (_) {
          token = await kakao.UserApi.instance.loginWithKakaoAccount();
        }
      }

      // 백엔드로 토큰 교환 (타임아웃 설정 + 재시도)
      final api = ApiService();
      print('🔍 [signInWithKakao] 백엔드로 카카오 토큰 전송 중...');
      
      Map<String, dynamic>? resp;
      int retryCount = 0;
      const maxRetries = 2;
      
      while (retryCount <= maxRetries) {
        try {
          resp = await api.post('/auth/kakao/login', {
            'access_token': token.accessToken,
          }).timeout(
            const Duration(seconds: 15), // 5초 → 15초로 증가
            onTimeout: () {
              print('⚠️ [signInWithKakao] 타임아웃 발생 (시도 ${retryCount + 1}/${maxRetries + 1})');
              return {'success': false, 'error': 'timeout'};
            },
          );
          
          print('🔍 [signInWithKakao] 백엔드 응답 (시도 ${retryCount + 1}): $resp');
          
          // 성공하면 루프 탈출
          if (resp['success'] == true) {
            print('✅ [signInWithKakao] 백엔드 응답 성공!');
            break;
          }
          
          // 타임아웃이면 재시도
          if (resp['error'] == 'timeout' && retryCount < maxRetries) {
            retryCount++;
            print('🔄 [signInWithKakao] 재시도 중... (${retryCount}/${maxRetries})');
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          
          // 다른 에러면 중단
          break;
        } catch (e) {
          print('❌ [signInWithKakao] API 호출 에러: $e');
          if (retryCount < maxRetries) {
            retryCount++;
            print('🔄 [signInWithKakao] 재시도 중... (${retryCount}/${maxRetries})');
            await Future.delayed(const Duration(milliseconds: 500));
            continue;
          }
          rethrow;
        }
      }
      
      if (resp == null) {
        throw Exception('백엔드 응답 없음');
      }
      
      print('🔍 [signInWithKakao] 최종 resp[\'success\']: ${resp['success']}');
      
      if (resp['success'] == true) {
        // ApiService.post()가 응답을 한 번 감싸므로, resp['data']가 실제 백엔드 응답
        final backendResponse = resp['data'] as Map<String, dynamic>;
        print('🔍 [signInWithKakao] backendResponse: $backendResponse');
        
        // 백엔드 응답에서 실제 데이터 추출
        final actualData = backendResponse['data'] as Map<String, dynamic>?;
        print('🔍 [signInWithKakao] actualData: $actualData');
        
        if (actualData != null) {
          // Supabase 토큰을 JWT 토큰으로 사용
          final supabaseAccessToken = actualData['supabase_access_token'] as String?;
          final supabaseRefreshToken = actualData['supabase_refresh_token'] as String?;
          
          print('🔍 [signInWithKakao] supabase_access_token: ${supabaseAccessToken != null ? "존재" : "null"}');
          print('🔍 [signInWithKakao] supabase_refresh_token: ${supabaseRefreshToken != null ? "존재" : "null"}');
          
          if (supabaseAccessToken != null && supabaseAccessToken.isNotEmpty) {
            // Supabase Access Token을 Bearer Token으로 설정
            ApiService.setBearerToken(supabaseAccessToken);
            
            final user = actualData['user'] as Map<String, dynamic>?;
            print('🔍 [signInWithKakao] user: $user');
            
            if (user != null) {
              final uid = user['id'] as String;
              
              // Supabase 세션 설정 (FCM 푸시 발송에 필요)
              if (supabaseAccessToken != null && supabaseAccessToken.isNotEmpty) {
                try {
                  if (supabaseRefreshToken != null && supabaseRefreshToken.isNotEmpty) {
                    // access token + refresh token 모두 전달
                    await _sb.auth.setSession(supabaseRefreshToken);
                  } else {
                    await _sb.auth.setSession(supabaseAccessToken);
                  }
                  print('✅ [signInWithKakao] Supabase 세션 설정 성공');
                } catch (e) {
                  print('⚠️ [signInWithKakao] Supabase 세션 설정 실패: $e');
                  // 세션 설정 실패 시 access token을 직접 저장 (FCM 푸시용)
                  _supabaseAccessToken = supabaseAccessToken;
                }
              }
              
              // Supabase에서 전체 사용자 정보 로드 (사업자 정보 포함)
              print('🔍 [signInWithKakao] 백엔드 응답 받음, Supabase에서 전체 정보 로드 시작');
              print('   - UID: $uid');
              await _loadUserData(uid);
              print('🔍 [signInWithKakao] Supabase 로드 완료');
              print('   - Business Status: ${_currentUser?.businessStatus}');
              print('   - Business Name: ${_currentUser?.businessName}');
              
              // FCM 토큰 초기화 및 저장
              try {
                await NotificationService().initializeFCM(uid);
              } catch (e) {
                print('⚠️ [signInWithKakao] FCM 초기화 실패 (무시): $e');
              }
            }
            return true;
          }
        }
      } else if (const bool.fromEnvironment('ALLOW_TEST_KAKAO', defaultValue: false)) {
        // 서버 검증 실패 시 테스트 바이패스 세컨드 찬스
        final retry = await api.post('/auth/kakao/login', { 'access_token': 'TEST_BYPASS' });
        if (retry['success'] == true) {
          final data = retry['data'] as Map<String, dynamic>;
          final backendToken = data['token'] as String?;
          if (backendToken != null && backendToken.isNotEmpty) {
            ApiService.setBearerToken(backendToken);
            final user = data['user'] as Map<String, dynamic>?;
            if (user != null) {
              final uid = user['id'] as String;
              await _loadUserData(uid);
            }
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      print('Kakao 로그인 오류: $e');
      final msg = e.toString().toLowerCase();
      final canceled = msg.contains('cancel') || msg.contains('cancelled') || msg.contains('canceled');
      if (canceled) return false;
      if (const bool.fromEnvironment('ALLOW_TEST_KAKAO', defaultValue: false)) {
        try {
          final api = ApiService();
          final resp = await api.post('/auth/kakao/login', {
            'access_token': 'TEST_BYPASS',
          });
          if (resp['success'] == true) {
            final data = resp['data'] as Map<String, dynamic>;
            final backendToken = data['token'] as String?;
            if (backendToken != null && backendToken.isNotEmpty) {
              ApiService.setBearerToken(backendToken);
              final user = data['user'] as Map<String, dynamic>?;
              if (user != null) {
                final uid = user['id'] as String;
                await _loadUserData(uid);
              }
              return true;
            }
          }
        } catch (_) {}
      }
      rethrow;
    } finally {
      _isLoading = false;
      _isLoadingFromKakao = false; // onAuthStateChange 중복 방지 해제
      notifyListeners();
    }
  }

  Future<void> signInWithEmailAndPassword(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();
      final res = await _sb.auth.signInWithPassword(email: email, password: password);
      final userId = res.user?.id;
      if (userId != null) {
        await _loadUserData(userId);
      }
    } catch (e) {
      print('이메일 로그인 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signUpWithEmailAndPassword(String email, String password, {String name = '사용자'}) async {
    try {
      _isLoading = true;
      notifyListeners();
      final res = await _sb.auth.signUp(email: email, password: password);
      final userId = res.user?.id;
      if (userId != null) {
        final profile = app_models.User(
          id: userId,
          email: email,
          name: name,
          role: 'customer',
          phoneNumber: null,
          createdAt: DateTime.now(),
        );
        await _sb.from('users').upsert(profile.toMap());
        _currentUser = profile;
      }
    } catch (e) {
      print('회원가입 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // FCM 토큰 삭제 (실패해도 로그아웃은 계속)
      if (_currentUser != null) {
        try {
          await FCMService().deleteFCMToken(_currentUser!.id);
        } catch (e) {
          print('⚠️ FCM 토큰 삭제 실패 (무시됨): $e');
        }
      }
      
      await _sb.auth.signOut();
      _currentUser = null;
    } catch (e) {
      print('로그아웃 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 계정 영구 삭제 (App Store 5.1.1(v)). Supabase에 `delete_my_account` RPC 필요 — `database/delete_my_account.sql`.
  Future<void> deleteAccount() async {
    final uid = _currentUser?.id;
    if (uid == null) return;

    _isLoading = true;
    notifyListeners();
    try {
      try {
        await FCMService().deleteFCMToken(uid);
      } catch (_) {}

      await _sb.rpc('delete_my_account');
    } catch (e, st) {
      debugPrint('❌ [AuthService] deleteAccount: $e\n$st');
      rethrow;
    } finally {
      _currentUser = null;
      try {
        await _sb.auth.signOut();
      } catch (_) {}
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateUserProfile({String? name, String? phoneNumber}) async {
    if (_currentUser == null) return;
    
    try {
      _isLoading = true;
      notifyListeners();
      
      final updates = <String, dynamic>{
        if (name != null) 'name': name,
        if (phoneNumber != null) 'phoneNumber': phoneNumber,
      };
      if (updates.isNotEmpty) {
        await _sb.from('users').update(updates).eq('id', _currentUser!.id);
        _currentUser = _currentUser!.copyWith(
          name: name,
          phoneNumber: phoneNumber,
        );
      }
    } catch (e) {
      print('프로필 업데이트 오류: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateRole(String role) async {
    if (_currentUser == null) return;
    try {
      _isLoading = true;
      notifyListeners();
      
      // 현재 businessstatus 확인
      final currentBusinessStatus = _currentUser!.businessStatus;
      final shouldUpdateBusinessStatus = role == 'business' && 
          (currentBusinessStatus == null || currentBusinessStatus.isEmpty);
      
      // Supabase 테이블 컬럼명에 맞춤 (소문자)
      final update = {
        'role': role,
        // ⚠️ 이미 승인된 사용자의 businessstatus를 덮어쓰지 않도록 수정
        // businessstatus가 없거나 비어있을 때만 'pending'으로 설정
        if (shouldUpdateBusinessStatus) 'businessstatus': 'pending',
      };
      
      final supaReady = SupabaseConfig.url.isNotEmpty && SupabaseConfig.anonKey.isNotEmpty;
      if (supaReady) {
        final result = await _sb.from('users').update(update).eq('id', _currentUser!.id).select();
        print('✅ Supabase 역할 업데이트 성공: ${_currentUser!.id}, role=$role');
        print('   - 기존 businessstatus: $currentBusinessStatus');
        print('   - businessstatus 업데이트 여부: $shouldUpdateBusinessStatus');
        print('   - 업데이트된 데이터: $result');
      }
      
      // Always update local state so UI can transition immediately
      // businessstatus는 기존 값을 유지 (새로 설정하는 경우만 pending)
      _currentUser = _currentUser!.copyWith(
        role: role,
        businessStatus: shouldUpdateBusinessStatus ? 'pending' : currentBusinessStatus,
      );
      print('사용자 역할이 업데이트되었습니다(로컬 적용${supaReady ? '' : ' - Supabase 미설정'}): $role');
      print('   - 최종 businessStatus: ${_currentUser!.businessStatus}');
    } catch (e) {
      // 비정상 상황에서도 로컬 업데이트를 반영하여 화면 전환 보장
      final currentBusinessStatus = _currentUser!.businessStatus;
      final shouldUpdateBusinessStatus = role == 'business' && 
          (currentBusinessStatus == null || currentBusinessStatus.isEmpty);
      
      _currentUser = _currentUser!.copyWith(
        role: role,
        businessStatus: shouldUpdateBusinessStatus ? 'pending' : currentBusinessStatus,
      );
      print('❌ 역할 업데이트 오류(로컬로 계속): $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateBusinessProfile({
    String? name,
    String? phoneNumber,
    required String businessName,
    String? businessNumber,
    String? address,
    List<String>? serviceAreas,
    List<String>? specialties,
  }) async {
    if (_currentUser == null) return;
    try {
      _isLoading = true;
      notifyListeners();

      // Supabase 테이블 컬럼명에 맞춤 (소문자)
      final updates = <String, dynamic>{
        if (name != null) 'name': name,
        if (phoneNumber != null) 'phonenumber': phoneNumber,  // 소문자
        'businessname': businessName,  // 소문자
        if (businessNumber != null) 'businessnumber': businessNumber,  // 소문자
        if (address != null) 'address': address,
        if (serviceAreas != null) 'serviceareas': serviceAreas,  // 소문자
        if (specialties != null) 'specialties': specialties,
        'role': 'business',
        'businessstatus': 'approved',  // 🎉 자동 승인으로 변경
      };
      
      // Only sync to Supabase if project is configured and user id looks like UUID
      final supaReady = SupabaseConfig.url.isNotEmpty && SupabaseConfig.anonKey.isNotEmpty;
      final uuidLike = RegExp(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}").hasMatch(_currentUser!.id);
      
      print('📝 사업자 프로필 업데이트 시도: ID=${_currentUser!.id}');
      print('   업데이트 데이터: $updates');
      
      if (supaReady && uuidLike) {
        // 서버 저장에 실패하면 로컬만 갱신해서 '저장됨'으로 보이던 문제가 있었습니다.
        // 실패는 호출자에게 전달해 사용자에게 알립니다.
        final result = await _sb
            .from('users')
            .update(updates)
            .eq('id', _currentUser!.id)
            .select();
        print('   업데이트된 행 수: ${result.length}');
        if (result.isEmpty) {
          throw Exception('프로필을 저장할 권한이 없거나 계정을 찾을 수 없습니다.');
        }
        print('✅ Supabase 사업자 프로필 업데이트 성공: ${_currentUser!.id}');
      } else {
        print('⚠️  Supabase 업데이트 건너뜀 (supaReady: $supaReady, uuidLike: $uuidLike)');
        print('   현재 사용자 ID: ${_currentUser!.id}');
      }

      _currentUser = _currentUser!.copyWith(
        name: name,
        phoneNumber: phoneNumber,
        role: 'business',
        businessName: businessName,
        businessNumber: businessNumber,
        address: address,
        serviceAreas: serviceAreas,
        specialties: specialties,
        businessStatus: 'approved',  // 🎉 자동 승인으로 변경
      );
      print('🎉 사업자 프로필이 업데이트되었습니다 (자동 승인)');
    } catch (e) {
      print('사업자 프로필 업데이트 실패: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 현재 사용자 정보를 새로고침 (승인 상태 확인용)
  Future<void> refreshCurrentUser() async {
    if (_currentUser == null) return;
    
    try {
      print('🔄 [AuthService] 사용자 정보 새로고침 시작');
      await _loadUserData(_currentUser!.id);
      print('✅ [AuthService] 사용자 정보 새로고침 완료');
      notifyListeners();
    } catch (e) {
      print('❌ [AuthService] 사용자 정보 새로고침 실패: $e');
    }
  }

  /// 진위확인 성공 후 호출. 서버에서 users 테이블이 갱신되므로
  /// 다시 읽어서 로컬 상태(verifyStatus, verifiedAt 등)를 동기화한다.
  Future<void> refreshAfterBusinessVerify() async {
    await refreshCurrentUser();
  }

  /// 사업자번호가 등록되어 있지 않은 사업자 회원에게 안내 알림을 생성하는 로직.
  /// 사용자 요청에 따라 더 이상 알림을 생성하지 않는다 (no-op).
  /// 사업자번호 등록은 사용자가 프로필에서 자율적으로 진행한다.
  // ignore: unused_element
  Future<void> _maybeNotifyBusinessVerifyRequired() async {
    return;
  }

  /// 세션에서 사용자 정보를 로드 (자동 로그인용)
  Future<void> loadUserFromSession() async {
    try {
      final session = _sb.auth.currentSession;
      if (session == null) {
        print('ℹ️ [AuthService] 세션 없음');
        return;
      }

      final userId = session.user.id;
      print('🔄 [AuthService] 세션에서 사용자 정보 로드: $userId');

      _isLoadingManually = true; // onAuthStateChange 중복 방지
      var sessionLoadTimedOut = false;
      try {
        // 런치 시 Supabase 지연으로 UI가 멈춘 것처럼 보이는 문제 완화 (iPad 심사 2.1)
        await _loadUserData(userId).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        sessionLoadTimedOut = true;
        debugPrint('⚠️ [AuthService] 세션 사용자 로드 타임아웃 — 다음 화면으로 진행');
        _currentUser = null;
      } finally {
        _isLoadingManually = false;
      }
      notifyListeners();

      if (!sessionLoadTimedOut) {
        print('✅ [AuthService] 세션에서 사용자 정보 로드 완료');
      }
    } catch (e) {
      print('❌ [AuthService] 세션에서 사용자 정보 로드 실패: $e');
      _currentUser = null;
      _isLoadingManually = false;
      notifyListeners();
    }
  }
} 