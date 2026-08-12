import { useState, useEffect, useCallback, useRef } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth } from '@/lib';
import { MessageService } from '@/lib/services';
import Burnt from 'burnt';
import { logger, Modules } from '@/lib/utils/logger';
import {
  clearInboxDataCache,
  getAccountDataGeneration,
  isAccountDataCurrent,
  writeAccountDataCache,
} from '@/lib/utils/account-data-cache';

// Cache configuration
const INBOX_CACHE_KEY = 'cachedInboxMessages';
const INBOX_TIMESTAMP_KEY = 'cachedInboxTimestamp';
const CACHE_DURATION = 7 * 24 * 60 * 60 * 1000; // 7 days (messages never get removed, so long cache is fine)

interface CachedInboxData {
  messages: Message[];
  lastUpdated: string;
  totalCount: number;
}

export function useInboxCache() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [lastFetchTime, setLastFetchTime] = useState<number>(0);
  const latestLoadID = useRef(0);
  const latestPaginationID = useRef(0);

  // Check if cache is valid
  const isCacheValid = async (generation: number): Promise<boolean> => {
    try {
      const timestampStr = await AsyncStorage.getItem(INBOX_TIMESTAMP_KEY);
      if (!timestampStr) return false;
      
      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();
      const isValid = (now - timestamp) < CACHE_DURATION;
      
      console.log('📧 Inbox cache validity check:', {
        age: Math.round((now - timestamp) / (1000 * 60 * 60)), // hours
        isValid,
        maxAge: Math.round(CACHE_DURATION / (1000 * 60 * 60)) // hours
      });
      
      return isValid && isAccountDataCurrent(generation);
    } catch (error) {
      logger.error(Modules.MESSAGE, 'Inbox cache validity check failed', error);
      return false;
    }
  };

  // Get cached messages
  const getCachedMessages = async (generation: number): Promise<Message[] | null> => {
    try {
      const isValid = await isCacheValid(generation);
      if (!isValid) return null;
      
      const cachedDataStr = await AsyncStorage.getItem(INBOX_CACHE_KEY);
      if (cachedDataStr) {
        const cachedData: CachedInboxData = JSON.parse(cachedDataStr);
        console.log('✅ Using cached inbox messages:', cachedData.messages.length, 'messages');
        return isAccountDataCurrent(generation) ? cachedData.messages : null;
      }
    } catch (error) {
      logger.error(Modules.MESSAGE, 'Failed to read inbox cache', error);
    }
    return null;
  };

  // Cache messages
  const cacheMessages = async (messages: Message[], generation: number): Promise<boolean> => {
    try {
      const cachedData: CachedInboxData = {
        messages,
        lastUpdated: new Date().toISOString(),
        totalCount: messages.length
      };
      
      const written = await writeAccountDataCache([
        [INBOX_CACHE_KEY, JSON.stringify(cachedData)],
        [INBOX_TIMESTAMP_KEY, Date.now().toString()]
      ], generation);
      
      if (written) console.log('💾 Cached inbox messages:', messages.length, 'messages');
      return written;
    } catch (error) {
      logger.error(Modules.MESSAGE, 'Failed to cache inbox messages', error);
      return false;
    }
  };

  // Clear cache (useful for force refresh)
  const clearCache = async (): Promise<void> => {
    try {
      await clearInboxDataCache();
      console.log('🗑️ Inbox cache cleared');
    } catch (error) {
      logger.error(Modules.MESSAGE, 'Failed to clear inbox cache', error);
    }
  };

  // Merge new messages with existing ones (avoiding duplicates)
  const mergeMessages = (existing: Message[], freshFirstPage: Message[]): Message[] => {
    const freshIDs = new Set(freshFirstPage.map(message => message.messageRowId));
    // Fresh rows win so edits to an existing message are not kept stale. Older
    // paginated rows stay available behind the refreshed first page.
    const combined = [
      ...freshFirstPage,
      ...existing.filter(message => !freshIDs.has(message.messageRowId)),
    ];
    return combined.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  };

  // Load messages with caching
  const loadMessagesWithCache = async (forceRefresh: boolean = false): Promise<void> => {
    const requestID = ++latestLoadID.current;
    const generation = getAccountDataGeneration();
    setLoading(true);
    
    const hasCreds = await SkywardAuth.hasCredentials();
    if (!isAccountDataCurrent(generation) || requestID !== latestLoadID.current) return;
    setCredentialsSet(hasCreds);
    
    if (!hasCreds) {
      setMessages([]);
      setLoading(false);
      return;
    }

    try {
      // If not forcing refresh, try cache first
      if (!forceRefresh) {
        const cachedMessages = await getCachedMessages(generation);
        if (!isAccountDataCurrent(generation) || requestID !== latestLoadID.current) return;
        if (cachedMessages !== null) {
          console.log('📧 Using cached inbox messages, no refresh needed');
          setMessages(cachedMessages);
          setLoading(false);
          setLastFetchTime(Date.now());
          
          // Check for new messages in background (don't wait for it)
          void loadNewMessagesInBackground(cachedMessages, generation, requestID);
          return;
        }
      }

      // Load fresh messages using MessageService
      const result = await MessageService.loadMessages();
      if (!isAccountDataCurrent(generation) || requestID !== latestLoadID.current) return;
      
      if (!result.success) {
        throw new Error(result.error || 'Failed to load messages');
      }
      
      setMessages(result.messages);
      await cacheMessages(result.messages, generation);
      setLastFetchTime(Date.now());
      
    } catch (error: any) {
      logger.error(Modules.MESSAGE, 'Error loading messages', error);
      throw error;
    } finally {
      if (requestID === latestLoadID.current) setLoading(false);
    }
  };

  // Load new messages in background and merge with existing
  const loadNewMessagesInBackground = async (
    existingMessages: Message[],
    generation: number,
    requestID: number
  ): Promise<void> => {
    try {
      console.log('🔄 Checking for new messages in background...');
      const result = await MessageService.loadMessages();
      if (!isAccountDataCurrent(generation) || requestID !== latestLoadID.current) return;
      
      const existingByID = new Map(
        existingMessages.map(message => [message.messageRowId, JSON.stringify(message)])
      );
      const firstPageChanged = result.success && result.messages.some(message =>
        existingByID.get(message.messageRowId) !== JSON.stringify(message)
      ) || result.success && result.messages.length === 0 && existingMessages.length > 0;
      if (result.success && firstPageChanged) {
        console.log('📧 Found new messages, updating cache...');
        const mergedMessages = result.messages.length === 0
          ? []
          : mergeMessages(existingMessages, result.messages);
        setMessages(mergedMessages);
        await cacheMessages(mergedMessages, generation);
      }
    } catch (error) {
      logger.debug(Modules.MESSAGE, 'Background message check failed');
    }
  };

  // Load more messages (for pagination)
  const handleLoadMoreMessages = async (): Promise<void> => {
    if (loadingMore || messages.length === 0) return;
    const requestID = ++latestPaginationID.current;
    const generation = getAccountDataGeneration();
    
    setLoadingMore(true);
    const lastMessage = messages[messages.length - 1];
    
    try {
      const result = await MessageService.loadMoreMessages(lastMessage.messageRowId, 10);
      if (!isAccountDataCurrent(generation) || requestID !== latestPaginationID.current) return;
      
      if (result.success && result.messages.length > 0) {
        const updatedMessages = [...messages, ...result.messages];
        setMessages(updatedMessages);
        await cacheMessages(updatedMessages, generation);
      }
    } catch (err) {
      logger.error(Modules.MESSAGE, 'Failed to fetch more messages', err);
    } finally {
      if (requestID === latestPaginationID.current) setLoadingMore(false);
    }
  };

  // Force refresh (clears cache and reloads)
  const forceRefresh = async (): Promise<void> => {
    setRefreshing(true);
    await clearCache();
    try {
      await loadMessagesWithCache(true);
    } finally {
      setRefreshing(false);
    }
  };

  // Handle credential events
  useEffect(() => {
    const handleValidCreds = async () => {
      setCredentialsSet(true);
      setMessages([]);
      await clearCache();
      await loadMessagesWithCache(true);
    };

    const handleInvalidCreds = async () => {
      latestLoadID.current += 1;
      latestPaginationID.current += 1;
      setCredentialsSet(false);
      setMessages([]);
      setLoading(false);
      setLoadingMore(false);
      await clearCache();
    };

    const subValid = DeviceEventEmitter.addListener('credentialsAdded', handleValidCreds);
    const subInvalid = DeviceEventEmitter.addListener('credentialsInvalid', handleInvalidCreds);
    
    return () => {
      subValid.remove();
      subInvalid.remove();
    };
  }, []);

  // Get cache age in minutes
  const getCacheAgeMinutes = async (): Promise<number | null> => {
    try {
      const timestampStr = await AsyncStorage.getItem(INBOX_TIMESTAMP_KEY);
      if (!timestampStr) return null;
      
      const timestamp = parseInt(timestampStr, 10);
      const now = Date.now();
      return Math.round((now - timestamp) / (1000 * 60));
    } catch (error) {
      return null;
    }
  };

  return {
    messages,
    setMessages,
    loading,
    setLoading,
    refreshing,
    setRefreshing,
    credentialsSet,
    setCredentialsSet,
    loadingMore,
    loadMessagesWithCache,
    handleLoadMoreMessages,
    forceRefresh,
    clearCache,
    lastFetchTime,
    getCacheAgeMinutes
  };
}
