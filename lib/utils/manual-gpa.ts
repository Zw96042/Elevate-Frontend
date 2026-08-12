import type { UnifiedCourseData } from '../services';
import { getAccountScopedItem, setAccountScopedItem } from './account-scoped-storage';

export const HISTORICAL_GRADE_LEVELS = [
  'Freshman', 'Sophomore', 'Junior', 'Senior',
] as const;

export type HistoricalGradeLevel = typeof HISTORICAL_GRADE_LEVELS[number];
export type GPASelection = HistoricalGradeLevel | 'Current' | 'All Time';

export interface SavedManualClass {
  className: string;
  sm1: number;
  sm2: number;
  rc1?: number;
  rc2?: number;
  rc3?: number;
  rc4?: number;
  level?: string;
}

const GRADE_YEARS: Record<HistoricalGradeLevel, number> = {
  Freshman: 9,
  Sophomore: 10,
  Junior: 11,
  Senior: 12,
};

function finiteGrade(value: unknown): number | undefined {
  if (value === null || value === undefined || value === '') return undefined;
  const number = Number(value);
  return Number.isFinite(number) && number >= 0 ? number : undefined;
}

export function normalizeManualClass(value: unknown): SavedManualClass | null {
  if (!value || typeof value !== 'object') return null;
  const row = value as Record<string, any>;
  const grades = row.grades && typeof row.grades === 'object' ? row.grades : {};
  const className = String(row.className ?? row.courseName ?? row.name ?? '').trim();
  if (!className) return null;
  return {
    className,
    sm1: finiteGrade(row.sm1 ?? grades.sm1) ?? -1,
    sm2: finiteGrade(row.sm2 ?? grades.sm2) ?? -1,
    rc1: finiteGrade(row.rc1 ?? grades.rc1),
    rc2: finiteGrade(row.rc2 ?? grades.rc2),
    rc3: finiteGrade(row.rc3 ?? grades.rc3),
    rc4: finiteGrade(row.rc4 ?? grades.rc4),
    level: typeof row.level === 'string' ? row.level : undefined,
  };
}

export async function loadManualClasses(
  gradeLevel: HistoricalGradeLevel
): Promise<SavedManualClass[]> {
  const raw = await getAccountScopedItem(`savedClasses-${gradeLevel}`);
  if (!raw) return [];
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed)) return [];
  return parsed.flatMap(row => {
    const normalized = normalizeManualClass(row);
    return normalized ? [normalized] : [];
  });
}

export async function saveManualClass(
  gradeLevel: HistoricalGradeLevel,
  value: SavedManualClass
): Promise<SavedManualClass[]> {
  const normalized = normalizeManualClass(value);
  if (!normalized) throw new Error('A class name is required.');
  const existing = await loadManualClasses(gradeLevel);
  const normalizedName = normalized.className.toLocaleLowerCase();
  const updated = [
    normalized,
    ...existing.filter(row => row.className.toLocaleLowerCase() !== normalizedName),
  ];
  await setAccountScopedItem(`savedClasses-${gradeLevel}`, JSON.stringify(updated));
  return updated;
}

export async function loadAvailableManualGradeLevels(): Promise<HistoricalGradeLevel[]> {
  const records = await Promise.all(
    HISTORICAL_GRADE_LEVELS.map(async level => ({ level, classes: await loadManualClasses(level) }))
  );
  return records.filter(record => record.classes.length > 0).map(record => record.level);
}

export async function loadManualCoursesForSelection(
  selection: GPASelection
): Promise<UnifiedCourseData[]> {
  const levels = selection === 'All Time'
    ? [...HISTORICAL_GRADE_LEVELS]
    : HISTORICAL_GRADE_LEVELS.includes(selection as HistoricalGradeLevel)
      ? [selection as HistoricalGradeLevel]
      : [];
  const records = await Promise.all(levels.map(async level => ({
    level,
    classes: await loadManualClasses(level),
  })));
  return records.flatMap(({ level, classes }) => classes.map(manual => ({
    courseName: manual.className,
    semester: 'both' as const,
    termLength: '1 - 4',
    gradeYear: GRADE_YEARS[level],
    currentScores: [],
    historicalGrades: {
      sm1: manual.sm1 >= 0 ? String(manual.sm1) : undefined,
      sm2: manual.sm2 >= 0 ? String(manual.sm2) : undefined,
      rc1: manual.rc1 === undefined ? undefined : String(manual.rc1),
      rc2: manual.rc2 === undefined ? undefined : String(manual.rc2),
      rc3: manual.rc3 === undefined ? undefined : String(manual.rc3),
      rc4: manual.rc4 === undefined ? undefined : String(manual.rc4),
    },
  })));
}

export function mergeAcademicCourses(
  skywardCourses: UnifiedCourseData[],
  manualCourses: UnifiedCourseData[]
): UnifiedCourseData[] {
  const keys = new Set(skywardCourses.map(course => courseKey(course)));
  return [
    ...skywardCourses,
    ...manualCourses.filter(course => !keys.has(courseKey(course))),
  ];
}

function courseKey(course: UnifiedCourseData): string {
  return `${course.gradeYear ?? 'current'}|${course.courseName.trim().toLowerCase()}`;
}
