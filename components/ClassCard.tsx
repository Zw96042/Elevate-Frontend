import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';

// Course Name, Teacher Name, Numerical Grade
const ClassCard = ({name, teacher, s1, s2} : Class) => {
    const percentage = s1;
    const letter = percentage >= 90 ? "A" : percentage >= 80 ? "B" : percentage >= 70 ? "C" : "D";
    let bgColor = "bg-blue-400";
    if (letter === "B") bgColor = "bg-yellow-400";
    else if (letter === "C" || letter === "D") bgColor = "bg-red-300";
  return (
    <Link href={`/classes/${name}`} asChild>
        <TouchableOpacity  className='w-[100%]'>
            <View className='w-full h-28 rounded-lg bg-slate-800 flex-row items-center justify-between'>
                <View>
                    <Text className='text-lg text-gray-200 font-normal ml-5'>{formatClassName(name)}</Text>
                    <Text className='text-sm text-gray-300 ml-5'>{formatClassName(teacher)}</Text>
                </View>
                <View className="flex-row items-center gap-4">
                    <View className="items-center">
                        <View className={`w-10 h-10 rounded-full ${bgColor} items-center justify-center`}>
                            <Text className="text-white font-semibold">{letter}</Text>
                        </View>
                        <Text className="text-xs text-gray-200 mt-1">{s1.toFixed(1)}%</Text>
                    </View>

                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default ClassCard