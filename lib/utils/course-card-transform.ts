import { UnifiedCourseData } from '../services';

const DEFAULT_CATEGORIES = {
  names: ['Daily', 'Labs', 'Major'],
  weights: [10, 30, 60],
};

export function transformCourseData(unifiedCourses: UnifiedCourseData[]) {
  return unifiedCourses
    .filter(course => Boolean(
      course.courseName && course.stuId && course.corNumId && course.section && course.gbId
    ))
    .map(course => {
      const scoreMap: Record<string, number> = {};
      course.currentScores?.forEach(score => {
        if (score.bucket) scoreMap[score.bucket.toLowerCase()] = score.score;
      });

      const getScore = (historicalKey: string, ...currentKeys: string[]): number | string => {
        for (const key of currentKeys) {
          const value = scoreMap[key];
          if (value !== undefined && value !== null) return value;
        }
        const historical = course.historicalGrades[
          historicalKey as keyof UnifiedCourseData['historicalGrades']
        ];
        if (historical !== undefined && historical !== '' && Number.isFinite(Number(historical))) {
          return Number(historical);
        }
        return '--';
      };

      return {
        name: course.courseName.toUpperCase().replace(/\s+/g, '_'),
        teacher: course.instructor?.toUpperCase().replace(/\s+/g, '_') || 'UNKNOWN_INSTRUCTOR',
        corNumId: course.corNumId || course.courseId || '',
        stuId: course.stuId,
        section: course.section,
        gbId: course.gbId,
        period: course.period,
        semester: course.semester,
        courseData: course,
        t1: { categories: DEFAULT_CATEGORIES, total: getScore('rc1', 'term 3', 'quarter 1', 'rc1') },
        t2: { categories: DEFAULT_CATEGORIES, total: getScore('rc2', 'term 6', 'quarter 2', 'rc2') },
        s1: { categories: DEFAULT_CATEGORIES, total: getScore('sm1', 'sem 1', 'semester 1', 'sm1') },
        t3: { categories: DEFAULT_CATEGORIES, total: getScore('rc3', 'term 9', 'quarter 3', 'rc3') },
        t4: { categories: DEFAULT_CATEGORIES, total: getScore('rc4', 'term 12', 'quarter 4', 'rc4') },
        s2: { categories: DEFAULT_CATEGORIES, total: getScore('sm2', 'sem 2', 'semester 2', 'sm2') },
      };
    });
}

export function shouldBlockCourseError(input: {
  error: string | null;
  localError: string | null;
  loading: boolean;
  checkedCredentials: boolean;
  hasCourseSnapshot: boolean;
}): boolean {
  const message = input.localError ?? input.error;
  if (!message || input.loading || !input.checkedCredentials || input.hasCourseSnapshot) return false;
  return !message.includes('credentials') && !message.includes('Missing credentials');
}
