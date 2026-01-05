import formatClassName from '../../utils/formatClassName';

describe('formatClassName', () => {
  describe('special cases', () => {
    it('should handle FF suffix', () => {
      expect(formatClassName('INVENTION_INNOVATION_FF')).toBe('Invention & Innovation FF');
      expect(formatClassName('SOME_CLASS_FF')).toBe('Invention & Innovation FF');
    });

    it('should convert HONORS suffix to H', () => {
      expect(formatClassName('ENGLISH_HONORS')).toBe('English H');
      expect(formatClassName('MATH_HONORS')).toBe('Math H');
    });
  });

  describe('acronym handling', () => {
    it('should preserve common acronyms', () => {
      expect(formatClassName('AP_HISTORY')).toBe('AP History');
      expect(formatClassName('IB_ENGLISH')).toBe('IB English');
      expect(formatClassName('GT_MATH')).toBe('GT Math');
      expect(formatClassName('ELA_READING')).toBe('ELA Reading');
    });

    it('should preserve course-specific acronyms', () => {
      expect(formatClassName('CALCULUS_BC')).toBe('Calculus BC');
      expect(formatClassName('CALCULUS_AB')).toBe('Calculus AB');
      expect(formatClassName('CSA_PROGRAMMING')).toBe('CSA Programming');
      expect(formatClassName('CSP_PRINCIPLES')).toBe('CSP Principles');
    });

    it('should preserve technology acronyms', () => {
      expect(formatClassName('CS_FUNDAMENTALS')).toBe('CS Fundamentals');
      expect(formatClassName('AI_MACHINE_LEARNING')).toBe('AI Machine Learning');
      expect(formatClassName('ML_BASICS')).toBe('ML Basics');
      expect(formatClassName('CAD_DESIGN')).toBe('CAD Design');
    });

    it('should preserve other acronyms', () => {
      expect(formatClassName('US_HISTORY')).toBe('US History');
      expect(formatClassName('UK_LITERATURE')).toBe('UK Literature');
      expect(formatClassName('EU_STUDIES')).toBe('EU Studies');
      expect(formatClassName('PE_CLASS')).toBe('PE Class');
      expect(formatClassName('IT_FUNDAMENTALS')).toBe('IT Fundamentals');
      expect(formatClassName('STEM_ROBOTICS')).toBe('STEM Robotics');
      expect(formatClassName('CTE_PATHWAY')).toBe('CTE Pathway');
    });
  });

  describe('standard formatting', () => {
    it('should convert underscores to spaces', () => {
      expect(formatClassName('WORLD_HISTORY')).toBe('World History');
      expect(formatClassName('ALGEBRA_TWO')).toBe('Algebra Two');
    });

    it('should capitalize first letter and lowercase rest', () => {
      expect(formatClassName('ENGLISH')).toBe('English');
      expect(formatClassName('MATHEMATICS')).toBe('Mathematics');
    });

    it('should handle multiple underscores', () => {
      expect(formatClassName('INTRO_TO_COMPUTER_SCIENCE')).toBe('Intro To Computer Science');
    });

    it('should preserve Roman numerals (consecutive i characters)', () => {
      expect(formatClassName('ENGLISH_II')).toBe('English II');
      expect(formatClassName('SPANISH_III')).toBe('Spanish III');
    });
  });

  describe('edge cases', () => {
    it('should handle empty string', () => {
      expect(formatClassName('')).toBe('');
    });

    it('should handle single word', () => {
      expect(formatClassName('BIOLOGY')).toBe('Biology');
    });

    it('should handle already formatted input', () => {
      expect(formatClassName('AP')).toBe('AP');
    });
  });
});
