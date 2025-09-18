/**
 * Skyward Client (Legacy)
 * Wrapper around new ApiClient for backward compatibility
 * This maintains existing function signatures while using the new architecture
 */

import { ApiClient } from './core/ApiClient';

/**
 * @deprecated Use ApiClient.fetchMessages() instead
 */
export const fetchSkywardMessages = async (params: {
  dwd: string;
  wfaacl: string;
  encses: string;
  userType?: string;
  sessionid: string;
  baseUrl: string;
}): Promise<any> => {
  const response = await ApiClient.fetchMessages();
  if (!response.success) {
    throw new Error(response.error || 'Failed to fetch messages');
  }
  return response.data;
};

/**
 * @deprecated Use ApiClient.fetchMoreMessages() instead
 */
export const fetchMoreSkywardMessages = async (
  sessionCodes: {
    dwd: string;
    wfaacl: string;
    encses: string;
    sessionid: string;
    userType?: string;
  },
  lastMessageId: string,
  limit: number
): Promise<any> => {
  const response = await ApiClient.fetchMoreMessages(1); // Convert to page-based
  if (!response.success) {
    throw new Error(response.error || 'Failed to fetch more messages');
  }
  return response.data;
};

/**
 * @deprecated Use ApiClient.fetchReportCard() instead
 */
export const fetchSkywardReportCard = async (params: {
  dwd: string;
  wfaacl: string;
  encses: string;
  userType?: string;
  sessionid: string;
  baseUrl: string;
}): Promise<any> => {
  const response = await ApiClient.fetchReportCard();
  if (!response.success) {
    throw new Error(response.error || 'Failed to fetch report card');
  }
  
  // Return in expected format for backward compatibility
  return {
    success: response.success,
    data: response.data,
    error: response.error
  };
};
