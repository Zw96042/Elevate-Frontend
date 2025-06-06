import { View, Text, FlatList, ActivityIndicator } from 'react-native'
import React, { useEffect, useState } from 'react'
import AsyncStorage from '@react-native-async-storage/async-storage'
import MessageCard from '@/components/MessageCard';
import { fetchSkywardMessages } from '@/lib/skywardClient';

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

  useEffect(() => {
    const loadMessages = async () => {
      try {
        const user = await AsyncStorage.getItem('skywardUser');
        const pass = await AsyncStorage.getItem('skywardPass');
        const link = await AsyncStorage.getItem('skywardLink');

        if (!user || !pass || !link) {
          console.error("Missing Skyward credentials or link");
          setLoading(false);
          return;
        }

        const data = await fetchSkywardMessages(user, pass, link);
        const sorted = data.sort((a: SkywardMessage, b: SkywardMessage) => new Date(b.date).getTime() - new Date(a.date).getTime());
        setMessages(sorted);
      } catch (err) {
        console.error("Failed to fetch messages:", err);
      } finally {
        setLoading(false);
      }
    };

    loadMessages();
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
        className='mt-4 px-5'
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
      />
    </View>
  );
};

export default Inbox;