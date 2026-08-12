import {
  loadManualCoursesForSelection,
  mergeAcademicCourses,
} from '@/lib/utils/manual-gpa';
import { getAccountScopedItem } from '@/lib/utils/account-scoped-storage';

jest.mock('@/lib/utils/account-scoped-storage', () => ({
  getAccountScopedItem: jest.fn(),
}));

const getItem = getAccountScopedItem as jest.MockedFunction<typeof getAccountScopedItem>;

describe('manual GPA history', () => {
  beforeEach(() => jest.clearAllMocks());

  it('provides a manual-only historical year to GPA calculations', async () => {
    getItem.mockImplementation(async key => key === 'savedClasses-Freshman'
      ? JSON.stringify([{ className: 'AP Biology', sm1: 94, sm2: 96 }])
      : null);

    const manual = await loadManualCoursesForSelection('Freshman');
    const merged = mergeAcademicCourses([], manual);

    expect(merged).toHaveLength(1);
    expect(merged[0]).toEqual(expect.objectContaining({
      courseName: 'AP Biology',
      gradeYear: 9,
      historicalGrades: expect.objectContaining({ sm1: '94', sm2: '96' }),
    }));
  });

  it('loads every saved year for All Time without duplicating a Skyward course', async () => {
    getItem.mockImplementation(async key => key === 'savedClasses-Freshman'
      ? JSON.stringify([{ name: 'Biology', grades: { sm1: '90', sm2: '92' } }])
      : key === 'savedClasses-Sophomore'
        ? JSON.stringify([{ className: 'Geometry', sm1: 88, sm2: 91 }])
        : null);
    const manual = await loadManualCoursesForSelection('All Time');
    const server = [{
      courseName: 'Biology', semester: 'both', termLength: '1 - 4', gradeYear: 9,
      currentScores: [], historicalGrades: { sm1: '93' },
    }] as any;

    expect(mergeAcademicCourses(server, manual).map(course => course.courseName)).toEqual([
      'Biology', 'Geometry',
    ]);
  });
});
