import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';

type AssignmentCardProps = Assignment & {
  editing: boolean;
};

// Course Name, Teacher Name, Numerical Grade
const AssignmentCard = ({ className, name, category, grade, outOf, dueDate, artificial, editing }: AssignmentCardProps) => {
  return (
    <Link
      href={{
        pathname: '/assignments/[assignment]',
        params: {
          assignment: name,
          class: className,
          name,
          category,
          grade: grade.toString(),
          outOf: outOf.toString(),
          dueDate,
          artificial: artificial.toString(),
          editing: editing.toString()
        }
      }}
      asChild
    >
        <TouchableOpacity  className='w-[100%]'>
            <View className='w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between'>
                <View>
                    <View className="self-start rounded-md bg-highlight px-2 ml-5">
                        <Text className="text-sm text-highlightText font-bold">{category}</Text>
                    </View>
                    <Text className='text-lg text-main font-medium ml-5'>{name}</Text>
                    <Text className='text-xs text-secondary ml-5'>Due {dueDate}</Text>
                </View>
                <View className='flex-row items-center'>
                    <View className="flex-row items-center gap-2 mr-1">
                        <View className={`w-10 h-10 rounded-full border-highlight border-2 items-center justify-center`} >
                            <Text className='text-highlightText font-bold text-sm'>{grade}</Text>
                        </View>
                        <View className="w-[1px] h-10 rounded-full bg-highlight" />
                        <View className={`w-10 h-10 rounded-full bg-highlight items-center justify-center`}>
                            <Text className='text-highlightText font-bold text-sm'>{outOf}</Text>
                        </View>
                    </View>
                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
                
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default AssignmentCard