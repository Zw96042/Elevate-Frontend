// lib/academicHistoryClient.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';

const config = require('./development.config.js');

interface AcademicHistoryResult {
  success: boolean;
  data?: any;
  error?: string;
}

export const fetchAcademicHistory = async (): Promise<AcademicHistoryResult> => {
  try {
    // Get session codes from AsyncStorage
    const dwd = await AsyncStorage.getItem('dwd');
    const wfaacl = await AsyncStorage.getItem('wfaacl');
    const encses = await AsyncStorage.getItem('encses');

    const allSessionCodesExist = dwd && wfaacl && encses;

    if (!allSessionCodesExist) {
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Authentication failed:', authResult.error);
        return { success: false, error: authResult.error };
      }
      return await fetchAcademicHistory(); // retry with new credentials
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
      if (response.status === 401) {
        throw new Error('Session Expired');
      } else {
        throw new Error(`Failed to fetch academic history: ${response.statusText}`);
      }
    }

    const responseData = await response.json();
    console.log('Raw API response:', responseData);
    
    // Extract the actual academic data from the response
    // The API returns { success: true, data: { "2024-2025": {...}, "alt": {...} } }
    // We need just the data part: { "2024-2025": {...}, "alt": {...} }
    const academicData = responseData.data || responseData;
    console.log('Extracted academic data:', academicData);
    
    return { success: true, data: academicData };
  } catch (error: any) {
    console.error('Error fetching academic history:', error);
    
    // Handle session expiry by re-authenticating
    if (error.message?.toLowerCase().includes('session expired')) {
      console.log('Session expired, attempting to re-authenticate...');
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Re-authentication failed:', authResult.error);
        return { success: false, error: authResult.error };
      }
      console.log('Re-authentication successful, retrying academic history fetch...');
      return await fetchAcademicHistory(); // retry after re-auth
    }
    
    return { success: false, error: error.message || 'Unknown error' };
  }
};
