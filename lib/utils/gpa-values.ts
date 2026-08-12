import type { GPAData } from '../unifiedGpaManager';

export const isFiniteGPA = (value: GPAData | undefined): value is GPAData =>
  value !== undefined
  && Number.isFinite(value.unweighted)
  && Number.isFinite(value.weighted);

export function averageSemesterGPA(
  first: GPAData | undefined,
  second: GPAData | undefined
): GPAData | null {
  const values = [first, second].filter(isFiniteGPA);
  if (values.length === 0) return null;
  return {
    unweighted: values.reduce((sum, value) => sum + value.unweighted, 0) / values.length,
    weighted: values.reduce((sum, value) => sum + value.weighted, 0) / values.length,
  };
}

export const formatGPAValue = (value: number | undefined): string =>
  typeof value === 'number' && Number.isFinite(value) ? value.toFixed(2) : '--';

export function shouldShowGPALogin(input: {
  checkedCredentials: boolean;
  hasCredentials: boolean;
  loadingCourses: boolean;
  hasCourseSnapshot: boolean;
  manualYearCount: number;
}): boolean {
  return input.checkedCredentials
    && !input.hasCredentials
    && !input.loadingCourses
    && !input.hasCourseSnapshot
    && input.manualYearCount === 0;
}
