import { View, Text, TouchableOpacity, TextInput, Keyboard, TouchableWithoutFeedback, Pressable } from 'react-native'
import React, { useRef, useState } from 'react'
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import formatClassName from '@/utils/formatClassName';
import { Ionicons } from '@expo/vector-icons';
import AsyncStorage from '@react-native-async-storage/async-storage';

const AssignmentDetails = () => {
  const router = useRouter();
  const { class: classParam, name, category, grade, outOf, dueDate, artificial, editing, term } = useLocalSearchParams();
  const formattedClass = formatClassName(classParam?.toString() || '');
//   console.log("term", term);

  const [gradeValue, setGradeValue] = React.useState(() =>
    grade === '*' ? '*' : !isNaN(Number(grade)) ? Number(grade).toFixed(2) : ''
  );
  const [outOfValue, setOutOfValue] = React.useState(() =>
    !isNaN(Number(outOf)) ? Number(outOf).toFixed(2) : ''
  );

  const gradeInputRef = useRef<TextInput>(null);
  const outOfInputRef = useRef<TextInput>(null);

  const [percentage, setPercentage] = useState(() => {
    if (!isNaN(Number(grade)) && !isNaN(Number(outOf)) && Number(outOf) !== 0) {
      return ((Number(grade) / Number(outOf)) * 100).toFixed(2);
    }
    if (grade === '*') return '*';
    return '0.00';
  });

  const handleSave = async () => {
    const className = Array.isArray(classParam) ? classParam[0] : classParam;
    const existing = JSON.parse(await AsyncStorage.getItem('artificialAssignments') ?? '{}');
    const formattedGrade = gradeValue === '*' ? '*' : parseFloat(Number(gradeValue).toFixed(2));
    const formattedOutOf = Number(outOfValue);

    console.log("Updating");
    if (isNaN(formattedOutOf)) return;
    console.log(formattedGrade);
    const updatedAssignment = {
      className,
      name,
      category,
      dueDate,
      grade: formattedGrade,
      outOf: parseFloat(formattedOutOf.toFixed(2)),
      artificial: artificial,
      term: term
    };

    const updatedClassList = [
      updatedAssignment,
      ...(existing[className]?.filter((a: any) => a.name !== name) ?? [])
    ];

    const updated = { ...existing, [className]: updatedClassList };
    console.log("Updated", updated);
    await AsyncStorage.setItem('artificialAssignments', JSON.stringify(updated));
  };

  const saveAndUpdate = async () => {
    await handleSave();
    if (gradeValue === '*') {
      setPercentage('*');
    } else if (!isNaN(Number(gradeValue)) && !isNaN(Number(outOfValue)) && Number(outOfValue) !== 0) {
      setPercentage(((Number(gradeValue) / Number(outOfValue)) * 100).toFixed(2));
    }
    console.log(percentage);
  };

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
        <TouchableWithoutFeedback
          onPress={async () => {
            Keyboard.dismiss();
            if (editing === "true") {
              await handleSave();
            }
          }}
        >
        <View className='bg-primary flex-1'>
            <View>
                <View className='flex-row mt-4'>
                    <View className='flex-1 items-center'>
                        <Text className='text-[#7398e6] font-bold text-sm'>Due Date</Text>
                        <Text className='text-main'>{dueDate?.toString().replaceAll("/", "-") || ''}</Text>
                    </View>
                    <View className='flex-1 items-center'>
                        <Text className='text-[#7398e6] font-bold text-sm'>Percentage</Text>
                        <Text className='text-main'>{percentage}%</Text>
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
                        <Text className='text-accent font-bold text-sm mb-4'>Grade</Text>
                        <Pressable
                          onPress={() => gradeInputRef.current?.focus()}
                          className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
                        >
                            {editing === "true" ? (
                              <TextInput
                                ref={gradeInputRef}
                                className='text-base text-main leading-[1.15rem] py-[0.175rem]'
                                keyboardType='numeric'
                                value={gradeValue}
                                onChangeText={setGradeValue}
                                onBlur={() => {
                                  const num = Number(gradeValue);
                                  if (!isNaN(num)) setGradeValue(num.toFixed(2));
                                }}
                                onSubmitEditing={saveAndUpdate}
                                returnKeyType="done"
                                />
                            ) : (
                              <Text className='text-base text-main'>{gradeValue}</Text>
                            )}
                        </Pressable>
                    </View>
                    <View className='mt-4 px-4 w-[50%]'>
                        <Text className='text-accent font-bold text-sm mb-4'>Total Points</Text>
                        <Pressable
                          onPress={() => outOfInputRef.current?.focus()}
                          className="flex-row items-center justify-between bg-cardColor px-4 py-3 rounded-full"
                        >
                            {editing === "true" ? (
                              <TextInput
                                ref={outOfInputRef}
                                className='text-base text-main leading-[1.15rem] py-[0.175rem]'
                                keyboardType='numeric'
                                value={outOfValue}
                                onChangeText={setOutOfValue}
                                onBlur={() => {
                                  const num = Number(outOfValue);
                                  if (!isNaN(num)) setOutOfValue(num.toFixed(2));
                                }}
                                onSubmitEditing={saveAndUpdate}
                                returnKeyType="done"
                                />
                            ) : (
                              <Text className='text-base text-main'>{outOfValue}</Text>
                            )}
                        </Pressable>
                    </View>
                </View>
                {artificial === "true" && (
                <TouchableOpacity
                    onPress={async () => {
                      const className = Array.isArray(classParam) ? classParam[0] : classParam;
                      const existing = JSON.parse(await AsyncStorage.getItem('artificialAssignments') ?? '{}');
                      const updatedClassList = (existing[className] ?? []).filter((a: any) => a.name !== name);
                      const updated = { ...existing, [className]: updatedClassList };

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
        </TouchableWithoutFeedback>
    </>
  )
}

export default AssignmentDetails