import { View, Text } from 'react-native'
import React from 'react'

// Course Name, Teacher Name, Numerical Grade
const AssignmentDateCard = ({ className, name, category, grade, outOf, dueDate }: Assignment) => {
  return (
    <View className='w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between'>
        <View>
            
            <Text className='text-lg text-main font-medium ml-5'>{name}</Text>
            <View className='flex-row'>
              <Text className='text-sm text-secondary ml-5'>{className} • </Text>
              <View className="self-start rounded-md bg-highlight px-2">
                  <Text className="text-sm text-highlightText font-bold">{category}</Text>
              </View>
              <Text className='text-sm text-secondary'> • {((grade/outOf)*100).toFixed(1)}%</Text>
            </View>
        </View>
        <View className='flex-row items-center'>
            <View className="flex-row items-center gap-2 mr-4">
                <View className={`w-10 h-10 rounded-full border-highlight border-2 items-center justify-center`} >
                    <Text className='text-highlightText font-bold text-sm'>{grade}</Text>
                </View>
                <View className="w-[1px] h-10 rounded-full bg-highlight" />
                <View className={`w-10 h-10 rounded-full bg-highlight items-center justify-center`}>
                    <Text className='text-highlightText font-bold text-sm'>{outOf}</Text>
                </View>
            </View>
        </View>
    </View>
  )
}

export default AssignmentDateCard