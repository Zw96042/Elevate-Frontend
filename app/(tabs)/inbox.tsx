import React, { useCallback } from 'react';
import {
  View, Text, FlatList, ActivityIndicator, TouchableOpacity
} from 'react-native';
import { useFocusEffect } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import he from 'he';

import MessageCard from '@/components/MessageCard';
import SkeletonMessage from '@/components/SkeletonMessage';
import { useSettingSheet } from '@/context/SettingSheetContext';
import { SkywardAuth } from '@/lib/skywardAuthInfo';
import { authenticate } from '@/lib/authHandler';
import { loadMessages } from '@/lib/loadMessageHandler';
import Burnt from 'burnt';
import { useColorScheme } from 'react-native';
import { useInboxLogic } from '@/hooks/useInboxLogic';

const Inbox = () => {
  const {
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
    handleLoadMoreMessages
  } = useInboxLogic();

  const { settingSheetRef } = useSettingSheet();
  const colorScheme = useColorScheme();
  const indicatorColor = colorScheme === 'dark' ? '#ffffff' : '#000000';

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
          if (result.messages.length === 0) throw new Error('Session Expired');
          setMessages(result.messages);
        } catch (error: any) {
          Burnt.toast({ title: "Session expired", preset: "none" });
          if (error.message === 'Session Expired') {
            await authenticate();
            try {
              const retryResult = await loadMessages();
              if (retryResult.success === false) throw new Error(retryResult.error);
              setMessages(retryResult.messages);
              Burnt.toast({ title: "Re-authenticated", preset: "done" });
            } catch {
              Burnt.toast({ title: "Error re-authenticating", preset: "error" });
            }
          }
        } finally {
          setLoading(false);
        }
       
      };
      fetchMessages();
    }, [])
  );

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
                <>
                  Your credentials are either invalid or not found.{' '}
                  <Text
                    className="text-blue-400 underline"
                    onPress={() => settingSheetRef.current?.snapToIndex(0)}
                  >
                    Update your settings
                  </Text>{' '}
                  to proceed.
                </>
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