// Authentication service - handles all auth operations
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth } from '../skywardAuthInfo';
import { authenticateWithSkyward } from '../api';
import { SessionManager } from '../utils/session-manager';
import { RequestDeduplicator } from '../utils/request-deduplicator';
import { logger, Modules, log } from '../utils/logger';
import { SkywardSessionCodes } from '../types/api';

export interface AuthResult {
  success: boolean;
  error?: string;
}

const AUTH_REQUEST_KEY = 'skyward_auth';
let authGeneration = 0;
let sessionMutation: Promise<void> = Promise.resolve();

export class AuthService {
  /**
   * Authenticate with Skyward
   * Uses request deduplication to prevent concurrent auth requests
   */
  static async authenticate(): Promise<AuthResult> {
    const endTimer = logger.time(Modules.AUTH, 'authenticate');

    // Use request deduplication
    const authentication = RequestDeduplicator.deduplicate(AUTH_REQUEST_KEY, async () => {
      try {
        const authResult = await this.performAuthentication();
        return authResult;
      } catch (error: any) {
        return { success: false, error: error.message || 'Authentication failed' };
      }
    });

    const result = await authentication;

    endTimer();
    
    if (result.success) {
      logger.success(Modules.AUTH, 'Authentication successful');
    } else {
      logger.error(Modules.AUTH, 'Authentication failed', result.error);
    }

    return result;
  }

  /**
   * Perform the actual authentication
   */
  private static async performAuthentication(): Promise<AuthResult> {
    const generation = authGeneration;

    try {
      const authInfo = await SkywardAuth.get();

      if (!authInfo?.link || !authInfo?.username || !authInfo?.password) {
        logger.warn(Modules.AUTH, 'Missing credentials');
        return { success: false, error: 'Missing credentials' };
      }

      // Real Skyward authentication
      try {
        log.api.request(Modules.AUTH, 'skyward/login');
        const startTime = Date.now();
        
        const sessionCodes = await authenticateWithSkyward({
          username: authInfo.username,
          password: authInfo.password,
          baseURL: authInfo.link,
        });

        const duration = Date.now() - startTime;

        if (!sessionCodes || !sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
          log.api.error(Modules.AUTH, 'skyward/login', duration, 'Invalid session codes');
          return { success: false, error: 'Invalid session codes received' };
        }

        log.api.success(Modules.AUTH, 'skyward/login', duration);
        if (!(await this.saveSessionIfCurrent(generation, authInfo, sessionCodes))) {
          return { success: false, error: 'Credentials changed during authentication' };
        }
        return { success: true };
      } catch (err: any) {
        logger.error(Modules.AUTH, 'Skyward login failed', err);

        if (generation === authGeneration && isConfirmedCredentialRejection(err)) {
          // Offline, timeout, and server failures must preserve the last-known
          // session/data. Only Skyward's explicit credential rejection signs out.
          await SessionManager.clearSessionCodes();
          DeviceEventEmitter.emit('credentialsInvalid');
        }
        
        return { success: false, error: err.message || 'Authentication failed' };
      }
    } catch (err: any) {
      logger.error(Modules.AUTH, 'Authentication error', err);
      return { success: false, error: err.message || 'Unknown error' };
    }
  }

  /**
   * Check if user has valid session
   */
  static async hasValidSession(): Promise<boolean> {
    return SessionManager.hasValidSession();
  }

  /**
   * Clear session (logout)
   */
  static async clearSession(): Promise<void> {
    authGeneration += 1;
    RequestDeduplicator.clearKey(AUTH_REQUEST_KEY);

    await this.mutateSession(() => SessionManager.clearSessionCodes());
  }

  private static async saveSessionIfCurrent(
    generation: number,
    original: { link: string; username: string; password: string },
    sessionCodes: SkywardSessionCodes
  ): Promise<boolean> {
    let saved = false;
    await this.mutateSession(async () => {
      if (!(await this.isAuthenticationCurrent(generation, original))) return;
      await SessionManager.saveSessionCodes(sessionCodes, original.link);
      saved = generation === authGeneration;
    });
    return saved;
  }

  private static async mutateSession(mutation: () => Promise<void>): Promise<void> {
    const queued = sessionMutation.then(mutation, mutation);
    sessionMutation = queued.catch(() => undefined);
    await queued;
  }

  private static async isAuthenticationCurrent(
    generation: number,
    original: { link: string; username: string; password: string }
  ): Promise<boolean> {
    if (generation !== authGeneration) return false;

    const current = await SkywardAuth.get();
    return (
      generation === authGeneration &&
      current?.link === original.link &&
      current.username === original.username &&
      current.password === original.password
    );
  }
}

function isConfirmedCredentialRejection(error: unknown): boolean {
  return error instanceof Error && error.message === 'Invalid username or password';
}
