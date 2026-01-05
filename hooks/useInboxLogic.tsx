import { useState, useEffect, useCallback } from 'react';
import { DeviceEventEmitter } from 'react-native';
import { SkywardAuth, MessageService } from '@/lib';

export function useInboxLogic() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const handleLoadMessages = useCallback(async () => {
    if (!credentialsSet) {
      setMessages([]);
      setLoading(false);
      return;
    }
    
    const result = await MessageService.loadMessages();
    if (result.success) {
      setMessages(result.messages);
    }
    setLoading(false);
  }, [credentialsSet]);

  const handleLoadMoreMessages = useCallback(async () => {
    if (loadingMore || messages.length === 0) return;
    
    setLoadingMore(true);
    const lastMessage = messages[messages.length - 1];
    
    try {
      const result = await MessageService.loadMoreMessages(lastMessage.messageRowId, 6);
      if (result.success) {
        setMessages(prev => [...prev, ...result.messages]);
      }
    } catch (err) {
      console.error("Failed to fetch more messages", err);
    } finally {
      setLoadingMore(false);
    }
  }, [loadingMore, messages]);

  useEffect(() => {
    const handleValidCreds = async () => {
      const hasCreds = await SkywardAuth.hasCredentials();
      if (hasCreds) {
        setCredentialsSet(true);
        const result = await MessageService.loadMessages();
        if (result.success) {
          setMessages(result.messages);
        }
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
