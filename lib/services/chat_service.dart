import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class ChatService extends ChangeNotifier {
  final SupabaseClient _sb = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  // 기존 코드 호환: roomKey를 title로 저장하고, 실제 id는 DB에서 생성/기존 채팅방 재사용
  Future<String> createChatRoom(String roomKey, String customerId, String businessId, {String? estimateId}) async {
    return ensureChatRoom(customerId: customerId, businessId: businessId, title: roomKey, estimateId: estimateId);
  }

  Future<String> ensureChatRoom({
    required String customerId,
    required String businessId,
    String? estimateId, // 견적서 ID (옵션)
    String? listingId, // 오더 마켓플레이스 ID (옵션)
    String? title,
  }) async {
    try {
      debugPrint('🔍 [ensureChatRoom] 채팅방 생성/조회 시작');
      debugPrint('   customerId: $customerId, businessId: $businessId');
      debugPrint('   estimateId: $estimateId, listingId: $listingId');
      
      // 0) If caller passed a deterministic key (e.g., 'call_<listingId>'),
      // try to reuse a room whose title equals it, or id if it's a UUID.
      if (title != null && title.isNotEmpty) {
        try {
          final uuidPattern = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
          if (uuidPattern.hasMatch(title)) {
            final byId = await _sb
                .from('chat_rooms')
                .select('id')
                .eq('id', title)
                .limit(1)
                .maybeSingle();
            if (byId != null && byId['id'] != null) {
              debugPrint('✅ [ensureChatRoom] 기존 채팅방 찾음 (ID)');
              return byId['id'].toString();
            }
          }
          final byTitle = await _sb
              .from('chat_rooms')
              .select('id')
              .eq('title', title)
              .limit(1)
              .maybeSingle();
          if (byTitle != null && byTitle['id'] != null) {
            debugPrint('✅ [ensureChatRoom] 기존 채팅방 찾음 (Title)');
            return byTitle['id'].toString();
          }
        } catch (_) {}
      }
      
      Map<String, dynamic>? existing;
      // Schema: participant_a/participant_b 우선, 없으면 customerid/businessid
      try {
        debugPrint('🔍 [ensureChatRoom] 기존 채팅방 검색 (participants)');
        var q1 = _sb
            .from('chat_rooms')
            .select('id')
            .or('and(participant_a.eq.$customerId,participant_b.eq.$businessId),and(participant_a.eq.$businessId,participant_b.eq.$customerId)');
        
        // listingId가 있으면 listingId로 필터링
        if (listingId != null && listingId.isNotEmpty) {
          q1 = q1.eq('listingid', listingId);
        }
        // estimateId가 있으면 estimateId로 필터링
        else if (estimateId != null && estimateId.isNotEmpty) {
          q1 = q1.eq('estimateid', estimateId);
        }
        
        existing = await q1.limit(1).maybeSingle();
      } catch (e) {
        debugPrint('⚠️ [ensureChatRoom] participants 검색 실패: $e');
        // Fallback: customerid/businessid로 검색
        try {
          var q2 = _sb
              .from('chat_rooms')
              .select('id')
              .eq('customerid', customerId)
              .eq('businessid', businessId);
          if (listingId != null && listingId.isNotEmpty) {
            q2 = q2.eq('listingid', listingId);
          } else if (estimateId != null && estimateId.isNotEmpty) {
            q2 = q2.eq('estimateid', estimateId);
          }
          existing = await q2.limit(1).maybeSingle();
        } catch (_) {
          existing = null;
        }
      }
      
      if (existing != null && existing['id'] != null) {
        debugPrint('✅ [ensureChatRoom] 기존 채팅방 찾음: ${existing['id']}');
        return existing['id'].toString();
      }

      final nowIso = DateTime.now().toIso8601String();
      // Insert with both schemas (호환성 유지)
      try {
        debugPrint('🆕 [ensureChatRoom] 새 채팅방 생성');
        final payloadA = <String, dynamic>{
          // 새로운 스키마
          'participant_a': customerId,
          'participant_b': businessId,
          // 기존 스키마 (호환성)
          'customerid': customerId,
          'businessid': businessId,
          'active': true,
          'createdat': nowIso,
          // 오더 시스템인 경우 listingId, 견적 시스템인 경우 estimateId
          if (listingId != null && listingId.isNotEmpty) 'listingid': listingId,
          if (estimateId != null && estimateId.isNotEmpty) 'estimateid': estimateId,
          if (title != null && title.isNotEmpty) 'title': title,
        };
        
        debugPrint('   Payload: $payloadA');
        final insA = await _sb.from('chat_rooms').insert(payloadA).select('id').single();
        debugPrint('✅ [ensureChatRoom] 새 채팅방 생성 완료: ${insA['id']}');
        return insA['id'].toString();
      } catch (e) {
        debugPrint('❌ [ensureChatRoom] 채팅방 생성 실패: $e');
        rethrow;
      }
    } catch (e) {
      debugPrint('❌ [ensureChatRoom] 전체 프로세스 실패: $e');
      rethrow;
    }
  }

  // 메시지 전송 (임시 구현)
  Future<void> sendMessage(String chatRoomId, String message, String senderId) async {
    try {
      print('=== sendMessage 시작 ===');
      print('chatRoomId: $chatRoomId');
      print('message: $message');
      print('senderId: $senderId');
      
      // If chatRoomId is not a UUID, try to resolve to a UUID via chat_rooms
      final isUuid = RegExp(r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$').hasMatch(chatRoomId);
      String resolvedId = chatRoomId;
      
      print('isUuid: $isUuid');
      
      if (!isUuid) {
        print('UUID가 아님, chat_rooms에서 ID 확인 시도...');
        try {
          final existingRoom = await _sb
              .from('chat_rooms')
              .select('id')
              .eq('title', chatRoomId)
              .limit(1)
              .maybeSingle();
          
          if (existingRoom != null && existingRoom['id'] != null) {
            resolvedId = existingRoom['id'].toString();
            print('기존 채팅방 ID 찾음: $resolvedId');
          } else {
            print('기존 채팅방을 찾을 수 없음');
          }
        } catch (e) {
          print('기존 채팅방 검색 실패: $e');
        }
      }

      print('최종 resolvedId: $resolvedId');

      // 메시지 저장
      final nowIso = DateTime.now().toIso8601String();
      print('메시지 저장 시도...');
      print('테이블: chat_messages');
      print('데이터: {room_id: $resolvedId, sender_id: $senderId, content: $message, createdat: $nowIso}');
      
      final insertResult = await _sb.from('chat_messages').insert({
        'room_id': resolvedId,
        'sender_id': senderId,
        'content': message,
        'createdat': nowIso,
      }).select();
      
      print('메시지 저장 성공: $insertResult');

      // 채팅방 참가자 정보 가져오기 (participant_a/b, customerid/businessid 모두 지원)
      print('채팅방 정보 가져오기 시도...');
      final chatRoom = await _sb
          .from('chat_rooms')
          .select('participant_a, participant_b, customerid, businessid, title')
          .eq('id', resolvedId)
          .single();
      
      print('채팅방 정보: $chatRoom');

      // 발신자 정보 가져오기
      print('발신자 프로필 가져오기 시도...');
      final senderProfile = await _getUserProfile(senderId);
      final senderName = senderProfile?['name'] ?? senderProfile?['businessname'] ?? '사용자';
      print('발신자 이름: $senderName');

      // 수신자 ID 결정 (participant_a/b 우선, 없으면 customerid/businessid)
      String recipientId = '';
      final pa = chatRoom['participant_a']?.toString();
      final pb = chatRoom['participant_b']?.toString();
      final cust = chatRoom['customerid']?.toString();
      final biz = chatRoom['businessid']?.toString();
      if (pa != null && pb != null) {
        recipientId = (senderId == pa) ? pb : pa;
        print('participant 기반 수신자: $recipientId');
      } else if (cust != null && biz != null) {
        recipientId = (senderId == cust) ? biz : cust;
        print('customerid/businessid 기반 수신자: $recipientId');
      }

      // 채팅 알림 전송 (실패해도 메시지는 성공으로 처리)
      print('채팅 알림 전송 시도...');
      try {
        await _notificationService.sendChatNotification(
          recipientUserId: recipientId,
          senderName: senderName,
          message: message,
          chatRoomId: resolvedId,
        );
        print('✅ 채팅 알림 전송 성공');
      } catch (notifError) {
        print('⚠️ 채팅 알림 전송 실패 (무시됨): $notifError');
        // 알림 실패해도 메시지는 저장되었으므로 계속 진행
      }

      print('=== 메시지 전송 완료 ===');
      print('chatRoomId: $resolvedId');
      print('수신자: $recipientId');
      print('발신자: $senderName');
      
    } catch (e) {
      print('=== sendMessage 실패 ===');
      print('에러: $e');
      print('에러 타입: ${e.runtimeType}');
      if (e is PostgrestException) {
        print('PostgrestException 상세:');
        print('  message: ${e.message}');
        print('  code: ${e.code}');
        print('  details: ${e.details}');
        print('  hint: ${e.hint}');
      }
      debugPrint('sendMessage failed: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getMessages(String chatRoomId) async {
    try {
      final me = _sb.auth.currentUser?.id ?? '';
      final rows = await _sb
          .from('chat_messages')
          .select()
          .eq('room_id', chatRoomId)
          .order('createdat', ascending: true);
      return rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        final created = m['createdat'] ?? m['createdAt'] ?? m['created_at'];
        m['timestamp'] = DateTime.tryParse(created?.toString() ?? '') ?? DateTime.now();
        m['isFromMe'] = (m['sender_id']?.toString() ?? m['senderid']?.toString() ?? m['senderId']?.toString() ?? '') == me;
        m['text'] = (m['content'] ?? m['text'] ?? '').toString();
        return m;
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 채팅방을 읽음 처리 (현재 사용자의 last_read_at 업데이트)
  Future<void> markChatRead(String chatRoomId, String userId) async {
    try {
      debugPrint('📖 [ChatService] 채팅 읽음 처리: roomId=$chatRoomId, userId=$userId');
      
      // 채팅방 정보 가져오기
      final room = await _sb
          .from('chat_rooms')
          .select('participant_a, participant_b')
          .eq('id', chatRoomId)
          .maybeSingle();
      
      if (room == null) {
        debugPrint('   ⚠️ 채팅방을 찾을 수 없음');
        return;
      }
      
      // 현재 사용자가 participant_a인지 participant_b인지 확인
      final isParticipantA = room['participant_a']?.toString() == userId;
      final fieldToUpdate = isParticipantA 
          ? 'participant_a_last_read_at' 
          : 'participant_b_last_read_at';
      
      // 현재 시간으로 업데이트
      await _sb
          .from('chat_rooms')
          .update({fieldToUpdate: DateTime.now().toIso8601String()})
          .eq('id', chatRoomId);
      
      debugPrint('   ✅ 읽음 처리 완료: $fieldToUpdate');
    } catch (e) {
      debugPrint('   ❌ 읽음 처리 실패: $e');
    }
  }

  // 채팅방 목록 가져오기 (최적화 버전)
  Future<List<Map<String, dynamic>>> getChatRooms(String userId) async {
    try {
      debugPrint('🔍 [ChatService] 채팅방 목록 로드: userId=$userId');
      final startTime = DateTime.now();
      
      // 1. 채팅방 정보 가져오기
      final rows = await _sb
          .from('chat_rooms')
          .select('id, title, createdat, customerid, businessid, participant_a, participant_b, estimateid, listingid, active, participant_a_last_read_at, participant_b_last_read_at')
          .or('customerid.eq.$userId,businessid.eq.$userId,participant_a.eq.$userId,participant_b.eq.$userId')
          .eq('active', true)
          .order('createdat', ascending: false);
      
      debugPrint('✅ [ChatService] ${rows.length}개 채팅방 조회 완료');
      
      if (rows.isEmpty) return [];
      
      // 2. 모든 상대방 ID 수집
      final otherUserIds = <String>{};
      final roomMap = <String, Map<String, dynamic>>{};
      
      for (final r in rows) {
        final room = Map<String, dynamic>.from(r);
        roomMap[room['id']] = room;
        
        String otherId = '';
        if (room['participant_a']?.toString() == userId) {
          otherId = room['participant_b']?.toString() ?? '';
        } else if (room['participant_b']?.toString() == userId) {
          otherId = room['participant_a']?.toString() ?? '';
        } else if (room['customerid']?.toString() == userId) {
          otherId = room['businessid']?.toString() ?? '';
        } else if (room['businessid']?.toString() == userId) {
          otherId = room['customerid']?.toString() ?? '';
        }
        
        if (otherId.isNotEmpty) {
          otherUserIds.add(otherId);
          room['_otherId'] = otherId;
        }
      }
      
      // 3. 모든 사용자 정보 병렬로 가져오기 (한 번의 in 쿼리로)
      final userMap = <String, Map<String, dynamic>>{};
      if (otherUserIds.isNotEmpty) {
        try {
          final users = await _sb
              .from('users')
              .select('id, businessname, name, avatar_url, role')
              .inFilter('id', otherUserIds.toList());
          for (final u in users) {
            final m = Map<String, dynamic>.from(u);
            final id = m['id']?.toString();
            if (id != null) userMap[id] = m;
          }
        } catch (e) {
          debugPrint('   ⚠️ 상대방 사용자 정보 일괄 조회 실패: $e');
        }
      }
      
      // 4. 표시용 메타데이터 설정 (상대방 이름/아바타, 오더 제목)
      for (final room in roomMap.values) {
        final otherId = room['_otherId'];
        if (otherId != null && userMap.containsKey(otherId)) {
          final user = userMap[otherId]!;
          final bn = user['businessname']?.toString();
          final nm = user['name']?.toString();
          room['displayName'] = (bn != null && bn.isNotEmpty) ? bn : ((nm != null && nm.isNotEmpty) ? nm : '상대방');
          room['otherAvatarUrl'] = user['avatar_url']?.toString();
          room['otherRole'] = user['role']?.toString();
          room['otherBusinessName'] = bn;
          room['otherName'] = nm;
        } else {
          room['displayName'] = room['title']?.toString() ?? '채팅';
        }

        final savedTitle = room['title']?.toString();
        if (savedTitle != null && savedTitle.isNotEmpty && !savedTitle.startsWith('order_') && !savedTitle.startsWith('call_')) {
          room['orderTitle'] = savedTitle;
        }

        // 기본값 (메시지가 없는 방 대비)
        room['lastMessage'] = '';
        room['unreadCount'] = 0;
      }

      // 5. 모든 방의 메시지를 단일 쿼리로 가져와 마지막 메시지 + 안읽음 수 계산
      //    (방마다 2쿼리씩 쏘던 N+1 패턴 제거)
      try {
        final roomIds = roomMap.keys.toList();
        final messages = await _sb
            .from('chat_messages')
            .select('room_id, content, text, createdat, sender_id')
            .inFilter('room_id', roomIds)
            .order('createdat', ascending: false);

        for (final msg in messages) {
          final roomId = msg['room_id']?.toString();
          if (roomId == null) continue;
          final room = roomMap[roomId];
          if (room == null) continue;

          // 내림차순이므로 첫 등장이 가장 최근 메시지
          if (room['lastMessageAt'] == null) {
            room['lastMessage'] = (msg['content']?.toString() ?? msg['text']?.toString() ?? '');
            room['lastMessageAt'] = msg['createdat']?.toString();
          }

          // 안읽음 수 집계 (상대방 메시지 & last_read 이후)
          if (msg['sender_id']?.toString() != userId) {
            final isParticipantA = room['participant_a']?.toString() == userId;
            final lastReadRaw = isParticipantA
                ? room['participant_a_last_read_at']
                : room['participant_b_last_read_at'];
            final lastRead = lastReadRaw != null ? DateTime.tryParse(lastReadRaw.toString()) : null;
            final createdAt = DateTime.tryParse(msg['createdat']?.toString() ?? '');
            if (lastRead == null || (createdAt != null && createdAt.isAfter(lastRead))) {
              room['unreadCount'] = (room['unreadCount'] as int) + 1;
            }
          }
        }
      } catch (e) {
        debugPrint('   ⚠️ 메시지 일괄 조회 실패: $e');
      }
      
      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds;
      debugPrint('✅ [ChatService] 채팅방 목록 로드 완료 (${duration}ms)');
      
      return roomMap.values.toList();
    } catch (e) {
      debugPrint('❌ [ChatService] 채팅방 목록 로드 실패: $e');
      return [];
    }
  }

  // 채팅방 상세 (estimateid, participants 등)
  Future<Map<String, dynamic>?> getChatRoom(String chatRoomId) async {
    try {
      final row = await _sb
          .from('chat_rooms')
          .select()
          .eq('id', chatRoomId)
          .maybeSingle();
      if (row == null) return null;
      return Map<String, dynamic>.from(row);
    } catch (_) {
      return null;
    }
  }

  // 메시지 전체 삭제
  Future<void> deleteMessages(String chatRoomId) async {
    await _sb.from('chat_messages').delete().eq('room_id', chatRoomId);
  }

  // 채팅방 삭제 (소프트 삭제: active=false)
  Future<void> softDeleteChatRoom(String chatRoomId, String userId) async {
    await _sb
        .from('chat_rooms')
        .update({'active': false})
        .eq('id', chatRoomId)
        .or('customerid.eq.$userId,businessid.eq.$userId');
  }

  // 채팅방 활성화 (임시 구현)
  Future<void> activateChatRoom(String estimateId, String businessId) async {
    try {
      await _sb
          .from('chat_rooms')
          .update({'active': true})
          .eq('estimateid', estimateId)
          .eq('businessid', businessId);
    } catch (e) {
      rethrow;
    }
  }

  /// 채팅방 + 상대방 프로필 + 오더 제목을 한 번에 (ChatScreen 진입용)
  Future<Map<String, dynamic>?> getChatRoomWithPeer(String chatRoomId, String myUserId) async {
    try {
      final room = await _sb
          .from('chat_rooms')
          .select('id, customerid, businessid, participant_a, participant_b, title, listingid, estimateid')
          .eq('id', chatRoomId)
          .maybeSingle();
      if (room == null) return null;

      String? otherId;
      if (room['participant_a']?.toString() == myUserId) {
        otherId = room['participant_b']?.toString();
      } else if (room['participant_b']?.toString() == myUserId) {
        otherId = room['participant_a']?.toString();
      } else if (room['customerid']?.toString() == myUserId) {
        otherId = room['businessid']?.toString();
      } else if (room['businessid']?.toString() == myUserId) {
        otherId = room['customerid']?.toString();
      }

      Map<String, dynamic>? other;
      if (otherId != null && otherId.isNotEmpty) {
        other = await _sb
            .from('users')
            .select('id, businessname, name, avatar_url, role')
            .eq('id', otherId)
            .maybeSingle();
      }

      String? orderTitle;
      final listingId = room['listingid']?.toString();
      if (listingId != null && listingId.isNotEmpty) {
        try {
          final listing = await _sb
              .from('marketplace_listings')
              .select('title')
              .eq('id', listingId)
              .maybeSingle();
          orderTitle = listing?['title']?.toString();
        } catch (_) {}
      }

      final bn = other?['businessname']?.toString();
      final nm = other?['name']?.toString();
      final displayName = (bn != null && bn.isNotEmpty)
          ? bn
          : ((nm != null && nm.isNotEmpty) ? nm : '상대방');

      return {
        'room': room,
        'otherId': otherId,
        'otherAvatarUrl': other?['avatar_url']?.toString(),
        'otherDisplayName': displayName,
        'otherRole': other?['role']?.toString(),
        'otherBusinessName': bn,
        'otherName': nm,
        'orderTitle': orderTitle,
        'listingId': listingId,
      };
    } catch (e) {
      debugPrint('❌ getChatRoomWithPeer 실패: $e');
      return null;
    }
  }

  /// 사용자 프로필 정보 가져오기
  Future<Map<String, dynamic>?> _getUserProfile(String userId) async {
    try {
      // 사용자 프로필 확인 (users 테이블 사용)
      final customerProfile = await _sb
          .from('users')
          .select('name, businessname')
          .eq('id', userId)
          .maybeSingle();
      
      if (customerProfile != null) {
        return customerProfile;
      }

      // 사업자 프로필 확인
      final businessProfile = await _sb
          .from('businesses')
          .select('businessname')
          .eq('id', userId)
          .maybeSingle();
      
      if (businessProfile != null) {
        return businessProfile;
      }

      return null;
    } catch (e) {
      debugPrint('사용자 프로필 가져오기 실패: $e');
      return null;
    }
  }
} 