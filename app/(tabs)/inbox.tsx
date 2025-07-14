import { View, Text, FlatList, ActivityIndicator, TouchableOpacity } from 'react-native';
import React, { useState, useCallback, useEffect } from 'react';
import MessageCard from '@/components/MessageCard';
import { loadMessages } from '@/lib/loadMessageHandler';
import { loadMoreMessages } from '@/lib/loadMoreMessagesHandler';
import { useFocusEffect } from '@react-navigation/native';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { authenticate } from '@/lib/authHandler';
import * as Burnt from "burnt";
import he from 'he';
import { useColorScheme } from 'react-native';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { Ionicons } from '@expo/vector-icons';
import SkeletonMessage from '@/components/SkeletonMessage';
import { DeviceEventEmitter } from 'react-native';


const Inbox = () => {
  let [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const colorScheme = useColorScheme();
  const indicatorColor = colorScheme === 'dark' ? '#ffffff' : '#000000';

  const { settingSheetRef } = useSettingSheet();

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

  useEffect(() => {
    const subscription = DeviceEventEmitter.addListener('credentialsAdded', async () => {
      const hasCreds = await SkywardAuth.hasCredentials();
      setCredentialsSet(hasCreds);
    });

    return () => subscription.remove();
  }, []);

  useEffect(() => {
    setLoading(true);
    handleLoadMessages();
  }, [credentialsSet]);

  const handleLoadMoreMessages = async () => {
  if (loadingMore || messages.length === 0) {
    console.log('Skipping load more: loadingMore or no messages.');
    return;
  }
  setLoadingMore(true);
  console.log('Loading more messages...');

  const lastMessage = messages[messages.length - 1];
  try {
    const result = await loadMoreMessages(lastMessage.messageRowId, 6);
    console.log('Loaded more messages:', result.messages.length);
    setMessages(prev => [...prev, ...result.messages]);
  } catch (error) {
    console.error('Failed to fetch more messages:', error);
  } finally {
    setLoadingMore(false);
  }
};

  useFocusEffect(
    useCallback(() => {
      const fetchMessages = async () => {
        const hasCreds = await SkywardAuth.hasCredentials();
        setCredentialsSet(hasCreds);
        if (!hasCreds) {
          setLoading(false);
          return;
        }

        try {
          const result = await loadMessages();
          if (result.messages.length === 0) {
            throw new Error('Session Expired');
          }
          setMessages(result.messages);
        } catch (error: any) {
          Burnt.toast({
            title: "Session expired",
            preset: "none"
          });
          if (error.message === 'Session Expired') {
            console.warn('Session expired, re-authenticating...');
            await authenticate();
            try {
              const retryResult = await loadMessages();
              setMessages(retryResult.messages);
              Burnt.toast({
                title: "Re-authenticated",
                preset: "done"
              });
            } catch (retryError) {
              Burnt.toast({
                title: "Error re-authenticating",
                preset: "error"
              });
              console.error('Failed to fetch messages after re-authentication:', retryError);
            }
          } else {
            console.error('Failed to fetch messages:', error);
          }
        } finally {
          setLoading(false);
        }
      };

      fetchMessages();
    }, [])
  );
  // let test = new Array<Message>();

  return (
    <View className="bg-primary flex-1">
      <View className="bg-blue-600 pt-14 pb-4 px-5 flex-row items-center justify-between">
        <Text className="text-white text-3xl font-bold">Inbox</Text>
        <TouchableOpacity
            onPress={() => settingSheetRef.current?.snapToIndex(1)}
          >
          <Ionicons name='cog-outline' color={'#fff'} size={26}/>
        </TouchableOpacity>
      </View>
      {loading ? (
        <FlatList
          className="mt-4 px-5 mb-[5rem]"
          data={Array.from({ length: 8 })}
          keyExtractor={(_, index) => `skeleton-${index}`}
          renderItem={() => <SkeletonMessage />}
          ItemSeparatorComponent={() => <View className="h-4" />}
        />
      ) : (
        <FlatList
          className="mt-4 px-5 mb-[5rem]"
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
          keyExtractor={(item, index) => `${item.subject}-${index}`}
          ItemSeparatorComponent={() => <View className="h-4" />}
          refreshing={refreshing}
          onRefresh={async () => {
            setRefreshing(true);
            await handleLoadMessages();
            setRefreshing(false);
          }}
          onEndReached={messages.length > 8 ? handleLoadMoreMessages : undefined}
          onEndReachedThreshold={0.1}
          ListEmptyComponent={
            <Text className="text-center text-gray-500 mt-10">
              {credentialsSet ? (
                'No messages found.'
              ) : (
                <Text className="text-center text-gray-500">
                  No credentials found.{' '}
                  <Text
                    className="text-blue-400 underline"
                    onPress={() => settingSheetRef.current?.snapToIndex(1)}
                  >
                    Update your settings
                  </Text>{' '}
                  to configure your account.
                </Text>
              )}
            </Text>
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