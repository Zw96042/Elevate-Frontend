import { DataService } from '@/lib/services';

jest.mock('@react-native-async-storage/async-storage', () =>
  require('@react-native-async-storage/async-storage/jest/async-storage-mock')
);

describe('unified academic score validation', () => {
  it('keeps zero but drops non-finite historical score strings', () => {
    const [course] = DataService.transformCombinedData({
      current: {
        grade: 11,
        courses: {
          Biology: { terms: '1 - 4', rc1: '0', rc2: 'NaN', sm1: 'Infinity' },
        },
      },
    });

    expect(course.currentScores).toEqual([{ bucket: 'Q1', score: 0 }]);
    expect(course.historicalGrades).toEqual(expect.objectContaining({
      rc1: '0',
      rc2: undefined,
      sm1: undefined,
    }));
  });
});
