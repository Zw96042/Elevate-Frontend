import { getCurrentTerm, getTermForDate, getCurrentAcademicYear } from '@/utils/academicCalendar';

describe('Academic Calendar', () => {
  describe('getCurrentAcademicYear', () => {
    it('should return current year for August-December', () => {
      const augustDate = new Date(2025, 7, 15); // August 15, 2025
      const originalDate = Date;
      global.Date = class extends originalDate {
        constructor() {
          super();
          return augustDate;
        }
      } as any;
      
      expect(getCurrentAcademicYear()).toBe(2025);
      global.Date = originalDate;
    });

    it('should return previous year for January-July', () => {
      const januaryDate = new Date(2026, 0, 5); // January 5, 2026
      const originalDate = Date;
      global.Date = class extends originalDate {
        constructor() {
          super();
          return januaryDate;
        }
      } as any;
      
      expect(getCurrentAcademicYear()).toBe(2025);
      global.Date = originalDate;
    });
  });

  describe('getCurrentTerm', () => {
    it('should detect Q1 for August-October dates', () => {
      // Mock current date to September 15, 2025
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2025, 8, 15)); // September 15, 2025
      
      expect(getCurrentTerm()).toBe('Q1 Grades');
      
      jest.useRealTimers();
    });

    it('should detect Q2 for late October-December dates', () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2025, 10, 15)); // November 15, 2025
      
      expect(getCurrentTerm()).toBe('Q2 Grades');
      
      jest.useRealTimers();
    });

    it('should detect SM1 for late December-early January dates', () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2026, 0, 5)); // January 5, 2026
      
      expect(getCurrentTerm()).toBe('SM1 Grade');
      
      jest.useRealTimers();
    });

    it('should detect Q3 for mid January-March dates', () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2026, 1, 15)); // February 15, 2026
      
      expect(getCurrentTerm()).toBe('Q3 Grades');
      
      jest.useRealTimers();
    });

    it('should detect Q4 for late March-May dates', () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2026, 3, 15)); // April 15, 2026
      
      expect(getCurrentTerm()).toBe('Q4 Grades');
      
      jest.useRealTimers();
    });

    it('should detect SM2 for June-July dates', () => {
      jest.useFakeTimers();
      jest.setSystemTime(new Date(2026, 5, 15)); // June 15, 2026
      
      expect(getCurrentTerm()).toBe('SM2 Grades');
      
      jest.useRealTimers();
    });
  });

  describe('getTermForDate', () => {
    it('should correctly identify term for specific dates', () => {
      expect(getTermForDate(new Date(2025, 8, 15))).toBe('Q1 Grades'); // Sept 15, 2025
      expect(getTermForDate(new Date(2025, 10, 15))).toBe('Q2 Grades'); // Nov 15, 2025
      expect(getTermForDate(new Date(2026, 0, 5))).toBe('SM1 Grade'); // Jan 5, 2026
      expect(getTermForDate(new Date(2026, 1, 15))).toBe('Q3 Grades'); // Feb 15, 2026
      expect(getTermForDate(new Date(2026, 3, 15))).toBe('Q4 Grades'); // Apr 15, 2026
      expect(getTermForDate(new Date(2026, 5, 15))).toBe('SM2 Grades'); // Jun 15, 2026
    });
  });
});
