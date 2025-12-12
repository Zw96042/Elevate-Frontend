// Centralized session token management
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardSessionCodes } from '../types/api';
import { logger, Modules } from './logger';

export class SessionManager {
  private static readonly SESSION_KEYS = {
    DWD: 'dwd',
    WFAACL: 'wfaacl',
    ENCSES: 'encses',
    USER_TYPE: 'User-Type',
    SESSION_ID: 'sessionid',
    BASE_URL: 'skywardBaseURL',
  };

  /**
   * Get all session codes from storage
   */
  static async getSessionCodes(): Promise<SkywardSessionCodes | null> {
    try {
      const [dwd, wfaacl, encses, userType, sessionid] = await Promise.all([
        AsyncStorage.getItem(this.SESSION_KEYS.DWD),
        AsyncStorage.getItem(this.SESSION_KEYS.WFAACL),
        AsyncStorage.getItem(this.SESSION_KEYS.ENCSES),
        AsyncStorage.getItem(this.SESSION_KEYS.USER_TYPE),
        AsyncStorage.getItem(this.SESSION_KEYS.SESSION_ID),
      ]);

      if (!dwd || !wfaacl || !encses || !userType || !sessionid) {
        logger.debug(Modules.SESSION, 'Session codes not found in storage');
        return null;
      }

      logger.debug(Modules.SESSION, 'Session codes retrieved from storage');
      return {
        dwd,
        wfaacl,
        encses,
        'User-Type': userType,
        sessionid,
      };
    } catch (error) {
      logger.error(Modules.SESSION, 'Failed to get session codes', error);
      return null;
    }
  }

  /**
   * Get base URL from storage
   */
  static async getBaseURL(): Promise<string | null> {
    try {
      const baseUrl = await AsyncStorage.getItem(this.SESSION_KEYS.BASE_URL);
      if (baseUrl) {
        logger.debug(Modules.SESSION, 'Base URL retrieved from storage');
      }
      return baseUrl;
    } catch (error) {
      logger.error(Modules.SESSION, 'Failed to get base URL', error);
      return null;
    }
  }

  /**
   * Save session codes to storage
   */
  static async saveSessionCodes(
    sessionCodes: SkywardSessionCodes,
    baseURL: string
  ): Promise<void> {
    try {
      await Promise.all([
        AsyncStorage.setItem(this.SESSION_KEYS.DWD, sessionCodes.dwd),
        AsyncStorage.setItem(this.SESSION_KEYS.WFAACL, sessionCodes.wfaacl),
        AsyncStorage.setItem(this.SESSION_KEYS.ENCSES, sessionCodes.encses),
        AsyncStorage.setItem(this.SESSION_KEYS.USER_TYPE, sessionCodes['User-Type']),
        AsyncStorage.setItem(this.SESSION_KEYS.SESSION_ID, sessionCodes.sessionid),
        AsyncStorage.setItem(this.SESSION_KEYS.BASE_URL, baseURL),
      ]);
      logger.success(Modules.SESSION, 'Session codes saved to storage');
    } catch (error) {
      logger.error(Modules.SESSION, 'Failed to save session codes', error);
      throw error;
    }
  }

  /**
   * Clear all session codes
   */
  static async clearSessionCodes(): Promise<void> {
    try {
      await AsyncStorage.multiRemove([
        this.SESSION_KEYS.DWD,
        this.SESSION_KEYS.WFAACL,
        this.SESSION_KEYS.ENCSES,
        this.SESSION_KEYS.USER_TYPE,
        this.SESSION_KEYS.SESSION_ID,
      ]);
      logger.success(Modules.SESSION, 'Session codes cleared from storage');
    } catch (error) {
      logger.error(Modules.SESSION, 'Failed to clear session codes', error);
      throw error;
    }
  }

  /**
   * Check if session codes exist
   */
  static async hasValidSession(): Promise<boolean> {
    const sessionCodes = await this.getSessionCodes();
    const baseURL = await this.getBaseURL();
    return sessionCodes !== null && baseURL !== null;
  }
}
