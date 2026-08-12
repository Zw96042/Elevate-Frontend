import { UnifiedGPAManager } from '@/lib/unifiedGpaManager';

jest.mock('@/lib/services', () => ({ DataService: {} }));
jest.mock('@/lib/utils/account-scoped-storage', () => ({
  getAccountScopedItem: jest.fn(),
}));

describe('GPA calculation', () => {
  it('counts a posted numeric zero instead of treating it as missing', () => {
    const result = UnifiedGPAManager.calculateCurrentGradeGPA([{
      courseName: 'Biology',
      semester: 'both',
      termLength: '1 - 4',
      currentScores: [],
      historicalGrades: { sm1: 0 as any },
    } as any]);

    expect(result.SM1).toEqual({ unweighted: 0, weighted: 0 });
  });

  it('does not let non-finite strings poison an average', () => {
    const result = UnifiedGPAManager.calculateCurrentGradeGPA([{
      courseName: 'Biology',
      semester: 'both',
      termLength: '1 - 4',
      currentScores: [],
      historicalGrades: { sm1: 'Infinity' },
    } as any]);

    expect(result.SM1).toBeUndefined();
  });
});
