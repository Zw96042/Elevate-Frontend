/**
 * Centralized Credential Management System
 * Handles secure storage and retrieval of authentication credentials
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { DeviceEventEmitter } from 'react-native';
import { createComponentLogger } from './Logger';
import { SkywardAuthInfo, SkywardSessionCodes, AsyncStorageKeys, ApiResponse } from '@/interfaces/interfaces';

const logger = createComponentLogger('CredentialManager');

// Storage keys for better type safety
const STORAGE_KEYS = {
  AUTH_INFO: 'skyward_auth_info',
  SESSION_CODES: 'skyward_session_codes',
  BASE_URL: 'baseUrl',
} as const;

export class CredentialManager {
  /**
   * Store authentication information securely
   */
  static async storeAuthInfo(authInfo: SkywardAuthInfo): Promise<void> {
    try {
      logger.info('Storing authentication information', {
        method: 'storeAuthInfo',
        username: authInfo.username,
        link: authInfo.link
      });
      
      await AsyncStorage.setItem(STORAGE_KEYS.AUTH_INFO, JSON.stringify(authInfo));
      
      logger.debug('Authentication information stored successfully', {
        method: 'storeAuthInfo'
      });
    } catch (error) {
      logger.error('Failed to store auth info', error as Error, {
        method: 'storeAuthInfo'
      });
      throw new Error('Failed to store authentication information');
    }
  }

  /**
   * Retrieve authentication information
   */
  static async getAuthInfo(): Promise<SkywardAuthInfo | null> {
    try {
      logger.debug('Retrieving authentication information', {
        method: 'getAuthInfo'
      });
      
      const authInfo = await AsyncStorage.getItem(STORAGE_KEYS.AUTH_INFO);
      const result = authInfo ? JSON.parse(authInfo) : null;
      
      logger.debug('Authentication information retrieved', {
        method: 'getAuthInfo',
        hasAuthInfo: !!result,
        username: result?.username || 'none'
      });
      
      return result;
    } catch (error) {
      logger.error('Failed to get auth info', error as Error, {
        method: 'getAuthInfo'
      });
      return null;
    }
  }

  /**
   * Store session codes
   */
  static async storeSessionCodes(sessionCodes: SkywardSessionCodes): Promise<void> {
    try {
      logger.info('Storing session codes', {
        method: 'storeSessionCodes',
        userType: sessionCodes['User-Type'],
        hasSessionId: !!sessionCodes.sessionid
      });

      // Store as individual items for backward compatibility
      await Promise.all([
        AsyncStorage.setItem('dwd', sessionCodes.dwd),
        AsyncStorage.setItem('wfaacl', sessionCodes.wfaacl),
        AsyncStorage.setItem('encses', sessionCodes.encses),
        AsyncStorage.setItem('User-Type', sessionCodes['User-Type']),
        AsyncStorage.setItem('sessionid', sessionCodes.sessionid),
      ]);
      
      // Also store as a complete object for future use
      await AsyncStorage.setItem(STORAGE_KEYS.SESSION_CODES, JSON.stringify(sessionCodes));
      
      logger.debug('Session codes stored successfully', {
        method: 'storeSessionCodes'
      });
    } catch (error) {
      logger.error('Failed to store session codes', error as Error, {
        method: 'storeSessionCodes'
      });
      throw new Error('Failed to store session codes');
    }
  }

  /**
   * Retrieve session codes
   */
  static async getSessionCodes(): Promise<SkywardSessionCodes | null> {
    try {
      logger.debug('Retrieving session codes', {
        method: 'getSessionCodes'
      });

      // Try to get from the complete object first
      const sessionCodes = await AsyncStorage.getItem(STORAGE_KEYS.SESSION_CODES);
      if (sessionCodes) {
        return JSON.parse(sessionCodes);
      }

      // Fallback to individual items for backward compatibility
      const [dwd, wfaacl, encses, userType, sessionid] = await Promise.all([
        AsyncStorage.getItem('dwd'),
        AsyncStorage.getItem('wfaacl'),
        AsyncStorage.getItem('encses'),
        AsyncStorage.getItem('User-Type'),
        AsyncStorage.getItem('sessionid'),
      ]);

      if (dwd && wfaacl && encses && userType && sessionid) {
        return {
          dwd,
          wfaacl,
          encses,
          'User-Type': userType,
          sessionid,
        };
      }

      return null;
    } catch (error) {
      console.error('Failed to get session codes:', error);
      return null;
    }
  }

  /**
   * Check if session codes are valid (not dev credentials)
   */
  static async hasValidSession(): Promise<boolean> {
    const sessionCodes = await this.getSessionCodes();
    if (!sessionCodes) return false;

    // Check if any of the required fields are missing or are dev credentials
    const isDevCredentials = Object.values(sessionCodes).some(value => value === 'dev');
    const hasAllFields = Object.values(sessionCodes).every(value => value && value.trim() !== '');

    return hasAllFields && !isDevCredentials;
  }

  /**
   * Clear all credentials
   */
  static async clearCredentials(): Promise<void> {
    try {
      await Promise.all([
        AsyncStorage.removeItem(STORAGE_KEYS.AUTH_INFO),
        AsyncStorage.removeItem(STORAGE_KEYS.SESSION_CODES),
        AsyncStorage.removeItem('dwd'),
        AsyncStorage.removeItem('wfaacl'),
        AsyncStorage.removeItem('encses'),
        AsyncStorage.removeItem('User-Type'),
        AsyncStorage.removeItem('sessionid'),
        AsyncStorage.removeItem('baseUrl'),
      ]);
    } catch (error) {
      console.error('Failed to clear credentials:', error);
      throw new Error('Failed to clear credentials');
    }
  }

  /**
   * Set empty session codes (for failed authentication)
   */
  static async setEmptySession(baseUrl: string): Promise<void> {
    try {
      await Promise.all([
        AsyncStorage.setItem('dwd', ''),
        AsyncStorage.setItem('wfaacl', ''),
        AsyncStorage.setItem('encses', ''),
        AsyncStorage.setItem('User-Type', ''),
        AsyncStorage.setItem('sessionid', ''),
        AsyncStorage.setItem('baseUrl', baseUrl),
      ]);

      // Emit event for credential invalidation
      DeviceEventEmitter.emit('credentialsInvalid');
    } catch (error) {
      console.error('Failed to set empty session:', error);
      throw new Error('Failed to clear session');
    }
  }

  /**
   * Set development credentials
   */
  static async setDevCredentials(baseUrl: string): Promise<void> {
    const devSessionCodes: SkywardSessionCodes = {
      dwd: 'dev',
      wfaacl: 'dev',
      encses: 'dev',
      'User-Type': 'dev',
      sessionid: 'dev',
    };

    await this.storeSessionCodes(devSessionCodes);
    await AsyncStorage.setItem('baseUrl', baseUrl);
  }

  /**
   * Get base URL
   */
  static async getBaseUrl(): Promise<string | null> {
    try {
      return await AsyncStorage.getItem('baseUrl');
    } catch (error) {
      console.error('Failed to get base URL:', error);
      return null;
    }
  }

  /**
   * Store base URL
   */
  static async setBaseUrl(baseUrl: string): Promise<void> {
    try {
      await AsyncStorage.setItem('baseUrl', baseUrl);
    } catch (error) {
      console.error('Failed to set base URL:', error);
      throw new Error('Failed to store base URL');
    }
  }

  /**
   * Validate credentials format
   */
  static validateAuthInfo(authInfo: Partial<SkywardAuthInfo>): boolean {
    return !!(
      authInfo.link &&
      authInfo.username &&
      authInfo.password &&
      typeof authInfo.link === 'string' &&
      typeof authInfo.username === 'string' &&
      typeof authInfo.password === 'string' &&
      authInfo.link.trim() !== '' &&
      authInfo.username.trim() !== '' &&
      authInfo.password.trim() !== ''
    );
  }

  /**
   * Check if credentials exist
   */
  static async credentialsExist(): Promise<boolean> {
    const authInfo = await this.getAuthInfo();
    return authInfo !== null && this.validateAuthInfo(authInfo);
  }
}
