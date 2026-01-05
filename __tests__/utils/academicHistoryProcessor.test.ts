import { processAcademicHistory, getCurrentGradeLevel } from '../../utils/academicHistoryProcessor';

describe('academicHistoryProcessor', () => {
  const createCourseData = (overrides = {}) => ({
    terms: '1 - 4',
    finalGrade: '90',
    sm1: '89',
    sm2: '91',
    pr1: '88',
    pr2: '89',
    pr3: '90',
    pr4: '91',
    pr5: '90',
    pr6: '91',
    pr7: '92',
    pr8: '93',
    rc1: '89',
    rc2: '90',
    rc3: '91',
    rc4: '92',
    ex1: '',
    ex2: '',
    ...overrides,
  });

  const createAcademicData = () => ({
    '2023-2024': {
      grade: 11,
      courses: {
        'AP Chemistry': createCourseData({ finalGrade: '95' }),
        'Honors English': createCourseData({ finalGrade: '92' }),
        'Algebra 2': createCourseData({ finalGrade: '88' }),
      },
    },
    '2022-2023': {
      grade: 10,
      courses: {
        'Biology': createCourseData({ finalGrade: '90' }),
        'English 2': createCourseData({ finalGrade: '87' }),
      },
    },
  });

  describe('processAcademicHistory', () => {
    it('should return GPA data for all terms', () => {
      const academicData = createAcademicData();
      const result = processAcademicHistory(academicData);

      expect(result).toHaveProperty('PR1');
      expect(result).toHaveProperty('PR2');
      expect(result).toHaveProperty('RC1');
      expect(result).toHaveProperty('RC2');
      expect(result).toHaveProperty('SM1');
      expect(result).toHaveProperty('SM2');
    });

    it('should return weighted and unweighted GPAs', () => {
      const academicData = createAcademicData();
      const result = processAcademicHistory(academicData);

      expect(result.SM1).toHaveProperty('weighted');
      expect(result.SM1).toHaveProperty('unweighted');
      expect(typeof result.SM1.weighted).toBe('number');
      expect(typeof result.SM1.unweighted).toBe('number');
    });

    it('should filter by target grade level', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'AP Chemistry': createCourseData({ rc1: '95', rc2: '95', sm1: '95', sm2: '95' }),
          },
        },
        '2022-2023': {
          grade: 10,
          courses: {
            'Biology': createCourseData({ rc1: '80', rc2: '80', sm1: '80', sm2: '80' }),
          },
        },
      };
      
      // Only grade 11 courses
      const result11 = processAcademicHistory(academicData, 11);
      
      // Only grade 10 courses
      const result10 = processAcademicHistory(academicData, 10);

      // Results should be different since different courses are included
      expect(result11.SM1.unweighted).toBe(95);
      expect(result10.SM1.unweighted).toBe(80);
    });

    it('should exclude grades below 9', () => {
      const academicData = {
        ...createAcademicData(),
        '2020-2021': {
          grade: 8,
          courses: {
            'Middle School Math': createCourseData({ finalGrade: '100' }),
          },
        },
      };

      const result = processAcademicHistory(academicData);
      
      // Grade 8 courses should not affect the GPA
      // If they were included, the GPA would be higher due to the 100 grade
      expect(result.SM1.unweighted).toBeLessThan(100);
    });

    it('should exclude courses with "P" final grade', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'AP Chemistry': createCourseData({ finalGrade: '90', rc1: '90', rc2: '90', sm1: '90', sm2: '90' }),
            'Pass/Fail Course': createCourseData({ finalGrade: 'P', rc1: '100', rc2: '100', sm1: '100', sm2: '100' }),
          },
        },
      };

      const result = processAcademicHistory(academicData);
      
      // Only AP Chemistry should be included (Pass/Fail excluded)
      // AP Chemistry gets +10 weight, so weighted should be 100
      expect(result.SM1.unweighted).toBe(90);
      expect(result.SM1.weighted).toBe(100);
    });

    it('should handle empty academic data', () => {
      const result = processAcademicHistory({});

      expect(result.SM1.unweighted).toBe(0);
      expect(result.SM1.weighted).toBe(0);
    });

    it('should apply AP weight (+10) correctly', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'AP Chemistry': createCourseData({ 
              rc1: '90', 
              rc2: '90', 
              sm1: '90',
              sm2: '90',
            }),
          },
        },
      };

      const result = processAcademicHistory(academicData);

      expect(result.SM1.unweighted).toBe(90);
      expect(result.SM1.weighted).toBe(100); // 90 + 10
    });

    it('should apply Honors weight (+5) correctly', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'Honors English': createCourseData({ 
              rc1: '90', 
              rc2: '90', 
              sm1: '90',
              sm2: '90',
            }),
          },
        },
      };

      const result = processAcademicHistory(academicData);

      expect(result.SM1.unweighted).toBe(90);
      expect(result.SM1.weighted).toBe(95); // 90 + 5
    });

    it('should cap weighted grades at 110', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'AP Chemistry': createCourseData({ 
              rc1: '105', 
              rc2: '105', 
              sm1: '105',
              sm2: '105',
            }),
          },
        },
      };

      const result = processAcademicHistory(academicData);

      expect(result.SM1.unweighted).toBe(105);
      expect(result.SM1.weighted).toBe(110); // Capped at 110
    });

    it('should calculate semester averages from RC grades when SM is missing', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {
            'Regular Class': createCourseData({ 
              rc1: '80', 
              rc2: '90', 
              rc3: '85',
              rc4: '95',
              sm1: '',
              sm2: '',
            }),
          },
        },
      };

      const result = processAcademicHistory(academicData);

      // SM1 = (80 + 90) / 2 = 85
      expect(result.SM1.unweighted).toBe(85);
      // SM2 = (85 + 95) / 2 = 90
      expect(result.SM2.unweighted).toBe(90);
    });
  });

  describe('getCurrentGradeLevel', () => {
    it('should return the highest grade level', () => {
      const academicData = createAcademicData();
      const result = getCurrentGradeLevel(academicData);

      expect(result).toBe(11);
    });

    it('should return 9 for empty data', () => {
      const result = getCurrentGradeLevel({});
      expect(result).toBe(9);
    });

    it('should ignore grades below 9', () => {
      const academicData = {
        '2020-2021': {
          grade: 8,
          courses: {},
        },
        '2021-2022': {
          grade: 9,
          courses: {},
        },
      };

      const result = getCurrentGradeLevel(academicData);
      expect(result).toBe(9);
    });

    it('should ignore grades above 12', () => {
      const academicData = {
        '2023-2024': {
          grade: 13,
          courses: {},
        },
        '2022-2023': {
          grade: 12,
          courses: {},
        },
      };

      const result = getCurrentGradeLevel(academicData);
      expect(result).toBe(12);
    });

    it('should ignore alt key', () => {
      const academicData = {
        '2023-2024': {
          grade: 11,
          courses: {},
        },
        alt: {
          grade: 99,
          courses: {},
        },
      };

      const result = getCurrentGradeLevel(academicData as any);
      expect(result).toBe(11);
    });
  });
});
