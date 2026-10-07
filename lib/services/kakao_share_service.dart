import 'package:kakao_flutter_sdk_share/kakao_flutter_sdk_share.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

/// 카카오톡 공유 서비스
class KakaoShareService {
  /// 오더방 오픈채팅방 URL
  static const String orderChatUrl = 'https://open.kakao.com/o/gv9woeWh';
  
  /// 견적 요청을 카카오톡으로 공유 (일반 고객용)
  Future<bool> shareEstimate({
    required String estimateId,
    required String title,
    required String category,
    required String address,
    String? description,
  }) async {
    try {
      print('🔍 [KakaoShare] shareEstimate 시작: $estimateId');
      
      final template = FeedTemplate(
        content: Content(
          title: '🔧 견적 요청: $title',
          description: '카테고리: $category\n주소: $address${description != null ? "\n\n$description" : ""}',
          imageUrl: Uri.parse('https://iiunvogtqssxaxdnhqaj.supabase.co/storage/v1/object/public/attachments_estimates/logo.png'), // ✅ 변경
          link: Link(
            androidExecutionParams: {'estimateId': estimateId},
            iosExecutionParams: {'estimateId': estimateId},
            webUrl: Uri.parse('https://play.google.com/store/apps/details?id=com.ononcompany.allsuri'), // ✅ 변경
            mobileWebUrl: Uri.parse('https://play.google.com/store/apps/details?id=com.ononcompany.allsuri'), // ✅ 변경
          ),
        ),
        buttons: [
          Button(
            title: '앱에서 보기',
            link: Link(
              androidExecutionParams: {'estimateId': estimateId},
              iosExecutionParams: {'estimateId': estimateId},
              webUrl: Uri.parse('https://play.google.com/store/apps/details?id=com.ononcompany.allsuri'), // ✅ 변경
              mobileWebUrl: Uri.parse('https://play.google.com/store/apps/details?id=com.ononcompany.allsuri'), // ✅ 변경
            ),
          ),
        ],
      );

      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        final uri = await ShareClient.instance.shareDefault(template: template);
        await launchUrl(uri, mode: LaunchMode.externalApplication);
              return true;
      } else {
        final url = await WebSharerClient.instance.makeDefaultUrl(template: template);
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('❌ [KakaoShare] 견적 공유 실패: $e');
      return false;
    }
  }

  /// 오더(공사)를 카카오톡으로 공유 (사업자용)
  /// ※ 주의: 카카오 SDK 정책상 사용자가 직접 채팅방을 선택하는 화면이 반드시 뜹니다.
  Future<bool> shareOrder({
    required String orderId,
    required String title,
    required String region,
    required String category,
    double? budgetAmount,
    double? commissionRate,
    String? imageUrl,
    String? description,
  }) async {
    try {
      print('🔍 [KakaoShare] shareOrder 시작');
      
      // 예산 및 수수료 포맷팅
      String budgetText = '';
      if (budgetAmount != null && budgetAmount > 0) {
        final formatter = NumberFormat('#,###');
        budgetText = '\n💰 견적 금액: ${formatter.format(budgetAmount)}원';
      }
      
      String feeText = '';
      if (commissionRate != null) {
        feeText = '\n💳 수수료: ${commissionRate.toStringAsFixed(0)}%';
      }

      // 설명 추가
      String descText = '';
      if (description != null && description.isNotEmpty) {
        final shortDesc = description.length > 100 
            ? '${description.substring(0, 100)}...' 
            : description;
        descText = '\n\n📝 $shortDesc';
      }

      // 이미지 URL (allsuri.app은 SSL 인증서 문제 → api.allsuri.app 사용)
      final String finalImageUrl = (imageUrl != null && imageUrl.startsWith('http'))
          ? imageUrl
          : 'https://api.allsuri.app/assets/images/logo.png';

      print('   [KakaoShare] 최종 공유 이미지 URL: $finalImageUrl');

      // 딥링크 URL (api.allsuri.app은 SSL 정상)
      final deepLinkUrl = 'https://api.allsuri.app/order/$orderId';

      // 1. 카카오톡 공유 템플릿 (Feed) 생성
      final template = FeedTemplate(
        content: Content(
          title: '🔧 오더: $title',
          description: '지역: $region$budgetText$feeText$descText',
          imageUrl: Uri.parse(finalImageUrl),
          imageWidth: 400,
          imageHeight: 400,
          link: Link(
            androidExecutionParams: {'orderId': orderId, 'path': 'order_detail'},
            iosExecutionParams: {'orderId': orderId, 'path': 'order_detail'},
            webUrl: Uri.parse(deepLinkUrl),
            mobileWebUrl: Uri.parse(deepLinkUrl),
          ),
        ),
        buttons: [
          Button(
            title: '앱에서 오더 확인',
            link: Link(
              androidExecutionParams: {'orderId': orderId, 'path': 'order_detail'},
              iosExecutionParams: {'orderId': orderId, 'path': 'order_detail'},
              webUrl: Uri.parse(deepLinkUrl),
              mobileWebUrl: Uri.parse(deepLinkUrl),
            ),
          ),
        ],
      );

      // 2. 카카오톡 설치 여부 확인 후 실행
      if (await ShareClient.instance.isKakaoTalkSharingAvailable()) {
        print('🔍 [KakaoShare] 카카오톡 앱으로 공유 시도...');
        final uri = await ShareClient.instance.shareDefault(template: template);
        
        // URI가 반환되면 직접 실행 (더 확실한 인텐트 전달)
        await launchUrl(uri, mode: LaunchMode.externalApplication);
              return true;
      } else {
        // 카카오톡 미설치 시 웹 브라우저 공유
        print('🔍 [KakaoShare] 카카오톡 미설치, 웹 공유 실행');
        final url = await WebSharerClient.instance.makeDefaultUrl(template: template);
        await launchUrl(url, mode: LaunchMode.externalApplication);
        return true;
      }
    } catch (e) {
      print('❌ [KakaoShare] 오더 공유 실패: $e');
      return false;
    }
  }

  /// 오픈채팅방 링크 직접 열기
  Future<bool> openOrderChatRoom() async {
    try {
      final Uri url = Uri.parse(orderChatUrl);
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      print('❌ [KakaoShare] 오픈채팅방 열기 실패: $e');
      return false;
    }
  }
}
