import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';

// Course Name, Teacher Name, Numerical Grade
const MessageCard = ({ subject, className, from, date, content, administrator }: Message & { administrator: boolean }) => {
  return (
    <Link
      href={{
        pathname: '/inbox/[message]',
        params: {
          message: subject,
          className,
          from,
          date,
          content
        }
      }}
      asChild
    >
        <TouchableOpacity  className='w-[100%]'>

            <View className='w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between'>
                <View>
                    {!administrator && (
                      <View className="self-start rounded-md bg-highlight px-2 ml-5">
                        <Text className="text-sm text-highlightText font-bold">{className}</Text>
                      </View>
                    )}
                    <Text className='text-lg text-main font-medium ml-5'>{subject.length > 35
                      ? subject.slice(0, 35).replace(/\s+\S*$/, '') + '...'
                      : subject}
                    </Text>
                    <Text className='text-xs text-secondary ml-5'>
                      {administrator ? date : `${from} • ${date}`}
                    </Text>
                </View>
                <View className='flex-row items-center'>
                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
                
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default MessageCard