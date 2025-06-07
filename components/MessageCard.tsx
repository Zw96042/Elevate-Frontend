import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';

// Course Name, Teacher Name, Numerical Grade
const MessageCard = ({ subject, className, from, date, content }: Message) => {
  let bgColor = "bg-[#bg-[#3b5795]]";

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
                    <View className="self-start rounded-md bg-[#3b5795] px-2 ml-5">
                        <Text className="text-sm text-[#7398e6] font-bold">{className}</Text>
                    </View>
                    <Text className='text-lg text-gray-300 font-medium ml-5'>{subject}</Text>
                    <Text className='text-xs text-gray-300 ml-5'>{from} • {date}</Text>
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