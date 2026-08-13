export function hasPostedGrade(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value) && value >= 0;
}

const MAX_EDITABLE_POINTS = 1_000_000;

export function parseEditablePoints(value: unknown, allowZero = true): number | null {
  if (typeof value !== 'string' && typeof value !== 'number') return null;
  if (typeof value === 'string' && value.trim() === '') return null;

  const parsed = Number(value);
  const minimum = allowZero ? 0 : 0.01;
  return Number.isFinite(parsed) && parsed >= minimum && parsed <= MAX_EDITABLE_POINTS
    ? parsed
    : null;
}
