import { describe, expect, it } from 'vitest'
import { countPopupTargets, parsePopupInput } from '../lib/app_popups'

const base = { title: '공지', body: '내용', audience: 'all' }

describe('parsePopupInput', () => {
  it('기본값: 한 번만, 켜짐, 버튼 없음', () => {
    const row = parsePopupInput(base)
    expect(row.frequency).toBe('once')
    expect(row.is_active).toBe(true)
    expect(row.button_label).toBeNull()
    expect(row.target_trades).toEqual([])
  })

  it('버튼 링크만 넣으면 버튼 글자는 "자세히 보기", 링크가 없으면 버튼 글자도 지움', () => {
    expect(parsePopupInput({ ...base, buttonUrl: 'https://allsuri.app' }).button_label).toBe('자세히 보기')
    expect(parsePopupInput({ ...base, buttonLabel: '보기' }).button_label).toBeNull()
  })

  it('잘못된 링크·이미지·길이·기간은 거부', () => {
    expect(() => parsePopupInput({ ...base, buttonUrl: 'javascript:alert(1)' })).toThrow('버튼 링크')
    expect(() => parsePopupInput({ ...base, imageUrl: 'http://x.com/a.png' })).toThrow('이미지')
    expect(() => parsePopupInput({ ...base, title: 'x'.repeat(41) })).toThrow('제목')
    expect(() => parsePopupInput({ ...base, body: '' })).toThrow('내용')
    expect(() => parsePopupInput({ ...base, startAt: '2026-11-02T00:00', endAt: '2026-11-01T00:00' })).toThrow('종료')
    expect(() => parsePopupInput({ ...base, audience: 'everyone' })).toThrow('대상')
  })

  it('공종 대상은 아는 대분류만 남기고, 하나도 없으면 거부', () => {
    const row = parsePopupInput({ ...base, audience: 'trades', targetTrades: ['하수구·막힘', '없는공종', '하수구·막힘'] })
    expect(row.target_trades).toEqual(['하수구·막힘'])
    expect(() => parsePopupInput({ ...base, audience: 'trades', targetTrades: ['없는공종'] })).toThrow('공종')
  })

  it('지정 대상은 uuid 만, 다른 대상으로 바꾸면 목록을 비움', () => {
    const id = '00000000-0000-0000-0000-00000000000a'
    expect(parsePopupInput({ ...base, audience: 'selected', targetUserIds: [id, 'abc'] }).target_user_ids).toEqual([id])
    expect(() => parsePopupInput({ ...base, audience: 'selected', targetUserIds: ['abc'] })).toThrow('사업자')
    expect(parsePopupInput({ ...base, audience: 'all', targetUserIds: [id] }).target_user_ids).toEqual([])
  })
})

describe('countPopupTargets', () => {
  const users = [
    { id: 'a', specialties: ['변기 막힘'] },
    { id: 'b', specialties: ['배수장치', '보일러'] },
    { id: 'c', specialties: [] },
    { id: 'd', specialties: null },
  ]
  it('전체 / 지정 / 공종(세부·예전 값도 대분류로 맞춤)', () => {
    expect(countPopupTargets({ audience: 'all', target_trades: [], target_user_ids: [] }, users)).toBe(4)
    expect(countPopupTargets({ audience: 'selected', target_trades: [], target_user_ids: ['a', 'z'] }, users)).toBe(1)
    expect(countPopupTargets({ audience: 'trades', target_trades: ['하수구·막힘'], target_user_ids: [] }, users)).toBe(2)
    expect(countPopupTargets({ audience: 'trades', target_trades: ['보일러·난방'], target_user_ids: [] }, users)).toBe(1)
  })
})
