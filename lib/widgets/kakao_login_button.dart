import 'package:flutter/material.dart';

/// 카카오 로그인 공식 컬러(#FEE500) 기준 풀폭 버튼.
/// 이미지 에셋을 늘리지 않고, 숨고·당근처럼 높이 56·최소 탭 44를 맞춘다.
class KakaoLoginButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;

  static const Color brandYellow = Color(0xFFFEE500);
  static const Color labelColor = Color(0xD9000000);

  const KakaoLoginButton({
    super.key,
    this.onPressed,
    this.label = '카카오로 시작하기',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: Material(
        color: brandYellow,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _KakaoMark(),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: labelColor,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KakaoMark extends StatelessWidget {
  const _KakaoMark();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 22,
      height: 20,
      child: CustomPaint(painter: _KakaoBubblePainter()),
    );
  }
}

class _KakaoBubblePainter extends CustomPainter {
  const _KakaoBubblePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = KakaoLoginButton.labelColor;
    final r = RRect.fromLTRBR(
      0,
      0,
      size.width,
      size.height * 0.78,
      const Radius.circular(5),
    );
    canvas.drawRRect(r, paint);
    final path = Path()
      ..moveTo(size.width * 0.18, size.height * 0.72)
      ..lineTo(size.width * 0.32, size.height)
      ..lineTo(size.width * 0.42, size.height * 0.72)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
