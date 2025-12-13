import React, { useCallback, useEffect, useRef, useMemo } from 'react';
import {
  View, Text, FlatList, ActivityIndicator, TouchableOpacity, DeviceEventEmitter
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import he from 'he';
import MessageCard from '@/components/MessageCard';
import SkeletonMessage from '@/components/SkeletonMessage';
import ErrorDisplay from '@/components/ErrorDisplay';
import LoginPrompt from '@/components/LoginPrompt';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { useColorScheme } from 'react-native';
import { useInboxCache } from '@/hooks/useInboxCache';
import { logger, Modules } from '@/lib/utils/logger';

const Inbox = () => {
  const {
    messages,
    loading,
    refreshing,
    credentialsSet,
    loadingMore,
    loadMessagesWithCache,
    handleLoadMoreMessages,
    forceRefresh
  } = useInboxCache();

  const { settingSheetRef } = useSettingSheet();
  const colorScheme = useColorScheme();
  const [error, setError] = React.useState<string | null>(null);
  const isInitialLoad = useRef(true);

  // Memoize theme-dependent values
  const indicatorColor = useMemo(() => 
    colorScheme === 'dark' ? '#ffffff' : '#000000', [colorScheme]);

  // Listen for credential updates
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      logger.info(Modules.PAGE_INBOX, 'Credentials added, refreshing messages');
      setError(null);
      await loadMessagesWithCache(false);
    });

    return () => {
      credentialsListener.remove();
    };
  }, []);

  const fetchMessages = useCallback(async () => {
    setError(null);
    logger.debug(Modules.PAGE_INBOX, 'Fetching messages');
    
    try {
      await loadMessagesWithCache(false);
      logger.success(Modules.PAGE_INBOX, 'Messages loaded successfully');
    } catch (error: any) {
      logger.error(Modules.PAGE_INBOX, 'Failed to load messages', error);
      setError(error.message || 'Unable to load messages. Please check your connection and try again.');
    }
  }, [loadMessagesWithCache]);

  // Only load messages on initial mount, not every focus
  useFocusEffect(
    useCallback(() => {
      if (isInitialLoad.current) {
        logger.info(Modules.PAGE_INBOX, 'Initial load on focus');
        fetchMessages();
        isInitialLoad.current = false;
      }
    }, [fetchMessages])
  );

  // Memoized render functions for better FlatList performance
  const renderMessageItem = useCallback(({ item }: { item: any }) => (
    <MessageCard
      subject={item.subject}
      messageRowId={item.messageRowId}
      className={item.className}
      from={item.from}
      date={item.date}
      content={he.decode(item.content)}
      administrator={item.subject === "Administrator Message"}
    />
  ), []);

  const keyExtractor = useCallback((item: any, i: number) => `${item.subject}-${i}`, []);

  const ItemSeparatorComponent = useCallback(() => <View className="h-4" />, []);

  const ListEmptyComponent = useMemo(() => (
    <View className="flex-1 justify-center items-center py-12">
      <Ionicons name="mail-outline" size={64} color="#9ca3af" />
      <Text className="text-center text-gray-500 mt-4 text-lg">
        No messages found
      </Text>
      <Text className="text-center text-gray-400 mt-2">
        Check back later for new messages
      </Text>
    </View>
  ), []);

  const ListFooterComponent = useMemo(() => 
    loadingMore ? (
      <View className="py-4">
        <ActivityIndicator size="small" color={indicatorColor} />
      </View>
    ) : null, [loadingMore, indicatorColor]);

  const onRefreshHandler = useCallback(async () => {
    logger.info(Modules.PAGE_INBOX, 'Pull-to-refresh triggered');
    setError(null);
    await forceRefresh();
  }, [forceRefresh]);

  const onEndReachedHandler = useCallback(() => {
    if (messages.length > 8) {
      logger.debug(Modules.PAGE_INBOX, 'End reached, loading more messages');
      handleLoadMoreMessages();
    }
  }, [messages.length, handleLoadMoreMessages]);

  // Show error display if there's an error
  if (error) {
    return (
      <View className="bg-primary flex-1">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Inbox</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-24">
          <ErrorDisplay
            error={error}
            onRetry={fetchMessages}
            title="Couldn't load messages"
          />
        </View>
      </View>
    );
  }

  // Show login prompt if credentials are not set
  if (!credentialsSet && !loading) {
    return (
      <View className="bg-primary flex-1">
        <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
          <Text className="text-white text-3xl font-bold">Inbox</Text>
          <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
            <Ionicons name='cog-outline' color={'#fff'} size={26} />
          </TouchableOpacity>
        </View>
        <View className="flex-1 mt-20">
          <LoginPrompt
            message="Please log in with your Skyward credentials to view your messages."
            onLoginPress={() => settingSheetRef.current?.snapToIndex(0)}
          />
        </View>
      </View>
    );
  }

  return (
    <View className="bg-primary flex-1">
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Inbox</Text>
        <TouchableOpacity onPress={() => settingSheetRef.current?.snapToIndex(0)}>
          <Ionicons name='cog-outline' color={'#fff'} size={26} />
        </TouchableOpacity>
      </View>
      {loading ? (
        <FlatList
          className="mt-4 px-5"
          contentContainerStyle={{ flexGrow: 1 }}
          data={Array.from({ length: 8 })}
          keyExtractor={(_, i) => `skeleton-${i}`}
          renderItem={() => <SkeletonMessage />}
          ItemSeparatorComponent={() => <View className="h-4" />}
        />
      ) : (
        <FlatList
          className="mt-4 px-5"
          contentContainerStyle={{ flexGrow: 1 }}
          data={messages}
          renderItem={renderMessageItem}
          keyExtractor={keyExtractor}
          ItemSeparatorComponent={ItemSeparatorComponent}
          refreshing={refreshing}
          onRefresh={onRefreshHandler}
          onEndReached={onEndReachedHandler}
          onEndReachedThreshold={0.1}
          ListEmptyComponent={ListEmptyComponent}
          ListFooterComponent={ListFooterComponent}
          removeClippedSubviews={true}
          maxToRenderPerBatch={10}
          windowSize={10}
          initialNumToRender={8}
          getItemLayout={(data, index) => ({
            length: 80 + 16, // MessageCard height + separator
            offset: (80 + 16) * index,
            index,
          })}
        />
      )}
    </View>
  );
};

export default React.memo(Inbox);