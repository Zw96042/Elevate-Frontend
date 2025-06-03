import { FlatList, ScrollView, Text, View } from "react-native";
import { Link } from "expo-router";
import { Image } from 'react-native'
import { icons } from "@/constants/icons";
import ClassCard from "@/components/ClassCard";
import * as SecureStore from 'expo-secure-store';
import { useEffect, useState } from 'react';
import { Link as RouterLink } from 'expo-router'; // rename so it doesn't clash

const DATA = [
  {
    name: 'BIOLOGY_1_HONORS',
    teacher: 'MARISA_SPEARS',
    s1: 100,
    s2: 95
  },
  {
    name: 'AP_PRECALCULUS',
    teacher: 'MARISA_SPEARS',
    s1: 100,
    s2: 95
  },
  {
    name: 'AP_HUMAN_GEOGRAPHY',
    teacher: 'MARISA_SPEARS',
    s1: 88,
    s2: 95
  },
  {
    name: 'INVENTION_&_INNOVATION_FF',
    teacher: 'MARISA_SPEARS',
    s1: 75,
    s2: 95
  },
  {
    name: 'WATER_POLO_B_1',
    teacher: 'MARISA_SPEARS',
    s1: 100,
    s2: 95
  },
  {
    name: 'ENGLISH_1_HONORS',
    teacher: 'MARISA_SPEARS',
    s1: 100,
    s2: 95
  },
  {
    name: 'AP_COMPUTER_SCIENCE_A_Math',
    teacher: 'MARISA_SPEARS',
    s1: 100,
    s2: 95
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
  
  return (
    <View className="flex-1 bg-primary">
      <View className="bg-blue-600 pt-14 pb-4 px-5">
        <Text className="text-white text-3xl font-bold">Courses</Text>
      </View>
      <ScrollView className="flex-1 px-5" showsVerticalScrollIndicator={false} contentContainerStyle={{minHeight: '100%', paddingBottom: 10}}>
        <View className="flex-1 mt-0">
          <>
            
            <FlatList 
              data={DATA}
              renderItem={({ item }) => (
                <ClassCard 
                  {... item}
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