import { View, Text, TouchableOpacity, ScrollView } from 'react-native'
import React, { useLayoutEffect } from 'react'
import { useLocalSearchParams, useNavigation, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

const MessageDetails = () => {
  const router = useRouter();
  const { message, className, from, date, content } = useLocalSearchParams();
  return (
    <View className='bg-primary flex-1'>
        <ScrollView className='flex-1'>
            <View>
                <Text className='text-slate-400 font-bold ml-4 mt-3 text-sm'>Subject</Text>
                <View className="bg-gray-800 rounded-lg p-3 mx-4 mt-3">
                    <Text className="text-slate-200 leading-5">
                        {message}
                    </Text>
                </View>

                <View className='flex-row items-center'>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-slate-400 font-bold text-sm mb-4'>From</Text>
                        <View className="bg-gray-800 rounded-lg p-3 w-full">
                            <Text className="text-slate-200 leading-5">
                                {from}
                            </Text>
                        </View>
                    </View>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-slate-400 font-bold text-sm mb-4'>Date</Text>
                        <View className="bg-gray-800 rounded-lg p-3 w-full">
                            <Text className="text-slate-200 leading-5">
                                {date}
                            </Text>
                        </View>
                    </View>
                
                </View>
                <Text className='text-slate-400 font-bold ml-4 mt-3 text-sm'>Message</Text>
                <View className="bg-gray-800 rounded-lg p-3 mx-4 mt-3">
                    <Text className="text-slate-200 leading-5">
                        {content}
                    </Text>
                </View>
            </View>
        </ScrollView>
    </View>
  )
}

export default MessageDetails