type Assignment = {
  className: string;
  name: string;
  term: string;
  category: string;
  grade: string;
  outOf: number;
  dueDate: string;
  artificial: boolean;
};

type GradeSummary = {
  courseTotal: number;
  categories: {
    [category: string]: {
      average: number;
      weight: number;
      rawPoints: number;
      rawTotal: number;
    };
  };
};

export function calculateGradeSummary(
  assignments: Assignment[],
  categoryWeights: Record<string, number>
): GradeSummary {
  const categories: Record<string, {
    rawPoints: number;
    rawTotal: number;
    weight: number;
  }> = {};

  // Sum up points per category
  for (const a of assignments) {
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

  // Compute average for each and weighted total
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

  const courseTotal = totalWeight > 0 ? weightedSum / totalWeight : 0;

  return {
    courseTotal: parseFloat(courseTotal.toFixed(2)),
    categories: categoryResult,
  };
}