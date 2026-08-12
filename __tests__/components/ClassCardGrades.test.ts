import { hasPostedGrade } from '@/lib/utils/grade-values';

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
});
