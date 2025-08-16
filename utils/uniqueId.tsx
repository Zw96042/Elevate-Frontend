/**
 * Generates a unique identifier combining timestamp and random string
 * @returns {string} A unique identifier string
 */
export const generateUniqueId = (): string => {
  const timestamp = Date.now().toString(36);
  const randomStr = Math.random().toString(36).substring(2, 8);
  return `${timestamp}-${randomStr}`;
};

/**
 * Generates a unique ID for an assignment based on its properties
 * This ensures consistent IDs for the same assignment across app restarts
 * @param assignment - The assignment object
 * @param index - Optional index to ensure uniqueness for similar assignments
 * @returns {string} A unique identifier for the assignment
 */
export const generateAssignmentId = (assignment: {
  className: string;
  name: string;
  term: string;
  category: string;
  dueDate: string;
  grade?: string;
  outOf?: number;
}, index?: number): string => {
  // Create a more comprehensive key including grade and points for better uniqueness
  const key = `${assignment.className}-${assignment.name}-${assignment.term}-${assignment.category}-${assignment.dueDate}-${assignment.grade || ''}-${assignment.outOf || ''}${index !== undefined ? `-${index}` : ''}`;
  
  // Simple hash function to convert string to consistent ID
  let hash = 0;
  for (let i = 0; i < key.length; i++) {
    const char = key.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash; // Convert to 32bit integer
  }
  
  // Convert to positive string and add prefix
  return `assign_${Math.abs(hash).toString(36)}`;
};

/**
 * Ensures an assignment has a unique ID
 * @param assignment - The assignment object (with or without ID)
 * @param index - Optional index to ensure uniqueness
 * @returns {Assignment} The assignment with a guaranteed unique ID
 */
export const ensureAssignmentId = (assignment: any, index?: number): any => {
  if (assignment.id) {
    return assignment;
  }
  
  return {
    ...assignment,
    id: generateAssignmentId(assignment, index),
  };
};

/**
 * Ensures all assignments in an array have unique IDs
 * @param assignments - Array of assignment objects
 * @returns {Assignment[]} Array of assignments with guaranteed unique IDs
 */
export const ensureUniqueAssignmentIds = (assignments: any[]): any[] => {
  const seenIds = new Set<string>();
  
  return assignments.map((assignment, index) => {
    if (assignment.id && !seenIds.has(assignment.id)) {
      seenIds.add(assignment.id);
      return assignment;
    }
    
    // Generate a new ID, potentially with index for uniqueness
    let newId = generateAssignmentId(assignment, index);
    let counter = 0;
    
    // If ID already exists, keep incrementing until we get a unique one
    while (seenIds.has(newId)) {
      counter++;
      newId = generateAssignmentId(assignment, index + counter * 1000);
    }
    
    seenIds.add(newId);
    return {
      ...assignment,
      id: newId,
    };
  });
};
