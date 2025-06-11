import { View, Text, ScrollView } from 'react-native'
import React from 'react'
import { useLocalSearchParams, useRouter } from 'expo-router';

const MessageDetails = () => {
  const router = useRouter();
  const { message, className, from, date, content } = useLocalSearchParams();
  return (
    <View className='bg-primary flex-1'>
        <ScrollView className='flex-1'>
            <View>
                <Text className='text-accent font-bold ml-4 mt-3 text-sm'>Subject</Text>
                <View className="bg-cardColor rounded-lg p-3 mx-4 mt-3">
                    <Text className="text-main leading-5">
                        {message}
                    </Text>
                </View>

                <View className='flex-row items-center'>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-accent font-bold text-sm mb-4'>From</Text>
                        <View className="bg-cardColor rounded-lg p-3 w-full">
                            <Text className="text-main leading-5">
                                {from}
                            </Text>
                        </View>
                    </View>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-accent font-bold text-sm mb-4'>Date</Text>
                        <View className="bg-cardColor rounded-lg p-3 w-full">
                            <Text className="text-main leading-5">
                                {date.slice(date.indexOf(" ")+1)}
                            </Text>
                        </View>
                    </View>
                
                </View>
                <Text className='text-accent font-bold ml-4 mt-3 text-sm'>Message</Text>
                <View className="bg-cardColor rounded-lg p-3 mx-4 mt-3 mb-8">
                    <Text className="text-main leading-5">
                        {content}
                    </Text>
                </View>
            </View>
        </ScrollView>
    </View>
  )
}

export default MessageDetails