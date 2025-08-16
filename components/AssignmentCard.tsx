import { View, Text, TouchableOpacity, useColorScheme } from 'react-native'
import React, { useState } from 'react'
import { Link } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import CircularProgress from 'react-native-circular-progress-indicator';

type AssignmentCardProps = Assignment & {
  editing: boolean;
};

// Course Name, Teacher Name, Numerical Grade
const AssignmentCard = ({ id, className, name, term, category, grade, outOf, dueDate, artificial, editing }: AssignmentCardProps) => {
   const [value, setValue] = useState(0);
   const theme = useColorScheme();
   const highlight = theme === 'dark' ? "#3b5795" : "#a4bfed";
   const highlightText = theme === 'dark' ? "#7398e6" : "#587bc5";
  // console.log(grade);
  return (
    <Link
      href={{
        pathname: '/assignments/[assignment]',
        params: {
          assignment: id || name, // Use ID if available, fallback to name
          assignmentId: id, // Always pass the ID separately
          class: className,
          name,
          term,
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
                        <View style={{ width: 40, height: 40, justifyContent: 'center', alignItems: 'center' }}>
                          <CircularProgress
                            value={Number(grade === '*' ? 0 : (Number(grade) / Number(outOf)) * 100)}
                            radius={20}
                            activeStrokeWidth={3}
                            activeStrokeColor={highlight}
                            inActiveStrokeOpacity={0}
                            duration={700}
                            showProgressValue={false}
                          />
                          <Text
                            style={{
                              position: 'absolute',
                              color: highlightText,
                              fontWeight: 'bold',
                              fontSize: 12,
                              textAlign: 'center',
                              width: 30,
                            }}
                          >
                            {grade === '*' ? '--' : ((Number(grade) / Number(outOf)) * 100).toFixed(0)}
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