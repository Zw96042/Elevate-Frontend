
/**
 * Authentication Handler
 * Simplified authentication logic using CredentialManager
 */

import { CredentialManager } from './core/CredentialManager';
import { createComponentLogger } from './core/Logger';
import { getNewSessionCodes } from './skywardAuthClient';
import { AuthResult } from '@/interfaces/interfaces';

const logger = createComponentLogger('AuthHandler');

// Authentication cooldown to prevent spam
let lastAuthAttempt = 0;
let lastAuthError = '';
const AUTH_COOLDOWN_MS = 5000; // 5 seconds

export async function authenticate(): Promise<AuthResult> {
  try {
    // Check cooldown for failed authentication attempts
    const now = Date.now();
    if (now - lastAuthAttempt < AUTH_COOLDOWN_MS && lastAuthError) {
      logger.debug('Authentication attempt blocked by cooldown', {
        method: 'authenticate',
        cooldownRemaining: `${Math.ceil((AUTH_COOLDOWN_MS - (now - lastAuthAttempt)) / 1000)}s`
      });
      return { success: false, error: lastAuthError };
    }

    logger.info('Starting authentication process', {
      method: 'authenticate'
    });

    const authInfo = await CredentialManager.getAuthInfo();
    
    if (!authInfo || !CredentialManager.validateAuthInfo(authInfo)) {
      logger.warn('No valid auth info found', {
        method: 'authenticate',
        hasAuthInfo: !!authInfo,
        isValid: authInfo ? CredentialManager.validateAuthInfo(authInfo) : false
      });
      return { success: false, error: 'Please log in with your Skyward credentials' };
    }

    logger.debug('Auth info found, checking credentials', {
      method: 'authenticate',
      username: authInfo.username,
      hasPassword: !!authInfo.password,
      hasLink: !!authInfo.link
    });

    // Check for development credentials
    if (authInfo.username === "dev-test" && authInfo.password === "fgx") {
      logger.info('Using development credentials', {
        method: 'authenticate'
      });
      await CredentialManager.setDevCredentials(authInfo.link);
      return { success: true };
    }

    // Authenticate with Skyward
    logger.info('Authenticating with Skyward backend', {
      method: 'authenticate',
      baseUrl: authInfo.link
    });

    try {
      const sessionCodes = await getNewSessionCodes({
        username: authInfo.username,
        password: authInfo.password,
        baseURL: authInfo.link,
      });

      if (!sessionCodes || !sessionCodes.dwd || !sessionCodes.wfaacl || !sessionCodes.encses) {
        logger.warn('Authentication failed - unable to get valid session codes', {
          method: 'authenticate',
          sessionCodes: sessionCodes ? 'present but invalid' : 'null'
        });
        return { success: false, error: 'Failed to authenticate with Skyward. Please check your credentials.' };
      }

      // Store session codes and base URL
      await CredentialManager.storeSessionCodes(sessionCodes);
      await CredentialManager.setBaseUrl(authInfo.link);

      logger.info('Authentication successful', {
        method: 'authenticate'
      });

      // Clear cooldown on success
      lastAuthError = '';
      lastAuthAttempt = 0;

      return { success: true };
    } catch (err: any) {
      lastAuthAttempt = Date.now();
      const errorMessage = 'Failed to authenticate with Skyward. Please check your credentials and try again.';
      lastAuthError = errorMessage;

      // Log all authentication failures as warnings, not errors, to reduce noise
      logger.warn('Authentication failed', {
        method: 'authenticate',
        errorType: err.message?.includes('Invalid user or pass') ? 'invalid_credentials' : 'other'
      });
      
      // Clear session on authentication failure
      await CredentialManager.setEmptySession(authInfo.link);
      return { success: false, error: errorMessage };
    }
  } catch (err: any) {
    lastAuthAttempt = Date.now();
    const errorMessage = 'An unexpected error occurred during authentication.';
    lastAuthError = errorMessage;

    // Log unexpected errors as warnings, not errors
    logger.warn('Unexpected authentication error', {
      method: 'authenticate',
      error: err.message
    });
    return { success: false, error: errorMessage };
  }
}