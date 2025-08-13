// lib/academicHistoryClient.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';

const config = require('./development.config.js');

interface AcademicHistoryResult {
  success: boolean;
  data?: any;
  error?: string;
}

export const fetchAcademicHistory = async (retryCount: number = 0): Promise<AcademicHistoryResult> => {
  try {
    // Prevent infinite retry loops
    if (retryCount > 1) {
      return { success: false, error: 'Max retry attempts reached' };
    }

    // Get session codes from AsyncStorage
    const dwd = await AsyncStorage.getItem('dwd');
    const wfaacl = await AsyncStorage.getItem('wfaacl');
    const encses = await AsyncStorage.getItem('encses');

    const allSessionCodesExist = dwd && wfaacl && encses;

    if (!allSessionCodesExist) {
      console.log('Session codes missing, attempting authentication...');
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Authentication failed:', authResult.error);
        return { success: false, error: authResult.error };
      }
      return await fetchAcademicHistory(retryCount + 1); // retry with new credentials
    }

    // Make the API call to the history endpoint
    const response = await fetch(`http://localhost:3000/api/history`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        dwd,
        wfaacl,
        encses,
      }),
    });

    if (!response.ok) {
      if (response.status === 401 && retryCount === 0) {
        console.log('Session expired, attempting re-authentication...');
        // Clear invalid session codes
        await AsyncStorage.multiRemove(['dwd', 'wfaacl', 'encses']);
        // Try to re-authenticate and retry once
        const authResult = await authenticate();
        if (authResult.success) {
          return await fetchAcademicHistory(retryCount + 1);
        } else {
          return { success: false, error: 'Re-authentication failed' };
        }
      } else {
        throw new Error(`Failed to fetch academic history: ${response.statusText}`);
      }
    }

    const responseData = await response.json();
    
    // Extract the actual academic data from the response
    // The API returns { success: true, data: { "2024-2025": {...}, "alt": {...} } }
    // We need just the data part: { "2024-2025": {...}, "alt": {...} }
    const academicData = responseData.data || responseData;
    
    return { success: true, data: academicData };
  } catch (error: any) {
    console.error('Error fetching academic history:', error);
    
    // Handle session expiry by re-authenticating
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Re-authentication failed:', authResult.error);
        return { success: false, error: authResult.error };
      }
      return await fetchAcademicHistory(); // retry after re-auth
    }
    
    return { success: false, error: error.message || 'Unknown error' };
  }
};
