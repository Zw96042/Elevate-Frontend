import {
  calculateSemesterAverages,
  updateCourseWithSemesterAverages,
  updateCoursesWithSemesterAverages,
} from '../../utils/semesterAverageCalculator';

describe('semesterAverageCalculator', () => {
  describe('calculateSemesterAverages', () => {
    describe('SM1 calculation (RC1 + RC2)', () => {
      it('should calculate SM1 from RC1 and RC2', () => {
        const result = calculateSemesterAverages(90, 92, null, null);
        expect(result.sm1).toBe(91); // (90 + 92) / 2
        expect(result.sm2).toBeNull();
      });

      it('should round RC grades before averaging', () => {
        const result = calculateSemesterAverages(89.4, 90.6, null, null);
        // RC1 rounds to 89, RC2 rounds to 91
        expect(result.sm1).toBe(90); // (89 + 91) / 2
      });

      it('should use RC1 alone if RC2 is missing', () => {
        const result = calculateSemesterAverages(90, null, null, null);
        expect(result.sm1).toBe(90);
      });

      it('should use RC2 alone if RC1 is missing', () => {
        const result = calculateSemesterAverages(null, 88, null, null);
        expect(result.sm1).toBe(88);
      });
    });

    describe('SM2 calculation (RC3 + RC4)', () => {
      it('should calculate SM2 from RC3 and RC4', () => {
        const result = calculateSemesterAverages(null, null, 85, 89);
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBe(87); // (85 + 89) / 2
      });

      it('should round RC grades before averaging', () => {
        const result = calculateSemesterAverages(null, null, 85.4, 88.6);
        // RC3 rounds to 85, RC4 rounds to 89
        expect(result.sm2).toBe(87); // (85 + 89) / 2
      });

      it('should use RC3 alone if RC4 is missing', () => {
        const result = calculateSemesterAverages(null, null, 85, null);
        expect(result.sm2).toBe(85);
      });

      it('should use RC4 alone if RC3 is missing', () => {
        const result = calculateSemesterAverages(null, null, null, 92);
        expect(result.sm2).toBe(92);
      });
    });

    describe('full year calculation', () => {
      it('should calculate both SM1 and SM2', () => {
        const result = calculateSemesterAverages(90, 92, 85, 89);
        expect(result.sm1).toBe(91);
        expect(result.sm2).toBe(87);
      });
    });

    describe('edge cases', () => {
      it('should handle string grades', () => {
        const result = calculateSemesterAverages('90', '92', '85', '89');
        expect(result.sm1).toBe(91);
        expect(result.sm2).toBe(87);
      });

      it('should handle empty strings as null', () => {
        const result = calculateSemesterAverages('', '', '', '');
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBeNull();
      });

      it('should handle "P" (Pass) grades as null', () => {
        const result = calculateSemesterAverages('P', 'P', 'P', 'P');
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBeNull();
      });

      it('should handle "X" grades as null', () => {
        const result = calculateSemesterAverages('X', 'X', 'X', 'X');
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBeNull();
      });

      it('should handle undefined values', () => {
        const result = calculateSemesterAverages(undefined, undefined, undefined, undefined);
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBeNull();
      });

      it('should handle all null values', () => {
        const result = calculateSemesterAverages(null, null, null, null);
        expect(result.sm1).toBeNull();
        expect(result.sm2).toBeNull();
      });
    });
  });

  describe('updateCourseWithSemesterAverages', () => {
    it('should add calculated semester averages to course data', () => {
      const courseData = {
        rc1: 90,
        rc2: 92,
        rc3: 85,
        rc4: 89,
        sm1: null as number | null,
        sm2: null as number | null,
      };

      const result = updateCourseWithSemesterAverages(courseData);

      expect(result.sm1).toBe(91);
      expect(result.sm2).toBe(87);
      expect(result.rc1).toBe(90);
      expect(result.rc2).toBe(92);
    });

    it('should preserve other course properties', () => {
      const courseData = {
        rc1: 90,
        rc2: 92,
        rc3: 85,
        rc4: 89,
        sm1: null as number | null,
        sm2: null as number | null,
        courseName: 'AP Chemistry',
        credits: 1,
      };

      const result = updateCourseWithSemesterAverages(courseData);

      expect(result.courseName).toBe('AP Chemistry');
      expect(result.credits).toBe(1);
    });
  });

  describe('updateCoursesWithSemesterAverages', () => {
    it('should update multiple courses', () => {
      const courses = [
        { rc1: 90, rc2: 92, rc3: 85, rc4: 89, sm1: null as number | null, sm2: null as number | null },
        { rc1: 80, rc2: 84, rc3: 78, rc4: 82, sm1: null as number | null, sm2: null as number | null },
      ];

      const result = updateCoursesWithSemesterAverages(courses);

      expect(result[0].sm1).toBe(91);
      expect(result[0].sm2).toBe(87);
      expect(result[1].sm1).toBe(82);
      expect(result[1].sm2).toBe(80);
    });

    it('should handle empty array', () => {
      const result = updateCoursesWithSemesterAverages([]);
      expect(result).toEqual([]);
    });
  });
});
