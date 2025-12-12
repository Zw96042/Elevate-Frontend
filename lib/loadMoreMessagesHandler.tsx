// lib/loadMoreMessagesHandler.tsx

import AsyncStorage from '@react-native-async-storage/async-storage';
import { fetchMoreSkywardMessages } from './skywardClient';
import { authenticate } from './authHandler';

export const loadMoreMessages = async (
  lastMessageId: string,
  limit: number = 10
): Promise<{
  messages: Message[];
  success: boolean;
}> => {
  const dwd = await AsyncStorage.getItem('dwd');
  const wfaacl = await AsyncStorage.getItem('wfaacl');
  const encses = await AsyncStorage.getItem('encses');
  const userType = await AsyncStorage.getItem('User-Type');
  const sessionid = await AsyncStorage.getItem('sessionid');
  const baseUrl = await AsyncStorage.getItem('skywardBaseURL');

  const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;

  if (!allSessionCodesExist) {
    const authResult = await authenticate();
    if (!authResult.success) {
      console.error('Authentication failed:', authResult.error);
      return { messages: [], success: false };
    }
    return await loadMoreMessages(lastMessageId, limit); // retry with new creds
  }

  try {
    const data = await fetchMoreSkywardMessages(
      {
        dwd,
        wfaacl,
        encses,
        userType,
        sessionid,
        baseUrl,
      },
      lastMessageId,
      limit
    );

    return { messages: data, success: true };
  } catch (error: any) {
    console.error('Failed to fetch more messages:', error.message);
    if (error.message?.toLowerCase().includes('session expired')) {
      const authResult = await authenticate();
      if (!authResult.success) {
        console.error('Re-authentication failed:', authResult.error);
        return { messages: [], success: false };
      }
      return await loadMoreMessages(lastMessageId, limit); // retry after re-auth
    }
    return { messages: [], success: false };
  }
};