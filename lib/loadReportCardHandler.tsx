/**
 * Report Card Handler (Refactored)
 * Simplified using new ApiClient and CredentialManager systems
 */

import { ApiClient } from './core/ApiClient';
import { CredentialManager } from './core/CredentialManager';
import { authenticate } from './authHandler';
import { ReportCardResult, Course } from '@/interfaces/interfaces';

export const loadReportCard = async (): Promise<ReportCardResult> => {
  try {
    // Check if we have valid credentials
    const hasValidSession = await CredentialManager.hasValidSession();
    
    if (!hasValidSession) {
      const authResult = await authenticate();
      if (!authResult.success) {
        return { courses: [], success: false, error: authResult.error };
      }
    }

    // Use the new ApiClient to fetch report card
    const response = await ApiClient.fetchReportCard();
    
    if (response.success && response.data) {
      return { 
        courses: response.data, 
        success: true 
      };
    } else {
      return { 
        courses: [], 
        success: false, 
        error: response.error || 'Failed to fetch report card data' 
      };
    }
  } catch (error: any) {
    // Handle session expiration
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        return { courses: [], success: false, error: 'Re-authentication failed' };
      }
      // Retry once after re-authentication
      return await loadReportCard();
    }
    
    return { 
      courses: [], 
      success: false, 
      error: error.message || 'Unknown error occurred' 
    };
  }
};
