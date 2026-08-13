import { hasPostedGrade, parseEditablePoints } from '@/lib/utils/grade-values';

describe('ClassCard posted-grade semantics', () => {
  it('preserves a legitimate posted zero', () => {
    expect(hasPostedGrade(0)).toBe(true);
    expect(hasPostedGrade(100)).toBe(true);
  });

  it('rejects missing and non-finite values', () => {
    expect(hasPostedGrade(undefined)).toBe(false);
    expect(hasPostedGrade(Number.NaN)).toBe(false);
    expect(hasPostedGrade(Number.POSITIVE_INFINITY)).toBe(false);
  });

  it('rejects non-finite, negative, oversized, and zero-denominator edits', () => {
    expect(parseEditablePoints('Infinity')).toBeNull();
    expect(parseEditablePoints('-1')).toBeNull();
    expect(parseEditablePoints('1000001')).toBeNull();
    expect(parseEditablePoints('0', false)).toBeNull();
    expect(parseEditablePoints('0.009', false)).toBeNull();
    expect(parseEditablePoints('0')).toBe(0);
    expect(parseEditablePoints('0.01', false)).toBe(0.01);
    expect(parseEditablePoints('25.5', false)).toBe(25.5);
  });
});
