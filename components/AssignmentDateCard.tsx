import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';

// Course Name, Teacher Name, Numerical Grade
const AssignmentDateCard = ({ className, name, category, grade, outOf, dueDate }: Assignment) => {
  let bgColor = "bg-[#bg-[#3b5795]]";

  return (
    <View className='w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between'>
        <View>
            
            <Text className='text-lg text-gray-300 font-medium ml-5'>{name}</Text>
            <View className='flex-row'>
              <Text className='text-sm text-gray-300 ml-5'>{className} • </Text>
              <View className="self-start rounded-md bg-[#3b5795] px-2">
                  <Text className="text-sm text-[#7398e6] font-bold">{category}</Text>
              </View>
              <Text className='text-sm text-gray-300'> • {((grade/outOf)*100).toFixed(1)}%</Text>
            </View>
        </View>
        <View className='flex-row items-center'>
            <View className="flex-row items-center gap-2 mr-4">
                <View className={`w-10 h-10 rounded-full border-[#3b5795] border-2 items-center justify-center`} >
                    <Text className='text-[#7398e6] font-bold text-sm'>{grade}</Text>
                </View>
                <View className="w-[1px] h-10 rounded-full bg-[#3b5795]" />
                <View className={`w-10 h-10 rounded-full bg-[#3b5795] items-center justify-center`}>
                    <Text className='text-[#7398e6] font-bold text-sm'>{outOf}</Text>
                </View>
            </View>
        </View>
    </View>
  )
}

export default AssignmentDateCard