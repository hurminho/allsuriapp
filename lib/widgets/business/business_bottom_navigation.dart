import 'package:flutter/material.dart';

import 'business_tokens.dart';

class BusinessBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final int unreadChats;

  const BusinessBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
    this.unreadChats = 0,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: BusinessTokens.surface,
        border: Border(top: BorderSide(color: BusinessTokens.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 70,
          child: Row(
            children: [
              _item(
                index: 0,
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: '홈',
              ),
              _item(
                index: 1,
                icon: Icons.assignment_outlined,
                selectedIcon: Icons.assignment_rounded,
                label: '새 일감',
              ),
              Expanded(
                child: Semantics(
                  button: true,
                  label: '공사 만들기',
                  child: InkWell(
                    onTap: () => onTap(2),
                    child: Transform.translate(
                      offset: const Offset(0, -13),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: BusinessTokens.yellow,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: BusinessTokens.surface,
                                width: 4,
                              ),
                            ),
                            child: const Icon(
                              Icons.add_rounded,
                              color: BusinessTokens.navy,
                              size: 29,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            '공사 만들기',
                            maxLines: 1,
                            style: TextStyle(
                              color: BusinessTokens.navy,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              height: 1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _item(
                index: 3,
                icon: Icons.chat_bubble_outline_rounded,
                selectedIcon: Icons.chat_bubble_rounded,
                label: '채팅',
                badge: unreadChats,
              ),
              _item(
                index: 4,
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: '내 정보',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _item({
    required int index,
    required IconData icon,
    required IconData selectedIcon,
    required String label,
    int badge = 0,
  }) {
    final selected = currentIndex == index;
    final color = selected ? BusinessTokens.blue : BusinessTokens.mutedText;
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? selectedIcon : icon, color: color, size: 23),
                if (badge > 0)
                  Positioned(
                    right: -9,
                    top: -7,
                    child: Container(
                      constraints: const BoxConstraints(
                        minWidth: 17,
                        minHeight: 17,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: BusinessTokens.danger,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        badge > 9 ? '9+' : '$badge',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
