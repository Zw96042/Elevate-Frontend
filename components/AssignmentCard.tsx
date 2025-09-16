import { View, Text, TouchableOpacity, useColorScheme } from 'react-native'
import React, { useState } from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import CircularProgress from 'react-native-circular-progress-indicator';

type AssignmentCardProps = Assignment & {
  editing: boolean;
  classId?: string;
  corNumId?: string;
  section?: string;
  gbId?: string;
};

// Course Name, Teacher Name, Numerical Grade
const AssignmentCard = ({ id, className, name, term, category, grade, outOf, dueDate, artificial, editing, classId, corNumId, section, gbId, meta }: AssignmentCardProps) => {
   const theme = useColorScheme();
   const highlight = theme === 'dark' ? "#3b5795" : "#a4bfed";
   const highlightText = theme === 'dark' ? "#7398e6" : "#587bc5";
  
  // Check for metadata types
  const isMissing = meta?.some(m => m.type === 'missing');
  const isNoCount = meta?.some(m => m.type === 'noCount');
  const isAbsent = meta?.some(m => m.type === 'absent');
  
  // Temporary test: simulate the missing assignment from API example
  const testIsMissing = name === 'PS 1A 1B' && grade === '*';
  
  // Get metadata configuration for display
  const getMetaDisplay = () => {
    if (isMissing || testIsMissing) {
      return {
        label: 'Missing',
        bgColor: theme === 'dark' ? 'bg-red-900' : 'bg-red-500',
        textColor: theme === 'dark' ? 'text-red-300' : 'text-red-800'
      };
    }
    if (isNoCount) {
      return {
        label: 'No Count',
        bgColor: theme === 'dark' ? 'bg-gray-700' : 'bg-gray-100',
        textColor: theme === 'dark' ? 'text-gray-300' : 'text-gray-700'
      };
    }
    if (isAbsent) {
      return {
        label: 'Absent',
        bgColor: theme === 'dark' ? 'bg-yellow-900' : 'bg-yellow-100',
        textColor: theme === 'dark' ? 'text-yellow-300' : 'text-yellow-800'
      };
    }
    return null;
  };
  
  const metaDisplay = getMetaDisplay();
  
  // Determine card styling based on metadata
  const getCardStyle = () => {
    if (isMissing || testIsMissing) {
      return 'w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between border-[0.5px] border-red-500';
    }
    return 'w-full h-20 rounded-2xl bg-cardColor flex-row items-center justify-between';
  };
  
  // Determine text styling for no count
  const getTextStyle = () => {
    if (isNoCount) {
      return 'text-lg text-main font-medium ml-5 line-through opacity-60';
    }
    return 'text-lg text-main font-medium ml-5';
  };
  
  // console.log(grade);
  return (
    <Link
      href={{
        pathname: '/assignments/[assignment]',
        params: {
          assignment: id || name, // Use ID if available, fallback to name
          assignmentId: id, // Always pass the ID separately
          class: className,
          classId: classId, // Pass classId to assignment detail page
          corNumId,
          section,
          gbId,
          name,
          term,
          category,
          grade: grade.toString(),
          outOf: outOf.toString(),
          dueDate,
          artificial: artificial.toString(),
          editing: editing.toString(),
          meta: JSON.stringify(meta || [])
        }
      }}
      asChild
    >
        <TouchableOpacity  className='w-[100%]'>
            <View className={getCardStyle()}>
                <View className="flex-1">
                    <View className="self-start rounded-md bg-highlight px-2 ml-5 mt-2">
                        <Text className="text-sm text-highlightText font-bold">{category}</Text>
                    </View>
                    <View className="flex-row items-center ml-5 mr-4 flex-1">
                        <View className="flex-row items-center flex-1">
                            <Text 
                                className={`text-lg text-main font-medium flex-shrink ${isNoCount ? 'line-through opacity-60' : ''}`}
                                numberOfLines={1} 
                                ellipsizeMode="tail"
                            >
                                {name}
                            </Text>
                            {metaDisplay && (
                                <View className={`px-2 py-1 rounded-md ${metaDisplay.bgColor} flex-shrink-0 ml-1`}>
                                    <Text className={`text-xs font-bold ${metaDisplay.textColor}`}>
                                        {metaDisplay.label.toUpperCase()}
                                    </Text>
                                </View>
                            )}
                        </View>
                    </View>
                    <Text className='text-xs text-secondary ml-5 mb-2'>Due {dueDate}</Text>
                </View>
                <View className='flex-row items-center'>
                    <View className="flex-row items-center gap-2 mr-1">
                        <View style={{ width: 40, height: 40, justifyContent: 'center', alignItems: 'center' }}>
                          <CircularProgress
                            value={Number(grade === '*' ? 0 : (Math.min(Number(grade) / Number(outOf), 1)) * 100)}
                            radius={20}
                            activeStrokeWidth={3}
                            activeStrokeColor={highlight}
                            inActiveStrokeOpacity={0}
                            duration={200}
                            showProgressValue={false}
                          />
                          <Text
                            style={{
                              position: 'absolute',
                              color: highlightText,
                              fontWeight: 'bold',
                              fontSize: 12,
                              textAlign: 'center',
                              width: 34,
                            }}
                          >
                            {grade === '*' ? '--' : (isNaN(Number(grade)) ? '--' : (() => {
                              const numGrade = Number(grade);
                              return numGrade >= 100 ? numGrade.toFixed(0) : numGrade.toFixed(1);
                            })())}
                          </Text>
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