// Main Skyward API client with centralized error handling
import { SessionManager } from '../../utils/session-manager';
import { SkywardSessionCodes } from '../../types/api';

export class SkywardAPIError extends Error {
  code?: string;
  statusCode?: number;

  constructor(message: string, code?: string, statusCode?: number) {
    super(message);
    this.name = 'SkywardAPIError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

/**
 * Check if error is a session expiration error
 */
export function isSessionExpiredError(error: any): boolean {
  return (
    error?.code === 'SESSION_EXPIRED' ||
    error?.statusCode === 401 ||
    error?.message?.toLowerCase().includes('session expired') ||
    error?.message?.toLowerCase().includes('session has timed out')
  );
}

/**
 * Get session codes and base URL, throw if missing
 */
export async function getRequiredSessionData(): Promise<{
  sessionCodes: SkywardSessionCodes;
  baseUrl: string;
}> {
  const sessionCodes = await SessionManager.getSessionCodes();
  const baseUrl = await SessionManager.getBaseURL();

  if (!sessionCodes || !baseUrl) {
    throw new SkywardAPIError('Missing session credentials', 'NO_SESSION');
  }

  return { sessionCodes, baseUrl };
}

/**
 * Handle API errors consistently
 */
export function handleAPIError(error: any, context: string): never {
  console.error(`❌ ${context}:`, error);

  if (isSessionExpiredError(error)) {
    throw new SkywardAPIError('Session expired', 'SESSION_EXPIRED', 401);
  }

  if (error instanceof SkywardAPIError) {
    throw error;
  }

  throw new SkywardAPIError(
    error.message || 'Unknown error occurred',
    error.code,
    error.statusCode
  );
}
