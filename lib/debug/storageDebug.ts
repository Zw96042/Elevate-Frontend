/**
 * Debug utility to check what's actually stored in AsyncStorage
 */

import AsyncStorage from '@react-native-async-storage/async-storage';
import { createComponentLogger } from '../core/Logger';

const logger = createComponentLogger('StorageDebug');

export async function debugStorage() {
  try {
    logger.info('=== STORAGE DEBUG ===');
    
    // Check all relevant keys
    const keys = [
      'skyward_auth_info',
      'skyward_session_codes', 
      'baseUrl',
      'dwd',
      'wfaacl',
      'encses',
      'User-Type',
      'sessionid'
    ];

    for (const key of keys) {
      const value = await AsyncStorage.getItem(key);
      logger.info(`Storage key: ${key}`, {
        method: 'debugStorage',
        hasValue: !!value,
        valueLength: value?.length || 0,
        valuePreview: value ? (value.length > 50 ? value.substring(0, 50) + '...' : value) : 'null'
      });
    }

    // Get all keys to see what's actually stored
    const allKeys = await AsyncStorage.getAllKeys();
    logger.info('All storage keys', {
      method: 'debugStorage',
      totalKeys: allKeys.length,
      keys: allKeys
    });

    logger.info('=== END STORAGE DEBUG ===');
  } catch (error) {
    logger.error('Failed to debug storage', error as Error);
  }
}
