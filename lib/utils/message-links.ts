export function safeMessageURL(value: string): string | null {
  try {
    const parsed = new URL(value.trim());
    return parsed.protocol === 'https:' && parsed.hostname ? parsed.href : null;
  } catch {
    return null;
  }
}
