import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../services/ad_service.dart';
import '../../services/media_service.dart';
import '../../models/ad.dart';

class AdManagementScreen extends StatefulWidget {
  const AdManagementScreen({Key? key}) : super(key: key);

  @override
  State<AdManagementScreen> createState() => _AdManagementScreenState();
}

class _AdManagementScreenState extends State<AdManagementScreen> {
  final AdService _adService = AdService();
  final MediaService _mediaService = MediaService();
  final ImagePicker _picker = ImagePicker();
  
  late Future<List<Ad>> _adsFuture;

  @override
  void initState() {
    super.initState();
    _loadAds();
  }

  void _loadAds() {
    setState(() {
      _adsFuture = _adService.getAllAds();
    });
  }

  String _getLocationGuide(String location) {
    switch (location) {
      case 'home_banner':
        return '📱 홈 화면 상단에 표시되는 메인 배너\n권장 크기: 1200×400px (3:1 비율)';
      case 'dashboard_ad_1':
        return '🎯 대시보드 광고 슬라이드 1번\n권장 크기: 800×200px (4:1 비율)';
      case 'dashboard_ad_2':
        return '🎯 대시보드 광고 슬라이드 2번\n권장 크기: 800×200px (4:1 비율)';
      default:
        return '광고 위치를 선택해주세요';
    }
  }

  String _getLocationLabel(String location) {
    switch (location) {
      case 'home_banner':
        return '📱 홈 화면 배너';
      case 'dashboard_ad_1':
        return '🎯 대시보드 광고 1';
      case 'dashboard_ad_2':
        return '🎯 대시보드 광고 2';
      default:
        return location;
    }
  }

  Future<void> _showAddEditDialog({Ad? ad}) async {
    final titleController = TextEditingController(text: ad?.title ?? '');
    final linkController = TextEditingController(text: ad?.linkUrl ?? '');
    String? imageUrl = ad?.imageUrl;
    String location = ad?.location ?? 'dashboard_banner';
    bool isActive = ad?.isActive ?? true;
    File? imageFile;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(ad == null ? '광고 추가' : '광고 수정'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: '광고 제목',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(
                      labelText: '링크 URL (선택)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: location,
                    decoration: const InputDecoration(
                      labelText: '광고 위치',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'home_banner', child: Text('📱 홈 화면 배너')),
                      DropdownMenuItem(value: 'dashboard_ad_1', child: Text('🎯 대시보드 광고 1')),
                      DropdownMenuItem(value: 'dashboard_ad_2', child: Text('🎯 대시보드 광고 2')),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          location = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _getLocationGuide(location),
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Checkbox(
                        value: isActive,
                        onChanged: (value) {
                          setDialogState(() {
                            isActive = value ?? true;
                          });
                        },
                      ),
                      const Text('활성화'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('광고 이미지', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '📐 이미지 규격 안내',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '• 홈 화면: 1200 x 400px (3:1 비율)\n'
                          '• 대시보드: 800 x 200px (4:1 비율)\n'
                          '• 파일 형식: JPG, PNG\n'
                          '• 최대 크기: 2MB',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.black87,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (imageUrl != null && imageFile == null)
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Image.network(
                              imageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.error),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setDialogState(() {
                                  imageUrl = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (imageFile != null)
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Image.file(
                              imageFile!,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () {
                                setDialogState(() {
                                  imageFile = null;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Text('이미지 없음'),
                      ),
                    ),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final pickedFile = await _picker.pickImage(
                        source: ImageSource.gallery,
                        imageQuality: 85,
                      );
                      if (pickedFile != null) {
                        setDialogState(() {
                          imageFile = File(pickedFile.path);
                          imageUrl = null; // 새 이미지 선택 시 기존 URL 제거
                        });
                      }
                    },
                    icon: const Icon(Icons.image),
                    label: const Text('이미지 선택'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('제목을 입력해주세요')),
                    );
                    return;
                  }

                  Navigator.pop(context);
                  
                  // 로딩 표시
                  showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    String finalImageUrl = imageUrl ?? '';

                    // 새 이미지 파일이 있으면 업로드
                    if (imageFile != null) {
                      final uploadedUrl = await _mediaService.uploadAdImage(imageFile!);
                      if (uploadedUrl != null) {
                        finalImageUrl = uploadedUrl;
                      } else {
                        throw Exception('이미지 업로드 실패');
                      }
                    }

                    if (ad == null) {
                      // 신규 광고 추가
                      await _adService.createAd(
                        title: titleController.text.trim(),
                        imageUrl: finalImageUrl,
                        linkUrl: linkController.text.trim().isEmpty ? null : linkController.text.trim(),
                        location: location,
                        isActive: isActive,
                      );
                    } else {
                      // 기존 광고 수정
                      await _adService.updateAd(ad.id, {
                        'title': titleController.text.trim(),
                        'image_url': finalImageUrl,
                        'link_url': linkController.text.trim().isEmpty ? null : linkController.text.trim(),
                        'location': location,
                        'is_active': isActive,
                      });
                    }

                    Navigator.pop(context); // 로딩 닫기
                    _loadAds(); // 목록 새로고침
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(ad == null ? '광고가 추가되었습니다' : '광고가 수정되었습니다')),
                    );
                  } catch (e) {
                    Navigator.pop(context); // 로딩 닫기
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('오류 발생: $e')),
                    );
                  }
                },
                child: Text(ad == null ? '추가' : '수정'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteAd(Ad ad) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('광고 삭제'),
        content: Text('${ad.title} 광고를 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _adService.deleteAd(ad.id);
        _loadAds();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('광고가 삭제되었습니다')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('삭제 실패: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('광고 관리'),
        backgroundColor: const Color(0xFF0B2545),
      ),
      body: FutureBuilder<List<Ad>>(
        future: _adsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return Center(child: Text('오류: ${snapshot.error}'));
          }

          final ads = snapshot.data ?? [];

          if (ads.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.ad_units, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    '등록된 광고가 없습니다',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: ads.length,
            itemBuilder: (context, index) {
              final ad = ads[index];
              return Card(
                margin: const EdgeInsets.only(bottom: 16),
                child: ListTile(
                  leading: ad.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            ad.imageUrl,
                            width: 60,
                            height: 60,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 60,
                              height: 60,
                              color: Colors.grey[300],
                              child: const Icon(Icons.image_not_supported),
                            ),
                          ),
                        )
                      : Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image),
                        ),
                  title: Text(
                    ad.title ?? '제목 없음',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('위치: ${_getLocationLabel(ad.location)}'),
                      if (ad.linkUrl != null && ad.linkUrl!.isNotEmpty)
                        Text('🔗 ${ad.linkUrl}', 
                          style: const TextStyle(fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      Text('상태: ${ad.isActive ? '✅ 활성' : '❌ 비활성'}'),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, color: Colors.blue),
                        onPressed: () => _showAddEditDialog(ad: ad),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () => _deleteAd(ad),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: const Color(0xFF0B2545),
        icon: const Icon(Icons.add),
        label: const Text('광고 추가'),
      ),
    );
  }
}

