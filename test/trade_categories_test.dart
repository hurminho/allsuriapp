import 'package:allsuriapp/config/trade_categories.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('대분류 12개, 기타는 마지막', () {
    expect(TradeCategories.groupNames.length, 12);
    expect(TradeCategories.groupNames.last, '기타');
  });

  test('세부 공종·대분류·예전 값을 대분류로 맞춘다', () {
    expect(TradeCategories.groupOf('변기 막힘'), '하수구·막힘');
    expect(TradeCategories.groupOf('누수·방수'), '누수·방수');
    expect(TradeCategories.groupOf('배수장치'), '하수구·막힘');
    expect(TradeCategories.groupOf('수도'), '수도·급수');
    expect(TradeCategories.groupOf('에어컨 분해 세척'), '가전·설비 청소');
    expect(TradeCategories.groupOf('냉장고'), '기타');
    expect(TradeCategories.groupOf(null), '기타');
  });

  test('세부 공종 이름은 겹치지 않는다', () {
    final all = [for (final g in TradeCategories.groups) ...g.items];
    expect(all.toSet().length, all.length);
  });
}
