import {
  averageSemesterGPA,
  formatGPAValue,
  isFiniteGPA,
  shouldShowGPALogin,
} from '@/lib/utils/gpa-values';

describe('GPA value semantics', () => {
  it('preserves a real zero in display and semester averages', () => {
    expect(formatGPAValue(0)).toBe('0.00');
    expect(isFiniteGPA({ unweighted: 0, weighted: 0 })).toBe(true);
    expect(averageSemesterGPA(
      { unweighted: 0, weighted: 0 },
      { unweighted: 100, weighted: 110 }
    )).toEqual({ unweighted: 50, weighted: 55 });
  });

  it('rejects missing and non-finite values', () => {
    expect(formatGPAValue(Number.NaN)).toBe('--');
    expect(isFiniteGPA({ unweighted: Number.NaN, weighted: 0 })).toBe(false);
    expect(averageSemesterGPA(undefined, undefined)).toBeNull();
  });

  it('keeps the selector reachable when another manual year exists offline', () => {
    expect(shouldShowGPALogin({
      checkedCredentials: true,
      hasCredentials: false,
      loadingCourses: false,
      hasCourseSnapshot: false,
      manualYearCount: 1,
    })).toBe(false);
  });
});
