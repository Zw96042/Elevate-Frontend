import { View, Text, TouchableOpacity } from 'react-native'
import React from 'react'
import { Link, useLocalSearchParams } from 'expo-router'
import { Ionicons } from '@expo/vector-icons';
import formatClassName from '@/utils/formatClassName';

type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";


// Course Name, Teacher Name, Numerical Grade
const ClassCard = ({ name, teacher, t1, t2, s1, t3, t4, s2, term }: Class & { term: TermLabel }) => {
    const termMap: Record<TermLabel, TermData> = {
        "Q1 Grades": t1,
        "Q2 Grades": t2,
        "SM1 Grade": s1,
        "Q3 Grades": t3,
        "Q4 Grades": t4,
        "SM2 Grades": s2,
    };

    type TermData = {
        categories: {
            names: string[];
            grades: number[];
        };
        total: number;
    };
    const currTerm = termMap[term];

    // const { class: classParam, teacher, t1, t2, s1, t3, t4, s2, term } = useLocalSearchParams();
    
    const percentage = currTerm.total;
    const letter = percentage >= 90 ? "A" : percentage >= 80 ? "B" : percentage >= 70 ? "C" : "D";
    let bgColor = "bg-blue-400";
    if (letter === "B") bgColor = "bg-yellow-400";
    else if (letter === "C" || letter === "D") bgColor = "bg-red-300";
  return (
    
    <Link 
        href={{
            pathname: '/classes/[class]',
            params: {
                class: name,
                t1: JSON.stringify(t1),
                t2: JSON.stringify(t2),
                s1: JSON.stringify(s1),
                t3: JSON.stringify(t3),
                t4: JSON.stringify(t4),
                s2: JSON.stringify(s2),
                term
            }
        }}
        asChild
        // href={`/classes/${name}`} asChild
    >
        {/* <Link
              href={{
                pathname: '/assignments/[assignment]',
                params: {
                  assignment: name,
                  class: className,
                  name,
                  category,
                  grade: grade.toString(),
                  outOf: outOf.toString(),
                  dueDate
                }
              }}
              asChild
            > */}
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
                        <Text className="text-xs text-gray-200 mt-1">{percentage.toFixed(1)}%</Text>
                    </View>

                    <Ionicons name="chevron-forward" size={24} color="#cbd5e1" className='mr-3'/>
                </View>
            </View>
        </TouchableOpacity>
    </Link>
  )
}

export default ClassCard