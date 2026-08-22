import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import '../../services/auth_service.dart';
import '../../widgets/common_app_bar.dart';
import '../../widgets/kakao_login_button.dart';
import '../../theme/business_theme.dart';
import 'signup_page.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signInWithEmailAndPassword(
        _emailController.text.trim(),
        _passwordController.text,
      );
      // 성공/실패는 onAuthStateChange에 의해 화면이 전환됨
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('오류: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _appleSignIn() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: const Dialog(
          backgroundColor: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Apple로 로그인 중…'),
              ],
            ),
          ),
        ),
      ),
    );
    try {
      final ok = await context.read<AuthService>().signInWithApple();
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apple 로그인에 실패했습니다. 설정을 확인하거나 이메일로 로그인해 주세요.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const CommonAppBar(title: '로그인'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              const Text(
                '올수리',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: BusinessTheme.navy,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '이메일로 로그인하거나 소셜 로그인을 이용하세요',
                textAlign: TextAlign.center,
                style: TextStyle(color: BusinessTheme.textMuted, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextFormField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: '이메일',
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '이메일을 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: '비밀번호',
                ),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return '비밀번호를 입력해주세요.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('로그인'),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Apple 또는 카카오로도 로그인할 수 있습니다',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: BusinessTheme.textMuted),
              ),
              const SizedBox(height: 12),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS)
                SizedBox(
                  width: double.infinity,
                  child: SignInWithAppleButton(
                    style: SignInWithAppleButtonStyle.black,
                    height: 56,
                    borderRadius: BorderRadius.circular(12),
                    onPressed: () {
                      if (!_isLoading) _appleSignIn();
                    },
                  ),
                ),
              if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) const SizedBox(height: 10),
              KakaoLoginButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (BuildContext dialogContext) {
                              return WillPopScope(
                                onWillPop: () async => false,
                                child: const Dialog(
                                  child: Padding(
                                    padding: EdgeInsets.all(32.0),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircularProgressIndicator(),
                                        SizedBox(height: 16),
                                        Text('연결하는 중…'),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                          
                          try {
                            final authService = context.read<AuthService>();
                            final ok = await authService.signInWithKakao();
                            
                            // 로딩 다이얼로그 닫기
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                            }
                            
                            if (ok) {
                              // 사업자 로그인 의도: 역할을 즉시 사업자로 설정 (승인 필요)
                              final currentUser = authService.currentUser;
                              if (currentUser?.role == 'business') {
                                // 이미 사업자인 경우 businessStatus 확인
                                if (currentUser?.businessStatus != 'approved') {
                                  // 승인 대기 중
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('사업자 승인 대기 중입니다. 관리자 승인 후 이용 가능합니다. 잠시만 기다려 주세요!'),
                                        duration: Duration(seconds: 3),
                                      ),
                                    );
                                  }
                                }
                              } else {
                                // 처음 사업자로 등록하는 경우
                                await authService.updateRole('business');
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('사업자 등록 신청이 완료되었습니다. 관리자 승인 후 이용 가능합니다.'),
                                      duration: Duration(seconds: 3),
                                    ),
                                  );
                                }
                              }
                            } else if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('카카오 로그인 실패')),
                              );
                            }
                          } catch (e) {
                            // 로딩 다이얼로그 닫기 (에러 시에도)
                            if (context.mounted) {
                              Navigator.of(context, rootNavigator: true).pop();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('오류: $e')),
                              );
                            }
                          }
                        },
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const SignupPage(),
                    ),
                  );
                },
                child: const Text('회원가입'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}