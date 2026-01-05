import { getCourseLevel, calculateTermGPAs, SavedClass, GPAResult } from '../../utils/gpaCalculator';

describe('gpaCalculator', () => {
  describe('getCourseLevel', () => {
    describe('AP courses', () => {
      it('should detect explicit AP courses', () => {
        expect(getCourseLevel('AP Chemistry')).toBe('AP');
        expect(getCourseLevel('AP US History')).toBe('AP');
        expect(getCourseLevel('AP Calculus BC')).toBe('AP');
        expect(getCourseLevel('ap physics')).toBe('AP');
      });

      it('should detect AP exception courses', () => {
        expect(getCourseLevel('Multivariable Calculus')).toBe('AP');
        expect(getCourseLevel('Linear Algebra')).toBe('AP');
        expect(getCourseLevel('Computer Science 2')).toBe('AP');
        expect(getCourseLevel('Computer Science II')).toBe('AP');
        expect(getCourseLevel('Organic Chemistry')).toBe('AP');
      });

      it('should not match partial AP exception names', () => {
        // "Computer Science 1" should NOT match "Computer Science 2" exception
        expect(getCourseLevel('Computer Science 1')).toBe('Regular');
        expect(getCourseLevel('Computer Science I')).toBe('Regular');
      });
    });

    describe('Honors courses', () => {
      it('should detect explicit Honors courses', () => {
        expect(getCourseLevel('Honors English')).toBe('Honors');
        expect(getCourseLevel('English Honors')).toBe('Honors');
        expect(getCourseLevel('honors algebra')).toBe('Honors');
      });

      it('should detect Honors exception courses', () => {
        expect(getCourseLevel('Anatomy & Physiology')).toBe('Honors');
        expect(getCourseLevel('Anatomy and Physiology')).toBe('Honors');
        expect(getCourseLevel('Robotics 2')).toBe('Honors');
        expect(getCourseLevel('Robotics II')).toBe('Honors');
        expect(getCourseLevel('Swift Coding')).toBe('Honors');
        expect(getCourseLevel('Engineering')).toBe('Honors');
      });

      it('should not match partial Honors exception names', () => {
        // "Robotics 1" should NOT match "Robotics 2" exception
        expect(getCourseLevel('Robotics 1')).toBe('Regular');
        expect(getCourseLevel('Robotics I')).toBe('Regular');
      });
    });

    describe('Regular courses', () => {
      it('should return Regular for standard courses', () => {
        expect(getCourseLevel('English 1')).toBe('Regular');
        expect(getCourseLevel('Algebra 2')).toBe('Regular');
        expect(getCourseLevel('World History')).toBe('Regular');
        expect(getCourseLevel('Physical Education')).toBe('Regular');
      });

      it('should handle edge cases', () => {
        expect(getCourseLevel('')).toBe('Regular');
        expect(getCourseLevel('   ')).toBe('Regular');
      });
    });
  });

  describe('calculateTermGPAs', () => {
    it('should calculate GPAs for all terms', () => {
      const classes: SavedClass[] = [
        { className: 'AP Chemistry', sm1: 95, sm2: 92, rc1: 94, rc2: 96, rc3: 91, rc4: 93 },
        { className: 'Honors English', sm1: 88, sm2: 90, rc1: 87, rc2: 89, rc3: 89, rc4: 91 },
        { className: 'Algebra 2', sm1: 85, sm2: 87, rc1: 84, rc2: 86, rc3: 86, rc4: 88 },
      ];

      const result = calculateTermGPAs(classes);

      // Check that all term keys exist
      expect(result).toHaveProperty('SM1');
      expect(result).toHaveProperty('SM2');
      expect(result).toHaveProperty('RC1');
      expect(result).toHaveProperty('RC2');
      expect(result).toHaveProperty('RC3');
      expect(result).toHaveProperty('RC4');
    });

    it('should apply correct weights for AP courses (+10)', () => {
      const classes: SavedClass[] = [
        { className: 'AP Chemistry', sm1: 90, sm2: 90 },
      ];

      const result = calculateTermGPAs(classes);

      expect(result.SM1.unweighted).toBe(90);
      expect(result.SM1.weighted).toBe(100); // 90 + 10
    });

    it('should apply correct weights for Honors courses (+5)', () => {
      const classes: SavedClass[] = [
        { className: 'Honors English', sm1: 90, sm2: 90 },
      ];

      const result = calculateTermGPAs(classes);

      expect(result.SM1.unweighted).toBe(90);
      expect(result.SM1.weighted).toBe(95); // 90 + 5
    });

    it('should cap weighted grades at 110', () => {
      const classes: SavedClass[] = [
        { className: 'AP Chemistry', sm1: 100, sm2: 100 },
      ];

      const result = calculateTermGPAs(classes);

      expect(result.SM1.unweighted).toBe(100);
      expect(result.SM1.weighted).toBe(110); // 100 + 10, capped at 110
    });

    it('should handle empty class array', () => {
      const result = calculateTermGPAs([]);

      expect(result.SM1.unweighted).toBe(0);
      expect(result.SM1.weighted).toBe(0);
    });

    it('should calculate semester averages from RC grades when SM grades are missing', () => {
      const classes: SavedClass[] = [
        { className: 'Regular Class', sm1: -1, sm2: -1, rc1: 80, rc2: 90, rc3: 85, rc4: 95 },
      ];

      const result = calculateTermGPAs(classes);

      // SM1 should be (80 + 90) / 2 = 85
      expect(result.SM1.unweighted).toBe(85);
      // SM2 should be (85 + 95) / 2 = 90
      expect(result.SM2.unweighted).toBe(90);
    });

    it('should round RC grades before calculating semester averages', () => {
      const classes: SavedClass[] = [
        { className: 'Regular Class', sm1: -1, sm2: -1, rc1: 89.4, rc2: 90.6, rc3: 85.5, rc4: 94.4 },
      ];

      const result = calculateTermGPAs(classes);

      // RC1 rounds to 89, RC2 rounds to 91 -> SM1 = (89 + 91) / 2 = 90
      expect(result.SM1.unweighted).toBe(90);
      // RC3 rounds to 86, RC4 rounds to 94 -> SM2 = (86 + 94) / 2 = 90
      expect(result.SM2.unweighted).toBe(90);
    });

    it('should skip classes with invalid className', () => {
      const classes: SavedClass[] = [
        { className: '', sm1: 90, sm2: 90 },
        { className: 'Valid Class', sm1: 80, sm2: 80 },
      ];

      const result = calculateTermGPAs(classes);

      // Should only include the valid class
      expect(result.SM1.unweighted).toBe(80);
    });

    it('should handle multiple classes with different levels', () => {
      const classes: SavedClass[] = [
        { className: 'AP Chemistry', sm1: 90, sm2: 90 },
        { className: 'Honors English', sm1: 90, sm2: 90 },
        { className: 'Regular Math', sm1: 90, sm2: 90 },
      ];

      const result = calculateTermGPAs(classes);

      // Unweighted: (90 + 90 + 90) / 3 = 90
      expect(result.SM1.unweighted).toBe(90);
      // Weighted: (100 + 95 + 90) / 3 = 95
      expect(result.SM1.weighted).toBe(95);
    });
  });
});
