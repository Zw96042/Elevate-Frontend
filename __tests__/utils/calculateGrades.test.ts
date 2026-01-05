import { calculateGradeSummary } from '../../utils/calculateGrades';

type Assignment = {
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
  meta?: { type: 'missing' | 'noCount' | 'absent'; note: string }[];
};

describe('calculateGrades', () => {
  describe('calculateGradeSummary', () => {
    const defaultCategoryWeights = {
      'Tests': 0.4,
      'Quizzes': 0.3,
      'Homework': 0.2,
      'Participation': 0.1,
    };

    const createAssignment = (overrides: Partial<Assignment> = {}): Assignment => ({
      className: 'Test Class',
      name: 'Test Assignment',
      term: 'Q1',
      category: 'Tests',
      grade: '90',
      outOf: 100,
      dueDate: '2024-01-15',
      artificial: false,
      ...overrides,
    });

    it('should calculate basic grade summary', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Tests', grade: '90', outOf: 100 }),
        createAssignment({ category: 'Tests', grade: '80', outOf: 100 }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      expect(result.categories['Tests']).toBeDefined();
      expect(result.categories['Tests'].rawPoints).toBe(170);
      expect(result.categories['Tests'].rawTotal).toBe(200);
      expect(result.categories['Tests'].average).toBe(85);
    });

    it('should calculate weighted course total', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Tests', grade: '100', outOf: 100 }),
        createAssignment({ category: 'Quizzes', grade: '80', outOf: 100 }),
        createAssignment({ category: 'Homework', grade: '90', outOf: 100 }),
        createAssignment({ category: 'Participation', grade: '100', outOf: 100 }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      // Tests: 100% * 0.4 = 40
      // Quizzes: 80% * 0.3 = 24
      // Homework: 90% * 0.2 = 18
      // Participation: 100% * 0.1 = 10
      // Total: 92
      expect(parseFloat(result.courseTotal)).toBe(92);
    });

    it('should exclude "noCount" assignments from calculations', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Tests', grade: '100', outOf: 100 }),
        createAssignment({
          category: 'Tests',
          grade: '0',
          outOf: 100,
          meta: [{ type: 'noCount', note: 'Does not count' }],
        }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      // Only the first assignment should count
      expect(result.categories['Tests'].rawPoints).toBe(100);
      expect(result.categories['Tests'].rawTotal).toBe(100);
      expect(result.categories['Tests'].average).toBe(100);
    });

    it('should handle empty assignments array', () => {
      const result = calculateGradeSummary([], defaultCategoryWeights);

      expect(result.courseTotal).toBe('*');
      expect(Object.keys(result.categories)).toHaveLength(0);
    });

    it('should handle assignments with zero outOf', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Tests', grade: '0', outOf: 0 }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      expect(result.categories['Tests'].average).toBe(0);
    });

    it('should calculate multiple categories correctly', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Tests', grade: '90', outOf: 100 }),
        createAssignment({ category: 'Quizzes', grade: '85', outOf: 100 }),
        createAssignment({ category: 'Homework', grade: '95', outOf: 100 }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      expect(result.categories['Tests'].average).toBe(90);
      expect(result.categories['Quizzes'].average).toBe(85);
      expect(result.categories['Homework'].average).toBe(95);
    });

    it('should handle missing category weights', () => {
      const assignments: Assignment[] = [
        createAssignment({ category: 'Unknown Category', grade: '90', outOf: 100 }),
      ];

      const result = calculateGradeSummary(assignments, defaultCategoryWeights);

      expect(result.categories['Unknown Category']).toBeDefined();
      expect(result.categories['Unknown Category'].weight).toBe(0);
    });

    describe('semester grade calculations', () => {
      it('should calculate SM1 from Q1 and Q2 grades', () => {
        const assignments: Assignment[] = [];
        const termMap = {
          'Q1 Grades': { total: 89.5 },
          'Q2 Grades': { total: 92.3 },
        };

        const result = calculateGradeSummary(
          assignments,
          defaultCategoryWeights,
          termMap,
          'SM1 Grade'
        );

        // RC1 = round(89.5) = 90, RC2 = round(92.3) = 92
        // SM1 = (90 + 92) / 2 = 91
        expect(result.rcGrades?.rc1).toBe(90);
        expect(result.rcGrades?.rc2).toBe(92);
        expect(result.semesterAverages?.sm1).toBe(91);
      });

      it('should calculate SM1 with final exam grade', () => {
        const assignments: Assignment[] = [];
        const termMap = {
          'Q1 Grades': { total: 90 },
          'Q2 Grades': { total: 90 },
        };

        const result = calculateGradeSummary(
          assignments,
          defaultCategoryWeights,
          termMap,
          'SM1 Grade',
          100 // Final exam grade
        );

        // RC1 = 90, RC2 = 90
        // SM1 = (90 * 0.4) + (90 * 0.4) + (100 * 0.2) = 36 + 36 + 20 = 92
        expect(result.semesterAverages?.sm1).toBe(92);
      });

      it('should calculate SM2 from Q3 and Q4 grades', () => {
        const assignments: Assignment[] = [];
        const termMap = {
          'Q3 Grades': { total: 85.4 },
          'Q4 Grades': { total: 88.6 },
        };

        const result = calculateGradeSummary(
          assignments,
          defaultCategoryWeights,
          termMap,
          'SM2 Grades'
        );

        // RC3 = round(85.4) = 85, RC4 = round(88.6) = 89
        // SM2 = (85 + 89) / 2 = 87
        expect(result.rcGrades?.rc3).toBe(85);
        expect(result.rcGrades?.rc4).toBe(89);
        expect(result.semesterAverages?.sm2).toBe(87);
      });

      it('should handle missing Q2 grade for SM1', () => {
        const assignments: Assignment[] = [];
        const termMap = {
          'Q1 Grades': { total: 90 },
        };

        const result = calculateGradeSummary(
          assignments,
          defaultCategoryWeights,
          termMap,
          'SM1 Grade'
        );

        expect(result.rcGrades?.rc1).toBe(90);
        expect(result.rcGrades?.rc2).toBeUndefined();
        expect(result.semesterAverages?.sm1).toBe(90);
      });
    });
  });
});
