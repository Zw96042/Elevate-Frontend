import { View, Text, TouchableOpacity } from 'react-native'
import React, { useMemo } from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';

// Course Name, Teacher Name, Numerical Grade
const MessageCard = ({ subject, className, from, date, content, administrator }: Message & { administrator: boolean }) => {
  // Memoize truncated subject to prevent recalculation
  const truncatedSubject = useMemo(() => {
    return subject.length > 35
      ? subject.slice(0, 35).replace(/\s+\S*$/, '') + '...'
      : subject;
  }, [subject]);

  // Memoize date display text
  const dateDisplayText = useMemo(() => {
    return administrator ? date : `${from} • ${date}`;
  }, [administrator, date, from]);

  return (
    <Link
      href={{
        pathname: '/inbox/[message]' as any,
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
                    <Text className='text-lg text-main font-medium ml-5'>{truncatedSubject}</Text>
                    <Text className='text-xs text-secondary ml-5'>{dateDisplayText}</Text>
                </View>
                <View className='flex-row items-center'>
                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
                
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default React.memo(MessageCard)