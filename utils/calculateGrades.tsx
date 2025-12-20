type Assignment = {
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
  meta?: AssignmentMeta[];
};

type AssignmentMeta = {
  type: 'missing' | 'noCount' | 'absent';
  note: string;
};

type GradeSummary = {
  courseTotal: string;
  categories: {
    [category: string]: {
      average: number;
      weight: number;
      rawPoints: number;
      rawTotal: number;
    };
  };
  rcGrades?: {
    rc1?: number;
    rc2?: number;
    rc3?: number;
    rc4?: number;
  };
  semesterAverages?: {
    sm1?: number;
    sm2?: number;
  };
};

/**
 * Calculate semester averages from rounded RC grades
 */
function calculateSemesterAverages(rcGrades: { rc1?: number; rc2?: number; rc3?: number; rc4?: number }): { sm1?: number; sm2?: number } {
  const result: { sm1?: number; sm2?: number } = {};

  // Calculate SM1 from RC1 and RC2
  if (rcGrades.rc1 !== undefined && rcGrades.rc2 !== undefined) {
    result.sm1 = (rcGrades.rc1 + rcGrades.rc2) / 2;
  } else if (rcGrades.rc1 !== undefined) {
    result.sm1 = rcGrades.rc1;
  } else if (rcGrades.rc2 !== undefined) {
    result.sm1 = rcGrades.rc2;
  }

  // Calculate SM2 from RC3 and RC4
  if (rcGrades.rc3 !== undefined && rcGrades.rc4 !== undefined) {
    result.sm2 = (rcGrades.rc3 + rcGrades.rc4) / 2;
  } else if (rcGrades.rc3 !== undefined) {
    result.sm2 = rcGrades.rc3;
  } else if (rcGrades.rc4 !== undefined) {
    result.sm2 = rcGrades.rc4;
  }

  return result;
}

export function calculateGradeSummary(
  assignments: Assignment[],
  categoryWeights: Record<string, number>,
  termMap?: Record<string, any>,
  selectedCategory?: string
): GradeSummary {
  const categories: Record<string, {
    rawPoints: number;
    rawTotal: number;
    weight: number;
  }> = {};

  // Filter out "no count" assignments before calculations
  const countableAssignments = assignments.filter(assignment => {
    const isNoCount = assignment.meta?.some(m => m.type === 'noCount');
    return !isNoCount;
  });

  // Debug: Log all terms and categories to see what we're working with
  const allCategories = [...new Set(countableAssignments.map(a => a.category))];
  const allTerms = [...new Set(countableAssignments.map(a => a.term))];
  console.log('🔍 All assignment categories:', allCategories);
  console.log('🔍 All assignment terms:', allTerms);
  console.log('🔍 Selected category:', selectedCategory);

  // Sum up points per category for countable assignments only
  for (const a of countableAssignments) {
    if (!categories[a.category]) {
      categories[a.category] = {
        rawPoints: 0,
        rawTotal: 0,
        weight: categoryWeights[a.category] ?? 0,
      };
    }
    categories[a.category].rawPoints += Number(a.grade);
    categories[a.category].rawTotal += a.outOf;
  }

  // Calculate RC grades based on the selected category
  const rcGrades: { rc1?: number; rc2?: number; rc3?: number; rc4?: number } = {};
  const semesterAverages: { sm1?: number; sm2?: number } = {};

  // If we're viewing a semester grade (SM1 or SM2), we need to calculate RC grades
  if (selectedCategory === 'SM1 Grade' && termMap) {
    // For SM1, we need to calculate RC1 (Q1) and RC2 (Q2) separately
    const q1Data = termMap['Q1 Grades'];
    const q2Data = termMap['Q2 Grades'];
    
    console.log('🔍 Q1 Data:', q1Data);
    console.log('🔍 Q2 Data:', q2Data);
    
    // Use the totals directly from Q1 and Q2 data (these are already calculated RC grades)
    if (q1Data && typeof q1Data.total === 'number') {
      rcGrades.rc1 = Math.round(q1Data.total);
      console.log('🔍 RC1 (Q1) - Raw total:', q1Data.total, 'Rounded:', rcGrades.rc1);
    }
    
    if (q2Data && typeof q2Data.total === 'number') {
      rcGrades.rc2 = Math.round(q2Data.total);
      console.log('🔍 RC2 (Q2) - Raw total:', q2Data.total, 'Rounded:', rcGrades.rc2);
    }
    
    // Calculate SM1 from rounded RC1 and RC2
    if (rcGrades.rc1 !== undefined && rcGrades.rc2 !== undefined) {
      semesterAverages.sm1 = (rcGrades.rc1 + rcGrades.rc2) / 2;
      console.log('🔍 SM1 calculated from RC1 and RC2:', semesterAverages.sm1);
    } else if (rcGrades.rc1 !== undefined) {
      semesterAverages.sm1 = rcGrades.rc1;
      console.log('🔍 SM1 using only RC1:', semesterAverages.sm1);
    } else if (rcGrades.rc2 !== undefined) {
      semesterAverages.sm1 = rcGrades.rc2;
      console.log('🔍 SM1 using only RC2:', semesterAverages.sm1);
    }
    
  } else if (selectedCategory === 'SM2 Grades' && termMap) {
    // Similar logic for SM2 with Q3 and Q4
    const q3Data = termMap['Q3 Grades'];
    const q4Data = termMap['Q4 Grades'];
    
    console.log('🔍 Q3 Data:', q3Data);
    console.log('🔍 Q4 Data:', q4Data);
    
    // Use the totals directly from Q3 and Q4 data
    if (q3Data && typeof q3Data.total === 'number') {
      rcGrades.rc3 = Math.round(q3Data.total);
      console.log('🔍 RC3 (Q3) - Raw total:', q3Data.total, 'Rounded:', rcGrades.rc3);
    }
    
    if (q4Data && typeof q4Data.total === 'number') {
      rcGrades.rc4 = Math.round(q4Data.total);
      console.log('🔍 RC4 (Q4) - Raw total:', q4Data.total, 'Rounded:', rcGrades.rc4);
    }
    
    // Calculate SM2 from rounded RC3 and RC4
    if (rcGrades.rc3 !== undefined && rcGrades.rc4 !== undefined) {
      semesterAverages.sm2 = (rcGrades.rc3 + rcGrades.rc4) / 2;
      console.log('🔍 SM2 calculated from RC3 and RC4:', semesterAverages.sm2);
    } else if (rcGrades.rc3 !== undefined) {
      semesterAverages.sm2 = rcGrades.rc3;
      console.log('🔍 SM2 using only RC3:', semesterAverages.sm2);
    } else if (rcGrades.rc4 !== undefined) {
      semesterAverages.sm2 = rcGrades.rc4;
      console.log('🔍 SM2 using only RC4:', semesterAverages.sm2);
    }
  }

  // Compute average for each category and weighted total (using original logic for overall grade)
  let weightedSum = 0;
  let totalWeight = 0;
  const categoryResult: GradeSummary['categories'] = {};

  for (const [cat, data] of Object.entries(categories)) {
    const average = data.rawTotal > 0 ? (data.rawPoints / data.rawTotal) * 100 : 0;
    
    weightedSum += average * data.weight;
    totalWeight += data.weight;

    categoryResult[cat] = {
      average: parseFloat(average.toFixed(2)),
      weight: data.weight,
      rawPoints: data.rawPoints,
      rawTotal: data.rawTotal,
    };
  }

  console.log('🔍 RC Grades:', rcGrades);
  console.log('🔍 Calculated semester averages:', semesterAverages);

  // Calculate course total - use semester average if available, otherwise use weighted calculation
  let courseTotal: string;
  
  if (selectedCategory === 'SM1 Grade' && semesterAverages.sm1 !== undefined) {
    courseTotal = semesterAverages.sm1.toString();
    console.log('🔍 Using SM1 semester average as course total:', courseTotal);
  } else if (selectedCategory === 'SM2 Grades' && semesterAverages.sm2 !== undefined) {
    courseTotal = semesterAverages.sm2.toString();
    console.log('🔍 Using SM2 semester average as course total:', courseTotal);
  } else {
    // Use original weighted calculation for non-semester views
    const weightedTotal = (totalWeight > 0 ? weightedSum / totalWeight : 0) === Number(0)
      ? '*'
      : parseFloat((totalWeight > 0 ? weightedSum / totalWeight : 0).toFixed(2)).toString();
    courseTotal = weightedTotal;
    console.log('🔍 Using weighted calculation as course total:', courseTotal);
  }
    
  console.log('🔍 Final course total:', courseTotal, 'from weightedSum:', weightedSum, 'totalWeight:', totalWeight);
    
  return {
    courseTotal: courseTotal,
    categories: categoryResult,
    rcGrades,
    semesterAverages,
  };
}