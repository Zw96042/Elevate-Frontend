// Authentication service - handles all auth operations
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth } from '../skywardAuthInfo';
import { authenticateWithSkyward } from '../api';
import { SessionManager } from '../utils/session-manager';
import { RequestDeduplicator } from '../utils/request-deduplicator';
import { logger, Modules, log } from '../utils/logger';

export interface AuthResult {
  success: boolean;
  error?: string;
}

const AUTH_REQUEST_KEY = 'skyward_auth';
const MIN_AUTH_INTERVAL = 2000; // 2 seconds
const FAILED_AUTH_COOLDOWN = 10000; // 10 seconds cooldown after failed auth

let lastAuthTime = 0;
let lastAuthResult: AuthResult | null = null;
let lastFailedAuthTime = 0;

export class AuthService {
  /**
   * Authenticate with Skyward
   * Uses request deduplication to prevent concurrent auth requests
   */
  static async authenticate(): Promise<AuthResult> {
    const now = Date.now();

    // Use cached result if recent and successful
    if (now - lastAuthTime < MIN_AUTH_INTERVAL && lastAuthResult?.success) {
      log.cache.hit(Modules.AUTH, 'auth_result');
      return lastAuthResult;
    }

    // Prevent rapid retry attempts after failed authentication
    if (lastFailedAuthTime > 0 && now - lastFailedAuthTime < FAILED_AUTH_COOLDOWN) {
      const remainingCooldown = Math.ceil((FAILED_AUTH_COOLDOWN - (now - lastFailedAuthTime)) / 1000);
      logger.warn(Modules.AUTH, `Authentication cooldown active. Retry in ${remainingCooldown}s`);
      return { success: false, error: `Please wait ${remainingCooldown} seconds before retrying authentication` };
    }

    const endTimer = logger.time(Modules.AUTH, 'authenticate');

    // Use request deduplication
    const result = await RequestDeduplicator.deduplicate(AUTH_REQUEST_KEY, async () => {
      try {
        const authResult = await this.performAuthentication();
        lastAuthResult = authResult;
        if (authResult.success) {
          lastAuthTime = Date.now();
          lastFailedAuthTime = 0; // Reset failed auth timer on success
        } else {
          lastFailedAuthTime = Date.now(); // Set failed auth timer
        }
        return authResult;
      } catch (error: any) {
        lastFailedAuthTime = Date.now(); // Set failed auth timer on exception
        return { success: false, error: error.message || 'Authentication failed' };
      }
    });

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
    try {
      const authInfo = await SkywardAuth.get();

      if (!authInfo?.link || !authInfo?.username || !authInfo?.password) {
        logger.warn(Modules.AUTH, 'Missing credentials');
        return { success: false, error: 'Missing credentials' };
      }

      // Development credentials
      if (authInfo.username === "dev-test" && authInfo.password === "fgx") {
        logger.info(Modules.AUTH, 'Using development credentials');
        await SessionManager.saveSessionCodes(
          {
            dwd: "dev",
            wfaacl: "dev",
            encses: "dev",
            'User-Type': "dev",
            sessionid: "dev",
          },
          authInfo.link
        );
        return { success: true };
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
        await SessionManager.saveSessionCodes(sessionCodes, authInfo.link);
        return { success: true };
      } catch (err: any) {
        logger.error(Modules.AUTH, 'Skyward login failed', err);
        
        // Clear invalid session
        await SessionManager.clearSessionCodes();
        
        // Emit event for invalid credentials
        DeviceEventEmitter.emit('credentialsInvalid');
        
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
    await SessionManager.clearSessionCodes();
    lastAuthResult = null;
    lastAuthTime = 0;
    lastFailedAuthTime = 0;
    RequestDeduplicator.clearKey(AUTH_REQUEST_KEY);
  }
}
