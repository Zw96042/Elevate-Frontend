import { View, Text, FlatList, ActivityIndicator } from 'react-native';
import React, { useEffect, useState, useCallback } from 'react';
import AsyncStorage from '@react-native-async-storage/async-storage';
import MessageCard from '@/components/MessageCard';
import { loadMessages } from '@/lib/loadMessageHandler';
import { loadMoreMessages } from '@/lib/loadMoreMessagesHandler';
import { Link as RouterLink } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { SkywardAuth } from '@/lib/skywardAuthInfo';


const Inbox = () => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);

  const handleLoadMessages = async () => {
    const result = await loadMessages();
    // setCredentialsSet(result.credentialsSet);
    setMessages(result.messages);
  };

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
        if (hasCreds) {
          const result = await loadMessages();
          setMessages(result.messages);
        }
        setLoading(false);
      };

      fetchMessages();
    }, [])
  );

  return (
    <View className="bg-primary flex-1">
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Inbox</Text>
      </View>
      {loading ? (
        <View className="flex-1 justify-center items-center bg-primary">
          <ActivityIndicator size="large" color="#ffffff" />
        </View>
      ) : (
        <FlatList
          className="mt-4 px-5 mb-24"
          data={messages}
          renderItem={({ item }) => (
            <MessageCard
              subject={
                item.subject.length > 35
                  ? item.subject.slice(0, 35).replace(/\s+\S*$/, '') + '...'
                  : item.subject
              }
              messageRowId={item.messageRowId}
              className={item.className}
              from={item.from}
              date={item.date}
              content={item.content}
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
          onEndReached={handleLoadMoreMessages}
          onEndReachedThreshold={0.2}
          ListEmptyComponent={
            <Text className="text-center text-gray-500 mt-10">
              {credentialsSet ? (
                'No messages found.'
              ) : (
                <>
                  No credentials found.{' '}
                  <RouterLink href="/profile" className="text-blue-400 underline">
                    Go to Settings
                  </RouterLink>{' '}
                  to configure your account.
                </>
              )}
            </Text>
          }
          ListFooterComponent={
            loadingMore ? (
              <View className="py-4">
                <ActivityIndicator size="small" color="#ffffff" />
              </View>
            ) : null
          }
        />
      )}
    </View>
  );
};

export default Inbox;