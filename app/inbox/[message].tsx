import { View, Text, Linking } from 'react-native'
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
        const replacedNewlines = content.replace(/\\n/g, '\n');
        
        // Break content into markdown-style tokens
        const parts = replacedNewlines.split(
            /(\*\*.*?\*\*|\[.*?\]\(.*?\)|\n)/g
        );

        return (
            <Text className="text-main leading-5" style={{ lineHeight: 22 }}>
            {parts.map((part, i) => {
                // Bold
                if (part.startsWith('**') && part.endsWith('**')) {
                return (
                    <Text key={i} style={{ fontWeight: 'bold' }}>
                    {part.slice(2, -2)}
                    </Text>
                );
                }

                // Markdown link [text](url)
                const linkMatch = part.match(/^\[(.*?)\]\((.*?)\)$/);
                if (linkMatch) {
                const [, text, url] = linkMatch;
                return (
                    <Text
                    key={i}
                    className='text-blue-400'
                    onPress={() => {
                        // Open in browser
                        Linking.openURL(url).catch(err =>
                        console.error('Failed to open URL:', err)
                        );
                    }}
                    >
                    {text}
                    </Text>
                );
                }

                // Newline
                if (part === '\n') {
                return <Text key={i}>{'\n'}</Text>;
                }

                // Regular text
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