import { View, Text } from 'react-native'
import { ScrollView } from 'react-native-gesture-handler'
import React from 'react'
import { useLocalSearchParams, useRouter } from 'expo-router';

const MessageDetails = () => {
  const router = useRouter();
  const params = useLocalSearchParams();
  const { message, className, from, date, content } = params as {
    message: string;
    className: string;
    from: string;
    date: string;
    content: string | { parts: { type: string; text: string }[] }[];
  };
  
  const renderFormattedContent = (content: string) => {
    // console.log(content);
    const replacedNewlines = content.replace(/\\n/g, '\n');
    const parts = replacedNewlines.split(/(\*\*.*?\*\*)/g);

    return (
      <Text className="text-main leading-5" style={{ lineHeight: 22 }}>
        {parts.map((part, i) => {
          if (part.startsWith('**') && part.endsWith('**')) {
            return (
              <Text key={i} style={{ fontWeight: 'bold' }}>
                {part.slice(2, -2)}
              </Text>
            );
          }
          return <Text key={i}>{part}</Text>;
        })}
      </Text>
    );
  };

  return (
    <View className='bg-primary flex-1'>
        <ScrollView
          contentContainerStyle={{ flexGrow: 1 }}
          keyboardShouldPersistTaps="handled"
          showsVerticalScrollIndicator={false}
          onStartShouldSetResponder={() => true}
        >
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
                    {renderFormattedContent(String(content))}
                </View>
            </View>
        </ScrollView>
    </View>
  )
}

export default MessageDetails