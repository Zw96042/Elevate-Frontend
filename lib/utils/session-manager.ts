// Centralized session token management
import AsyncStorage from '@react-native-async-storage/async-storage';
import { SkywardSessionCodes } from '../types/api';
import {
  clearStoredSessionCodes,
  getStoredSessionCodes,
  saveStoredSessionCodes,
} from './secure-skyward-storage';
import { logger, Modules } from './logger';

export class SessionManager {
  private static readonly BASE_URL_KEY = 'skywardBaseURL';

  /**
   * Get all session codes from storage
   */
  static async getSessionCodes(): Promise<SkywardSessionCodes | null> {
    try {
      const sessionCodes = await getStoredSessionCodes();
      if (!sessionCodes) {
        logger.debug(Modules.SESSION, 'Session codes not found in storage');
        return null;
      }

      logger.debug(Modules.SESSION, 'Session codes retrieved from storage');
      return sessionCodes;
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
      const baseUrl = await AsyncStorage.getItem(this.BASE_URL_KEY);
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
      await AsyncStorage.setItem(this.BASE_URL_KEY, baseURL);
      await saveStoredSessionCodes(sessionCodes);
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
      await clearStoredSessionCodes();
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
