import { View, Text, FlatList, ActivityIndicator } from 'react-native'
import React, { useEffect, useState } from 'react'
import AsyncStorage from '@react-native-async-storage/async-storage'
import MessageCard from '@/components/MessageCard';
import { fetchSkywardMessages } from '@/lib/skywardClient';
import { Link as RouterLink } from 'expo-router';

type SkywardMessage = {
  subject: string;
  className: string;
  from: string;
  date: string;
  content: string;
};

const Inbox = () => {
  const [messages, setMessages] = useState<SkywardMessage[]>([]);
  const [loading, setLoading] = useState(true);
  const [credentialsSet, setCredentialsSet] = useState(false);
  const [refreshing, setRefreshing] = useState(false);

  const loadMessages = async () => {
    try {
      // Load session codes individually from AsyncStorage
      const dwd = await AsyncStorage.getItem('dwd');
      const wfaacl = await AsyncStorage.getItem('wfaacl');
      const encses = await AsyncStorage.getItem('encses');
      const userType = await AsyncStorage.getItem('User-Type');
      const sessionid = await AsyncStorage.getItem('sessionid');
      const baseUrl = await AsyncStorage.getItem('baseUrl');

      // Check if all session codes exist
      const allSessionCodesExist = dwd && wfaacl && encses && userType && sessionid && baseUrl;
      setCredentialsSet(!!allSessionCodesExist);

      if (!allSessionCodesExist) {
        console.error("Missing session credentials");
        setMessages([]);
        return;
      }

      // Call your API helper passing the session codes
      const data = await fetchSkywardMessages({ dwd, wfaacl, encses, userType, sessionid, baseUrl });

      const sorted = data.sort((a: SkywardMessage, b: SkywardMessage) =>
        new Date(b.date).getTime() - new Date(a.date).getTime()
      );
      setMessages(sorted);
    } catch (err) {
      console.error("Failed to fetch messages:", err);
      setMessages([]);
    }
  };

  useEffect(() => {
    loadMessages().finally(() => setLoading(false));
  }, []);

  if (loading) {
    return (
      <View className='flex-1 justify-center items-center bg-primary'>
        <ActivityIndicator size="large" color="#ffffff" />
      </View>
    );
  }

  return (
    <View className='bg-primary flex-1'>
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Inbox</Text>
      </View>
      <FlatList
        className='mt-4 px-5 mb-24'
        data={messages}
        renderItem={({ item }) => (
          <MessageCard 
            subject={item.subject.length > 35
              ? item.subject.slice(0, 35).replace(/\s+\S*$/, '') + '...' 
              : item.subject}
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
          await loadMessages();
          setRefreshing(false);
        }}
        ListEmptyComponent={
          <Text className="text-center text-gray-500 mt-10">
            {credentialsSet ? 'No messages found.' : (
              <>
                No credentials found.{" "}
                <RouterLink href="/profile" className="text-blue-400 underline">
                  Go to Settings
                </RouterLink>{" "}
                to configure your account.
              </>
            )}
          </Text>
        }
      />
    </View>
  );
};

export default Inbox;