import { FlatList, ScrollView, Text, TouchableOpacity, View } from "react-native";
import { Link } from "expo-router";
import { Image } from 'react-native'
import { icons } from "@/constants/icons";
import ClassCard from "@/components/ClassCard";
import * as SecureStore from 'expo-secure-store';
import React, { useEffect, useState } from 'react';
import { Link as RouterLink } from 'expo-router'; // rename so it doesn't clash
import { Ionicons } from "@expo/vector-icons";

const DATA = [
  {
    name: 'BIOLOGY_1_HONORS',
    teacher: 'MARISA_SPEARS',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [85, 95, 75]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_PRECALCULUS',
    teacher: 'KENZIE_SANCHEZ',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_HUMAN_GEOGRAPHY',
    teacher: 'IAN_FULLMER',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'INVENTION_&_INNOVATION_FF',
    teacher: 'NORMAN_MORGAN',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'WATER_POLO_B_1',
    teacher: 'DARCI_CARRUTHERS',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'ENGLISH_1_HONORS',
    teacher: 'CATHERINE_KELLY',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
  {
    name: 'AP_COMPUTER_SCIENCE_A_Math',
    teacher: 'ISIANA_RENDON',
    t1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    s1: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 100
    },
    t3: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 98
    },
    t4: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 96
    },
    s2: {
      categories: {
        names: ["Daily", "Labs", "Major"],
        grades: [90, 85, 99]
      },
      total: 95
    },
  },
];

export default function Index() {
  const [credentialsSet, setCredentialsSet] = useState<boolean | null>(null);

  useEffect(() => {
    const checkCredentials = async () => {
      try {
        const data = await SecureStore.getItemAsync('person_info');
        if (data) {
          const { link, username, password } = JSON.parse(data);
          const isComplete = !!link && !!username && !!password;
          setCredentialsSet(isComplete);
        } else {
          setCredentialsSet(false);
        }
      } catch (e) {
        console.error("Error loading credentials:", e);
        setCredentialsSet(false);
      }
    };

    checkCredentials();
  }, []);

  const [dropdownOpen, setDropdownOpen] = React.useState(false);
  type TermLabel =
  | "Q1 Grades"
  | "Q2 Grades"
  | "SM1 Grade"
  | "Q3 Grades"
  | "Q4 Grades"
  | "SM2 Grades";
  
  const [selectedCategory, setSelectedCategory] = React.useState<TermLabel>("Q1 Grades");
  
  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Courses</Text>
      </View>
      <ScrollView className="flex-1 px-5" showsVerticalScrollIndicator={false} contentContainerStyle={{minHeight: '100%', paddingBottom: 10}}>
        <Text className='text-slate-400 font-bold ml-4 mt-3 text-sm'>Term</Text>
            <View className="mt-2 px-4">
              <TouchableOpacity
                onPress={() => setDropdownOpen(!dropdownOpen)}
                className="flex-row items-center justify-between bg-slate-800 px-4 py-3 rounded-full"
              >
                <Text className="text-base text-slate-300">{selectedCategory}</Text>
                <Ionicons name={dropdownOpen ? 'chevron-up' : 'chevron-down'} size={20} color="#cbd5e1"/>
              </TouchableOpacity>

              {dropdownOpen && (
                <View className="mt-2 bg-slate-800 rounded-xl">
                  {(["Q1 Grades", "Q2 Grades", "SM1 Grade", "Q3 Grades", "Q4 Grades", "SM2 Grades"] as TermLabel[]).map((label) => (
                  <TouchableOpacity
                    key={label}
                    onPress={() => {
                      setSelectedCategory(label);
                      setDropdownOpen(false);
                    }}
                    className="px-4 py-3"
                  >
                    <Text className="text-slate-300">{label}</Text>
                  </TouchableOpacity>
                ))}
                </View>
              )}
            </View>
        <View className="flex-1 mt-0">
          <>
            
            <FlatList 
              data={DATA}
              renderItem={({ item }) => (
                <ClassCard 
                  name={item.name}
                  teacher={item.teacher}
                  t1={item.t1}
                  t2={item.t2}
                  s1={item.s1}
                  t3={item.t3}
                  t4={item.t4}
                  s2={item.s2}
                  term={selectedCategory}
                />
              )}
              keyExtractor={(item) => item.name.toString()}
              className="mt-2 pb-32"
              scrollEnabled={false}
              ItemSeparatorComponent={() => <View className="h-4" />}
              ListEmptyComponent={
                <View className="mt-10 px-5">
                  {credentialsSet === null ? (
                    <Text className="text-center text-gray-500">Checking credentials...</Text>
                  ) : credentialsSet ? (
                    <Text className="text-center text-gray-500">Server error. Try again later.</Text>
                  ) : (
                    <Text className="text-center text-gray-500">
                      No credentials found.{" "}
                      <RouterLink href="/profile" className="text-blue-400 underline">
                        Go to Settings
                      </RouterLink>{" "}
                      to configure your account.
                    </Text>
                  )}
                </View>
              }
            />
          </>
        </View>
      </ScrollView>
    </View>
  );
}