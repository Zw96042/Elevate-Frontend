import React, { useCallback, useEffect, useRef } from 'react';
import {
  View, Text, FlatList, ActivityIndicator, TouchableOpacity, DeviceEventEmitter, RefreshControl
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import he from 'he';

import MessageCard from '@/components/MessageCard';
import SkeletonMessage from '@/components/SkeletonMessage';
import ErrorDisplay from '@/components/ErrorDisplay';
import LoginPrompt from '@/components/LoginPrompt';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { useColorScheme } from 'react-native';
import { useInboxCache } from '@/hooks/useInboxCache';

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
  const indicatorColor = colorScheme === 'dark' ? '#ffffff' : '#000000';
  const [error, setError] = React.useState<string | null>(null);
  const isInitialLoad = useRef(true);

  // Listen for credential updates
  useEffect(() => {
    const credentialsListener = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      // Auto-refresh when credentials are verified
      setError(null);
      await loadMessagesWithCache(false);
    });

    return () => {
      credentialsListener.remove();
    };
  }, []);

  const fetchMessages = async () => {
    setError(null);
    
    try {
      await loadMessagesWithCache(false);
    } catch (error: any) {
      console.error('Error loading messages:', error);
      setError(error.message || 'Unable to load messages. Please check your connection and try again.');
    }
  };

  // Only load messages on initial mount, not every focus
  useFocusEffect(
    useCallback(() => {
      if (isInitialLoad.current) {
        fetchMessages();
        isInitialLoad.current = false;
      }
    }, [])
  );

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
          className="mt-4 px-5 mb-[5rem]"
          contentContainerStyle={{ flexGrow: 1 }}
          data={Array.from({ length: 8 })}
          keyExtractor={(_, i) => `skeleton-${i}`}
          renderItem={() => <SkeletonMessage />}
          ItemSeparatorComponent={() => <View className="h-4" />}
        />
      ) : (
        <FlatList
          className="mt-4 px-5 mb-[5rem]"
          contentContainerStyle={{ flexGrow: 1 }}
          data={messages}
          renderItem={({ item }) => (
            <MessageCard
              subject={item.subject}
              messageRowId={item.messageRowId}
              className={item.className}
              from={item.from}
              date={item.date}
              content={he.decode(item.content)}
              administrator={item.subject === "Administrator Message"}
            />
          )}
          keyExtractor={(item, i) => `${item.subject}-${i}`}
          ItemSeparatorComponent={() => <View className="h-4" />}
          refreshing={refreshing}
          onRefresh={async () => {
            setError(null);
            await forceRefresh();
          }}
          onEndReached={messages.length > 8 ? handleLoadMoreMessages : undefined}
          onEndReachedThreshold={0.1}
          ListEmptyComponent={
            <View className="flex-1 justify-center items-center py-12">
              <Ionicons name="mail-outline" size={64} color="#9ca3af" />
              <Text className="text-center text-gray-500 mt-4 text-lg">
                No messages found
              </Text>
              <Text className="text-center text-gray-400 mt-2">
                Check back later for new messages
              </Text>
            </View>
          }
          ListFooterComponent={
            loadingMore ? (
              <View className="py-4">
                <ActivityIndicator size="small" color={indicatorColor} />
              </View>
            ) : null
          }
        />
      )}
    </View>
  );
};

export default Inbox;