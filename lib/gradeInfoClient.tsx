// lib/gradeInfoClient.tsx
import AsyncStorage from '@react-native-async-storage/async-storage';
import { authenticate } from './authHandler';
import { fetchGradeInfoDirect, GradeInfoParams as DirectGradeInfoParams } from './skywardGradeInfoClient';

const config = require('./development.config.js');

export interface GradeInfoParams {
  stuId: string;
  corNumId: string;
  section: string;
  gbId: string;
  bucket: string;  // e.g. TERM 3, SEM 1
  customUrl?: string;
}

interface GradeInfoResult {
  success: boolean;
  data?: any;
  error?: string;
  retryCount?: number;
  wasAuthError?: boolean;
}

export const fetchGradeInfo = async (
  params: GradeInfoParams,
  retryCount: number = 0
): Promise<GradeInfoResult> => {
  try {
    if (retryCount > 1) {
      return { success: false, error: 'Max retry attempts reached' };
    }

    console.log('📋 Fetching grade info directly from Skyward...');
    console.log('📋 Grade info parameters:', {
      stuId: params.stuId,
      corNumId: params.corNumId,
      section: params.section,
      gbId: params.gbId,
      bucket: params.bucket,
      hasRequiredParams: !!(params.stuId && params.corNumId && params.section && params.gbId)
    });

    // Validate required parameters
    if (!params.stuId || !params.corNumId || !params.section || !params.gbId || !params.bucket) {
      console.log('❌ Missing required parameters for fetchGradeInfo:', {
        stuId: !!params.stuId,
        corNumId: !!params.corNumId,
        section: !!params.section,
        gbId: !!params.gbId,
        bucket: !!params.bucket
      });
      return { success: false, error: 'Missing required parameters' };
    }

    // Convert params to match the direct client interface
    const directParams: DirectGradeInfoParams = {
      stuId: params.stuId,
      corNumId: params.corNumId,
      section: params.section,
      gbId: params.gbId,
      bucket: params.bucket,
      customUrl: params.customUrl,
      entityId: '',
      track: '',
      dialogLevel: '',
      subjectId: '',
      isEoc: 'no',
    };

    // Get base URL
    const baseUrl = await AsyncStorage.getItem('skywardBaseURL');
    console.log('📋 Base URL from storage:', baseUrl);
    if (!baseUrl) {
      console.log('📋 No base URL found, attempting authentication...');
      // Try to authenticate first
      const authResult = await authenticate();
      if (!authResult.success) {
        console.log('❌ Authentication failed:', authResult);
        return { success: false, error: 'Authentication required and failed' };
      }
      console.log('✅ Authentication successful, retrying grade info fetch...');
      return await fetchGradeInfo(params, retryCount + 1);
    }

    // Call direct client
    console.log('📋 Calling fetchGradeInfoDirect with params:', directParams);
    const result = await fetchGradeInfoDirect(directParams, baseUrl);
    
    console.log('📋 Raw result from fetchGradeInfoDirect:', JSON.stringify(result, null, 2));
    console.log('✅ Direct grade info fetch successful');
    // Match the expected backend response structure
    return { 
      success: true, 
      data: {
        success: true,
        data: result
      }, 
      retryCount, 
      wasAuthError: false 
    };

  } catch (error: any) {
    console.error('❌ Error fetching grade info directly:', error.message);
    console.error('❌ Full error object:', error);
    console.error('❌ Error stack:', error.stack);
    
    // Handle session expiry with retry logic
    if (error.code === 'SESSION_EXPIRED' && retryCount === 0) {
      console.log('🔄 Session expired, retrying with fresh authentication...');
      await AsyncStorage.multiRemove(['dwd', 'wfaacl', 'encses', 'sessionid']);
      const authResult = await authenticate();
      if (authResult.success) {
        return await fetchGradeInfo(params, retryCount + 1);
      } else {
        return { 
          success: false, 
          error: 'Re-authentication failed', 
          retryCount: retryCount + 1, 
          wasAuthError: true 
        };
      }
    }

    return { 
      success: false, 
      error: error.message || 'Unknown error', 
      retryCount, 
      wasAuthError: false 
    };
  }
};