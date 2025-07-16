import { useState, useEffect, useCallback } from 'react';
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { authenticate } from '@/lib/authHandler';
import { loadMessages } from '@/lib/loadMessageHandler';
import { loadMoreMessages } from '@/lib/loadMoreMessagesHandler';
import Burnt from 'burnt';

export function useInboxLogic() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const handleLoadMessages = async () => {
    if (!credentialsSet) {
      setMessages([]);
      setLoading(false);
      return;
    }
    const result = await loadMessages();
    setMessages(result.messages);
    setLoading(false);
  };

  const handleLoadMoreMessages = async () => {
    if (loadingMore || messages.length === 0) return;
    setLoadingMore(true);
    const lastMessage = messages[messages.length - 1];
    try {
      const result = await loadMoreMessages(lastMessage.messageRowId, 6);
      setMessages(prev => [...prev, ...result.messages]);
    } catch (err) {
      console.error("Failed to fetch more messages", err);
    } finally {
      setLoadingMore(false);
    }
  };

  useEffect(() => {
    const handleValidCreds = async () => {
      const hasCreds = await SkywardAuth.hasCredentials();
      if (hasCreds) {
        setCredentialsSet(true);
        const result = await loadMessages();
        setMessages(result.messages);
      }
    };

    const handleInvalidCreds = () => {
      setCredentialsSet(false);
      setMessages([]);
    };

    const subValid = DeviceEventEmitter.addListener('credentialsAdded', handleValidCreds);
    const subInvalid = DeviceEventEmitter.addListener('credentialsInvalid', handleInvalidCreds);
    return () => {
      subValid.remove();
      subInvalid.remove();
    };
  }, []);

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
    handleLoadMessages,
    handleLoadMoreMessages,
  };
}