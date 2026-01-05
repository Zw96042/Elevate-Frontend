import {
  generateUniqueId,
  generateAssignmentId,
  ensureAssignmentId,
  ensureUniqueAssignmentIds,
  generateCourseId,
  ensureUniqueCourseIds,
} from '../../utils/uniqueId';

describe('uniqueId', () => {
  describe('generateUniqueId', () => {
    it('should generate a unique string', () => {
      const id1 = generateUniqueId();
      const id2 = generateUniqueId();

      expect(typeof id1).toBe('string');
      expect(id1).not.toBe(id2);
    });

    it('should contain timestamp and random parts', () => {
      const id = generateUniqueId();
      expect(id).toMatch(/^[a-z0-9]+-[a-z0-9]+$/);
    });
  });

  describe('generateAssignmentId', () => {
    const baseAssignment = {
      className: 'AP Chemistry',
      name: 'Chapter 1 Test',
      term: 'Q1',
      category: 'Tests',
      dueDate: '2024-01-15',
      grade: '95',
      outOf: 100,
    };

    it('should generate consistent IDs for same assignment', () => {
      const id1 = generateAssignmentId(baseAssignment);
      const id2 = generateAssignmentId(baseAssignment);

      expect(id1).toBe(id2);
    });

    it('should generate different IDs for different assignments', () => {
      const id1 = generateAssignmentId(baseAssignment);
      const id2 = generateAssignmentId({ ...baseAssignment, name: 'Chapter 2 Test' });

      expect(id1).not.toBe(id2);
    });

    it('should include assign_ prefix', () => {
      const id = generateAssignmentId(baseAssignment);
      expect(id).toMatch(/^assign_/);
    });

    it('should generate different IDs with index parameter', () => {
      const id1 = generateAssignmentId(baseAssignment, 0);
      const id2 = generateAssignmentId(baseAssignment, 1);

      expect(id1).not.toBe(id2);
    });

    it('should handle missing optional fields', () => {
      const minimalAssignment = {
        className: 'Math',
        name: 'Quiz',
        term: 'Q1',
        category: 'Quizzes',
        dueDate: '2024-01-01',
      };

      const id = generateAssignmentId(minimalAssignment);
      expect(id).toMatch(/^assign_/);
    });
  });

  describe('ensureAssignmentId', () => {
    it('should return assignment unchanged if it has an ID', () => {
      const assignment = {
        id: 'existing_id',
        className: 'Math',
        name: 'Test',
        term: 'Q1',
        category: 'Tests',
        dueDate: '2024-01-01',
      };

      const result = ensureAssignmentId(assignment);
      expect(result.id).toBe('existing_id');
    });

    it('should add ID if assignment lacks one', () => {
      const assignment = {
        className: 'Math',
        name: 'Test',
        term: 'Q1',
        category: 'Tests',
        dueDate: '2024-01-01',
      };

      const result = ensureAssignmentId(assignment);
      expect(result.id).toMatch(/^assign_/);
    });
  });

  describe('ensureUniqueAssignmentIds', () => {
    it('should preserve existing unique IDs', () => {
      const assignments = [
        { id: 'id1', className: 'Math', name: 'Test 1', term: 'Q1', category: 'Tests', dueDate: '2024-01-01' },
        { id: 'id2', className: 'Math', name: 'Test 2', term: 'Q1', category: 'Tests', dueDate: '2024-01-02' },
      ];

      const result = ensureUniqueAssignmentIds(assignments);
      expect(result[0].id).toBe('id1');
      expect(result[1].id).toBe('id2');
    });

    it('should generate IDs for assignments without them', () => {
      const assignments = [
        { className: 'Math', name: 'Test 1', term: 'Q1', category: 'Tests', dueDate: '2024-01-01' },
        { className: 'Math', name: 'Test 2', term: 'Q1', category: 'Tests', dueDate: '2024-01-02' },
      ];

      const result = ensureUniqueAssignmentIds(assignments);
      expect(result[0].id).toMatch(/^assign_/);
      expect(result[1].id).toMatch(/^assign_/);
      expect(result[0].id).not.toBe(result[1].id);
    });

    it('should handle duplicate IDs by generating new ones', () => {
      const assignments = [
        { id: 'duplicate', className: 'Math', name: 'Test 1', term: 'Q1', category: 'Tests', dueDate: '2024-01-01' },
        { id: 'duplicate', className: 'Math', name: 'Test 2', term: 'Q1', category: 'Tests', dueDate: '2024-01-02' },
      ];

      const result = ensureUniqueAssignmentIds(assignments);
      expect(result[0].id).toBe('duplicate');
      expect(result[1].id).not.toBe('duplicate');
    });

    it('should handle empty array', () => {
      const result = ensureUniqueAssignmentIds([]);
      expect(result).toEqual([]);
    });
  });

  describe('generateCourseId', () => {
    const baseCourse = {
      courseName: 'AP Chemistry',
      courseData: {
        finalGrade: '95',
        sm1: '94',
        sm2: '96',
      },
      savedLevel: 'AP',
    };

    it('should generate consistent IDs for same course', () => {
      const id1 = generateCourseId(baseCourse, 'Junior');
      const id2 = generateCourseId(baseCourse, 'Junior');

      expect(id1).toBe(id2);
    });

    it('should generate different IDs for different grade levels', () => {
      const id1 = generateCourseId(baseCourse, 'Junior');
      const id2 = generateCourseId(baseCourse, 'Senior');

      expect(id1).not.toBe(id2);
    });

    it('should include course_ prefix', () => {
      const id = generateCourseId(baseCourse, 'Junior');
      expect(id).toMatch(/^course_/);
    });

    it('should generate different IDs with index parameter', () => {
      const id1 = generateCourseId(baseCourse, 'Junior', 0);
      const id2 = generateCourseId(baseCourse, 'Junior', 1);

      expect(id1).not.toBe(id2);
    });
  });

  describe('ensureUniqueCourseIds', () => {
    it('should preserve existing unique IDs', () => {
      const courses = [
        { id: 'course1', courseName: 'Math', courseData: { finalGrade: '90' } },
        { id: 'course2', courseName: 'English', courseData: { finalGrade: '85' } },
      ];

      const result = ensureUniqueCourseIds(courses, 'Junior');
      expect(result[0].id).toBe('course1');
      expect(result[1].id).toBe('course2');
    });

    it('should generate IDs for courses without them', () => {
      const courses = [
        { courseName: 'Math', courseData: { finalGrade: '90' } },
        { courseName: 'English', courseData: { finalGrade: '85' } },
      ];

      const result = ensureUniqueCourseIds(courses, 'Junior');
      expect(result[0].id).toMatch(/^course_/);
      expect(result[1].id).toMatch(/^course_/);
      expect(result[0].id).not.toBe(result[1].id);
    });

    it('should handle empty array', () => {
      const result = ensureUniqueCourseIds([], 'Junior');
      expect(result).toEqual([]);
    });
  });
});
