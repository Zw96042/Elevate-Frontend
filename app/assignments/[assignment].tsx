import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';

const AssignmentDetails = () => {
  const router = useRouter();
  const { class: classParam, name, category, grade, outOf, dueDate, artificial } = useLocalSearchParams();
  const formattedClass = formatClassName(classParam?.toString() || '');

  return (
    <>
        <Stack.Screen
            options={{
            title: decodeURIComponent(name.toString() || 'Assignment'),
            headerStyle: { backgroundColor: '#2563eb' },
            headerTintColor: '#fff',
            headerTitleStyle: {
                fontWeight: 'bold',
                fontSize: 18,
            },
            headerBackTitle: formattedClass.length > 10
                ? formattedClass.slice(0, 10).trim() + '…'
                : formattedClass,
            }}
        />
        <View className='bg-primary flex-1'>
            {/* <View className="bg-blue-600">
                <View className='mt-14'>
                    <TouchableOpacity onPress={() => router.back()} className='flex-row'>
                        <Ionicons name="chevron-back" size={24} color="white" />
                        <Text className='text-white text-xl font-medium'>{formattedClass}</Text>
                    </TouchableOpacity>
                </View>
                <View className='pt-6 pb-4 px-5'>
                    <Text className="text-white text-3xl font-bold">Assignment</Text>
                </View>
            </View> */}
            <View>
                <Text className='text-main font-medium text-xl mt-4 ml-4'>{name?.toString() || ''}</Text>
                <View className='flex-row mt-4'>
                    <View className='flex-1 items-center'>
                        <Text className='text-[#7398e6] font-bold text-sm'>Due Date</Text>
                        <Text className='text-main'>{dueDate?.toString().replaceAll("/", "-") || ''}</Text>
                    </View>
                    <View className='flex-1 items-center'>
                        <Text className='text-[#7398e6] font-bold text-sm'>Percentage</Text>
                        <Text className='text-main'>{((Number(grade) / Number(outOf)) * 100).toFixed(2)}%</Text>
                    </View>
                </View>
                <Text className='text-accent font-bold ml-4 mt-3 text-sm'>Category</Text>
                <View className='mt-4 px-4'>
                    <View className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full">
                        <Text className='text-base text-main'>{category?.toString()}</Text>
                    </View>
                </View>
                <View className='flex-row items-center'>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-accent font-bold text-sm mb-4'>Score</Text>
                        <View className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full">
                            <Text className='text-base text-main'>{Number(grade).toFixed(2)}</Text>
                        </View>
                    </View>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-accent font-bold text-sm mb-4'>Total Points</Text>
                        <View className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full">
                            <Text className='text-base text-main'>{Number(outOf).toFixed(2)}</Text>
                        </View>
                    </View>
                </View>
                {artificial === "true" && (
                <TouchableOpacity
                    onPress={async () => {
                      const className = Array.isArray(classParam) ? classParam[0] : classParam;
                      const existing = JSON.parse(await AsyncStorage.getItem('artificialAssignments') ?? '{}');
                      const updatedClassList = (existing[className] ?? []).filter((a: any) => a.name !== name);
                      const updated = { ...existing, [className]: updatedClassList };
                      console.log(updated);
                      await AsyncStorage.setItem('artificialAssignments', JSON.stringify(updated));
                      router.back();
                    }}
                    className='mt-4 mx-4 bg-cardColor items-center rounded-lg'
                    >
                    <Text className='text-red-500 font-medium py-3 text-lg'>Delete Assignment</Text>
                </TouchableOpacity>
                )}
            </View>
        </View>
    </>
  )
}

export default AssignmentDetails