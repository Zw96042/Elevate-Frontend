import { useState, useEffect, useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { authenticate } from '@/lib/authHandler';
import { loadMessages } from '@/lib/loadMessageHandler';
import { loadMoreMessages } from '@/lib/loadMoreMessagesHandler';
import Burnt from 'burnt';

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

  // Check if cache is valid
  const isCacheValid = async (): Promise<boolean> => {
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
      
      return isValid;
    } catch (error) {
      console.error('❌ Inbox cache validity check failed:', error);
      return false;
    }
  };

  // Get cached messages
  const getCachedMessages = async (): Promise<Message[] | null> => {
    try {
      const isValid = await isCacheValid();
      if (!isValid) return null;
      
      const cachedDataStr = await AsyncStorage.getItem(INBOX_CACHE_KEY);
      if (cachedDataStr) {
        const cachedData: CachedInboxData = JSON.parse(cachedDataStr);
        console.log('✅ Using cached inbox messages:', cachedData.messages.length, 'messages');
        return cachedData.messages;
      }
    } catch (error) {
      console.error('❌ Failed to get cached inbox messages:', error);
    }
    return null;
  };

  // Cache messages
  const cacheMessages = async (messages: Message[]): Promise<void> => {
    try {
      const cachedData: CachedInboxData = {
        messages,
        lastUpdated: new Date().toISOString(),
        totalCount: messages.length
      };
      
      await AsyncStorage.multiSet([
        [INBOX_CACHE_KEY, JSON.stringify(cachedData)],
        [INBOX_TIMESTAMP_KEY, Date.now().toString()]
      ]);
      
      console.log('💾 Cached inbox messages:', messages.length, 'messages');
    } catch (error) {
      console.error('❌ Failed to cache inbox messages:', error);
    }
  };

  // Clear cache (useful for force refresh)
  const clearCache = async (): Promise<void> => {
    try {
      await AsyncStorage.multiRemove([INBOX_CACHE_KEY, INBOX_TIMESTAMP_KEY]);
      console.log('🗑️ Inbox cache cleared');
    } catch (error) {
      console.error('❌ Failed to clear inbox cache:', error);
    }
  };

  // Merge new messages with existing ones (avoiding duplicates)
  const mergeMessages = (existing: Message[], newMessages: Message[]): Message[] => {
    const existingIds = new Set(existing.map(msg => msg.messageRowId));
    const uniqueNewMessages = newMessages.filter(msg => !existingIds.has(msg.messageRowId));
    
    // Combine and sort by date (newest first)
    const combined = [...existing, ...uniqueNewMessages];
    return combined.sort((a, b) => new Date(b.date).getTime() - new Date(a.date).getTime());
  };

  // Load messages with caching
  const loadMessagesWithCache = async (forceRefresh: boolean = false): Promise<void> => {
    setLoading(true);
    
    const hasCreds = await SkywardAuth.hasCredentials();
    setCredentialsSet(hasCreds);
    
    if (!hasCreds) {
      setMessages([]);
      setLoading(false);
      return;
    }

    try {
      // If not forcing refresh, try cache first
      if (!forceRefresh) {
        const cachedMessages = await getCachedMessages();
        if (cachedMessages && cachedMessages.length > 0) {
          console.log('📧 Using cached inbox messages, no refresh needed');
          setMessages(cachedMessages);
          setLoading(false);
          setLastFetchTime(Date.now());
          
          // Check for new messages in background (don't wait for it)
          loadNewMessagesInBackground(cachedMessages);
          return;
        }
      }

      // Load fresh messages
      const result = await loadMessages();
      if (result.messages.length === 0) throw new Error('Session Expired');
      
      setMessages(result.messages);
      await cacheMessages(result.messages);
      setLastFetchTime(Date.now());
      
    } catch (error: any) {
      console.error('Error loading messages:', error);
      
      if (error.message === 'Session Expired') {
        try {
          await authenticate();
          const retryResult = await loadMessages();
          if (retryResult.success === false) throw new Error(retryResult.error);
          
          setMessages(retryResult.messages);
          await cacheMessages(retryResult.messages);
          Burnt.toast({ title: "Re-authenticated", preset: "done", duration: 2 });
        } catch (retryError) {
          throw new Error('Unable to authenticate with Skyward. Please check your credentials.');
        }
      } else {
        throw new Error('Unable to load messages. Please check your connection and try again.');
      }
    } finally {
      setLoading(false);
    }
  };

  // Load new messages in background and merge with existing
  const loadNewMessagesInBackground = async (existingMessages: Message[]): Promise<void> => {
    try {
      console.log('🔄 Checking for new messages in background...');
      const result = await loadMessages();
      
      if (result.messages.length > existingMessages.length) {
        console.log('📧 Found new messages, updating cache...');
        const mergedMessages = mergeMessages(existingMessages, result.messages);
        setMessages(mergedMessages);
        await cacheMessages(mergedMessages);
      }
    } catch (error) {
      console.log('⚠️ Background message check failed (this is okay):', error);
    }
  };

  // Load more messages (for pagination)
  const handleLoadMoreMessages = async (): Promise<void> => {
    if (loadingMore || messages.length === 0) return;
    
    setLoadingMore(true);
    const lastMessage = messages[messages.length - 1];
    
    try {
      const result = await loadMoreMessages(lastMessage.messageRowId, 10);
      const updatedMessages = [...messages, ...result.messages];
      setMessages(updatedMessages);
      await cacheMessages(updatedMessages);
    } catch (err) {
      console.error("Failed to fetch more messages", err);
    } finally {
      setLoadingMore(false);
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
      await loadMessagesWithCache(false);
    };

    const handleInvalidCreds = async () => {
      setCredentialsSet(false);
      setMessages([]);
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
