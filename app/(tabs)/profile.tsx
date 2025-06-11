import React, { useState, useEffect } from 'react';
import { View, TextInput, Button, Text, ScrollView, TouchableOpacity, TouchableWithoutFeedback, Keyboard, KeyboardAvoidingViewComponent, KeyboardAvoidingView, Platform } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { Image } from 'react-native'
import { icons } from "@/constants/icons";
import { authenticate } from '@/lib/authHandler';
import * as Burnt from "burnt";

const STORAGE_KEY = 'person_info';

export default function PersonInfoScreen() {
  const [name, setName] = useState('');
  const [link, setLink] = useState('');

  const [saved, setSaved] = useState(false);

  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

useEffect(() => {
  const loadInfo = async () => {
    const storedName = await AsyncStorage.getItem('person_info_name');
    const storedLink = await AsyncStorage.getItem('skywardLink');
    const storedUser = await AsyncStorage.getItem('skywardUser');
    const storedPass = await AsyncStorage.getItem('skywardPass');

    if (storedName) setName(storedName);
    if (storedLink) setLink(storedLink);
    if (storedUser) setUsername(storedUser);
    if (storedPass) setPassword(storedPass);
  };

  loadInfo();
}, []);

const saveInfo = async () => {
  try {
    await AsyncStorage.setItem('person_info_name', name);
    await AsyncStorage.setItem('skywardUser', username);
    await AsyncStorage.setItem('skywardPass', password);
    await AsyncStorage.setItem('skywardLink', link);

    console.log("Saved credentials:");
    console.log("skywardLink:", link);
    console.log("skywardUser:", username);
    console.log("skywardPass:", password);

    setSaved(true);
    setTimeout(() => setSaved(false), 2000);

    // Now authenticate with saved credentials
    const authResult = await authenticate();

    if (authResult.success) {
      console.log("Authentication succeeded");
      Burnt.toast({
        title: "Information Verified",
        preset: "done"
      });
      // Optionally: store session codes here or show UI feedback
    } else {
      console.error("Authentication failed:", authResult.error);
      Burnt.toast({
        title: "Error",
        preset: "error",
        message: "Couldn't verify details",
      });
      // Optionally: show user error feedback
    }
  } catch (error) {
    console.error("Failed to save credentials", error);
  }
};

  return (
    <KeyboardAvoidingView behavior={Platform.OS === "ios" ? "padding" : "height"} className='flex-1 bg-primary'>
      <TouchableWithoutFeedback onPress={Keyboard.dismiss}>
        <View className='flex-1 bg-primary'>
            <View className="bg-blue-600 pt-14 pb-4 px-5">
                <Text className="text-white text-3xl font-bold">Settings</Text>
            </View>
            <View className='flex-1 p-10'>
                <View className='bg-cardColor w-full h-[21rem] rounded-3xl'>
                    <View className='flex-1 px-4 pb-10'>
                            <View className='bg-highlight self-start rounded-xl mt-3 ml-auto'>
                                <TouchableOpacity onPress={saveInfo} className="w-full">
                                    <Text className='font-bold text-sm text-highlightText p-1 text-center'>Save Info</Text>
                                </TouchableOpacity>
                            </View>
                            <View className="mb-4">
                                <Text className="text-lg font-semibold mb-2 text-main">Skyward Link</Text>
                                <TextInput
                                className="border border-secondary rounded-lg p-3 text-main"
                                value={link}
                                onChangeText={setLink}
                                placeholder="https://example.com"
                                autoCapitalize="none"
                                />
                            </View>

                            <View className="mb-4">
                                <Text className="text-lg font-semibold mb-2 text-main">Username</Text>
                                <TextInput
                                className="border border-secondary rounded-lg p-3 text-main"
                                value={username}
                                onChangeText={setUsername}
                                placeholder="Username"
                                autoCapitalize="none"
                                />
                            </View>

                            <View>
                                <Text className="text-lg font-semibold mb-2 text-main">Password</Text>
                                <TextInput
                                className="border border-secondary rounded-lg p-3 text-main"
                                value={password}
                                onChangeText={setPassword}
                                placeholder="Password"
                                secureTextEntry
                                />
                            </View>
                    </View>
                </View>
            </View>
          </View>
        </TouchableWithoutFeedback>
      </KeyboardAvoidingView>
  );
}

/*
/*
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
      total: 85
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
*/