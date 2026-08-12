import { shouldBlockCourseError, transformCourseData } from '@/lib/utils/course-card-transform';

describe('course-card source association', () => {
  it('keeps the original live course after dropping an earlier incomplete row', () => {
    const historyOnly = {
      courseName: 'History Only', semester: 'both', termLength: '1-4',
      currentScores: [], historicalGrades: {},
    } as any;
    const live = {
      courseName: 'Biology', stuId: 'student', corNumId: '42', section: '1', gbId: 'GB',
      semester: 'both', termLength: '1-4', currentScores: [{ bucket: 'SEM 1', score: 91 }],
      historicalGrades: {},
    } as any;

    const transformed = transformCourseData([historyOnly, live]);

    expect(transformed).toHaveLength(1);
    expect(transformed[0].courseData).toBe(live);
    expect(transformed[0].s1.total).toBe(91);
  });

  it('keeps a last-known-good course snapshot visible after refresh failure', () => {
    expect(shouldBlockCourseError({
      error: 'Network request failed',
      localError: null,
      loading: false,
      checkedCredentials: true,
      hasCourseSnapshot: true,
    })).toBe(false);
    expect(shouldBlockCourseError({
      error: 'Network request failed',
      localError: null,
      loading: false,
      checkedCredentials: true,
      hasCourseSnapshot: false,
    })).toBe(true);
  });
});
