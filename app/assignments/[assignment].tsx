import { View, Text, TouchableOpacity, TextInput, Keyboard, TouchableWithoutFeedback, Pressable, useColorScheme, Platform } from 'react-native'
import React, { useRef, useState, useMemo, useCallback } from 'react'
import { Stack, useLocalSearchParams, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { generateUniqueId } from '@/utils/uniqueId';

const AssignmentDetails = () => {
  const router = useRouter();
  const theme = useColorScheme();
  const { class: classParam, classId, name, category, grade, outOf, dueDate, artificial, editing, term, assignmentId, corNumId, section, gbId, meta } = useLocalSearchParams();
  
  // Memoize formatted class name
  const formattedClass = useMemo(() => formatClassName(classParam?.toString() || ''), [classParam]);

  // Memoize parsed meta data
  const parsedMeta = useMemo(() => {
    try {
      const metaData = meta ? JSON.parse(meta.toString()) : [];
      
      // Temporary test: simulate missing assignment metadata
      if (name?.toString() === 'PS 1A 1B' && grade?.toString() === '*') {
        return [{
          type: 'missing',
          note: 'This assignment is marked missing'
        }];
      }
      
      return metaData;
    } catch {
      return [];
    }
  }, [meta, name, grade]);

  // Memoize initial values to prevent unnecessary recalculations
  const initialGradeValue = useMemo(() => 
    grade === '*' ? '*' : !isNaN(Number(grade)) ? Number(grade).toFixed(2) : '', [grade]);
  const initialOutOfValue = useMemo(() => 
    !isNaN(Number(outOf)) ? Number(outOf).toFixed(2) : '', [outOf]);

  const [gradeValue, setGradeValue] = useState(initialGradeValue);
  const [outOfValue, setOutOfValue] = useState(initialOutOfValue);

  const gradeInputRef = useRef<TextInput>(null);
  const outOfInputRef = useRef<TextInput>(null);

  // Memoize initial percentage calculation
  const initialPercentage = useMemo(() => {
    if (!isNaN(Number(grade)) && !isNaN(Number(outOf)) && Number(outOf) !== 0) {
      return ((Number(grade) / Number(outOf)) * 100).toFixed(2);
    }
    if (grade === '*') return '*';
    return '0.00';
  }, [grade, outOf]);

  const [percentage, setPercentage] = useState(initialPercentage);

  // Memoize percentage calculation to prevent unnecessary recalculations
  const calculatedPercentage = useMemo(() => {
    if (gradeValue === '*') {
      return '*';
    } else if (!isNaN(Number(gradeValue)) && !isNaN(Number(outOfValue)) && Number(outOfValue) !== 0) {
      return ((Number(gradeValue) / Number(outOfValue)) * 100).toFixed(2);
    } else {
      return '0.00';
    }
  }, [gradeValue, outOfValue]);

  React.useEffect(() => {
    setPercentage(calculatedPercentage);
  }, [calculatedPercentage]);

  const handleSave = useCallback(async () => {
    const className = classParam?.toString() || '';
    const classIdParam = classId?.toString() || '';
    const corNumIdParam = corNumId?.toString() || '';
    const sectionParam = section?.toString() || '';
    const gbIdParam = gbId?.toString() || '';
    
    // Special handling for final exam grades
    if (category?.toString() === "Final Exam") {
      const examKey = `${className}_${corNumIdParam}_${sectionParam}_${gbIdParam}`;
      const examType = term?.toString() || '';
      const existing = JSON.parse(await AsyncStorage.getItem("finalExamGrades") ?? "{}");
      
      if (!existing[examKey]) {
        existing[examKey] = {};
      }
      
      const formattedGrade = gradeValue === '*' ? '*' : parseFloat(Number(gradeValue).toFixed(2));
      existing[examKey][examType] = formattedGrade.toString();
      await AsyncStorage.setItem("finalExamGrades", JSON.stringify(existing));
      return;
    }
    
    // Regular assignment handling
    const existing = JSON.parse(await AsyncStorage.getItem('artificialAssignments') ?? '{}');
    const formattedGrade = gradeValue === '*' ? '*' : parseFloat(Number(gradeValue).toFixed(2));
    const formattedOutOf = Number(outOfValue);

    if (isNaN(formattedOutOf)) return;
    
    const updatedAssignment = {
      id: assignmentId || generateUniqueId(), // Ensure assignment has an ID
      className,
      name,
      category,
      dueDate,
      grade: formattedGrade,
      outOf: parseFloat(formattedOutOf.toFixed(2)),
      artificial: true,
      term: term,
      meta: parsedMeta // Preserve meta data for artificial assignments
    };

    // Use stable key for artificial assignments (same format as class page)
    const storageKey = `${className}_${corNumIdParam}_${sectionParam}_${gbIdParam}_${term}`;

    // Use ID for identification if available, fallback to name
    const identifier = assignmentId || name;
    const filterFn = assignmentId 
      ? (a: any) => a.id !== assignmentId 
      : (a: any) => a.name !== name;

    const updatedClassList = [
      updatedAssignment,
      ...(existing[storageKey]?.filter(filterFn) ?? [])
    ];

    const updated = { ...existing };
    if (updatedClassList.length === 0) {
      // Remove the key if no assignments left
      delete updated[storageKey];
    } else {
      updated[storageKey] = updatedClassList;
    }
    await AsyncStorage.setItem('artificialAssignments', JSON.stringify(updated));
  }, [gradeValue, outOfValue, assignmentId, name, category, dueDate, parsedMeta, classParam, classId, corNumId, section, gbId, term]);

  const saveAndUpdate = useCallback(async () => {
    await handleSave();
    if (gradeValue === '*') {
      setPercentage('*');
    } else if (!isNaN(Number(gradeValue)) && !isNaN(Number(outOfValue)) && Number(outOfValue) !== 0) {
      setPercentage(((Number(gradeValue) / Number(outOfValue)) * 100).toFixed(2));
    }
  }, [handleSave, gradeValue, outOfValue]);

  return (
    <>
        <Stack.Screen
            options={{
            title: decodeURIComponent(name.toString() || 'Assignment'),
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
                                keyboardType='phone-pad'
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
                {parsedMeta.length > 0 && (
                <View className='mt-4 px-4'>
                    <Text className='text-accent font-bold text-sm mb-4'>Assignment Status</Text>
                    {parsedMeta.map((metaItem: any, index: number) => {
                        const getMetaConfig = (type: string) => {
                            switch (type) {
                                case 'missing':
                                    return {
                                        label: 'Missing',
                                        bgColor: theme === 'dark' ? 'bg-red-500' : 'bg-red-500'
                                    };
                                case 'noCount':
                                    return {
                                        label: 'No Count',
                                        bgColor: theme === 'dark' ? 'bg-gray-500' : 'bg-gray-400'
                                    };
                                case 'absent':
                                    return {
                                        label: 'Absent',
                                        bgColor: theme === 'dark' ? 'bg-yellow-500' : 'bg-yellow-500'
                                    };
                                default:
                                    return {
                                        label: metaItem.type,
                                        bgColor: theme === 'dark' ? 'bg-gray-500' : 'bg-gray-400'
                                    };
                            }
                        };
                        
                        const config = getMetaConfig(metaItem.type);
                        
                        return (
                            <View key={index} className="bg-cardColor px-4 py-3 rounded-2xl mb-2">
                                <View className="flex-row items-center justify-between">
                                    <Text className='text-base text-main font-medium'>{config.label}</Text>
                                    <View className={`w-3 h-3 rounded-full ${config.bgColor.replace('bg-', 'bg-')}`} />
                                </View>
                                {metaItem.note && (
                                    <Text className='text-sm text-secondary mt-2'>{metaItem.note}</Text>
                                )}
                            </View>
                        );
                    })}
                </View>
                )}
                {artificial === "true" && (
                <TouchableOpacity
                    onPress={async () => {
                      const className = classParam?.toString() || '';
                      const classIdParam = classId?.toString() || '';
                      const corNumIdParam = corNumId?.toString() || '';
                      const sectionParam = section?.toString() || '';
                      const gbIdParam = gbId?.toString() || '';
                      
                      // Special handling for final exam grades
                      if (category?.toString() === "Final Exam") {
                        const examKey = `${className}_${corNumIdParam}_${sectionParam}_${gbIdParam}`;
                        const examType = term?.toString() || '';
                        const existing = JSON.parse(await AsyncStorage.getItem("finalExamGrades") ?? "{}");
                        
                        if (existing[examKey] && existing[examKey][examType]) {
                          delete existing[examKey][examType];
                          
                          // Remove the entire class key if no exam grades left
                          if (Object.keys(existing[examKey]).length === 0) {
                            delete existing[examKey];
                          }
                          
                          await AsyncStorage.setItem("finalExamGrades", JSON.stringify(existing));
                        }
                        router.back();
                        return;
                      }
                      
                      // Regular assignment deletion
                      const existing = JSON.parse(await AsyncStorage.getItem('artificialAssignments') ?? '{}');
                      // Check for the assignment in the current term format
                      const currentStorageKey = `${className}_${corNumIdParam}_${sectionParam}_${gbIdParam}_${term}`;
                      
                      // Also check for old format (full term name) for backward compatibility
                      const oldTerm = term === "Q1" ? "Q1 Grades" : 
                                     term === "Q2" ? "Q2 Grades" :
                                     term === "Q3" ? "Q3 Grades" :
                                     term === "Q4" ? "Q4 Grades" :
                                     term === "SM1" ? "SM1 Grade" :
                                     term === "SM2" ? "SM2 Grades" : null;
                      const oldStorageKey = oldTerm ? `${className}_${corNumIdParam}_${sectionParam}_${gbIdParam}_${oldTerm}` : null;
                      
                      const assignmentsToFilter = existing[currentStorageKey] ?? (oldStorageKey && existing[oldStorageKey]) ?? [];
                      const storageKeyToUse = existing[currentStorageKey] ? currentStorageKey : 
                                             (oldStorageKey && existing[oldStorageKey]) ? oldStorageKey : currentStorageKey;
                      // Use ID for identification if available, fallback to name
                      const filterFn = assignmentId 
                        ? (a: any) => a.id !== assignmentId 
                        : (a: any) => a.name !== name;
                      const updatedClassList = assignmentsToFilter.filter(filterFn);
                      
                      const updated = { ...existing };
                      if (updatedClassList.length === 0) {
                        // Remove the key entirely if no assignments left
                        if (storageKeyToUse) {
                          delete updated[storageKeyToUse];
                        }
                      } else {
                        if (storageKeyToUse) {
                          updated[storageKeyToUse] = updatedClassList;
                        }
                      }
                      
                      await AsyncStorage.setItem('artificialAssignments', JSON.stringify(updated));
                      router.back();
                    }}
                    className='mt-4 mx-4 bg-cardColor items-center rounded-lg'
                    >
                    <Text className='text-red-500 font-medium py-3 text-lg'>
                      {category?.toString() === "Final Exam" ? "Reset Exam Grade" : "Delete Assignment"}
                    </Text>
                </TouchableOpacity>
                )}
            </View>
        </View>
        </TouchableWithoutFeedback>
    </>
  )
}

export default React.memo(AssignmentDetails)