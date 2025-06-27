import { View, Text, useColorScheme, TextInput, TouchableWithoutFeedback, Platform, Keyboard } from 'react-native'
import React, { useEffect, useState, useRef, useMemo } from 'react'
import { Tabs } from 'expo-router'
import { Ionicons } from '@expo/vector-icons'
import { SettingSheetProvider, useSettingSheet } from '@/context/SettingSheetContext'
import BottomSheet, { BottomSheetBackdrop, BottomSheetModalProvider, BottomSheetView } from '@gorhom/bottom-sheet'
import { colors } from '@/utils/colorTheme'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { authenticate } from '@/lib/authHandler'
import * as Burnt from "burnt";
import Animated from 'react-native-reanimated'

const InnerLayout = () => {
  const [currentSnapPosition, setCurrentSnapPosition] = useState<'hidden' | '33%' | '80%'>('hidden');
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);
  const {
    settingSheetRef,
    link,
    setLink,
    username,
    setUsername,
    password,
    setPassword,
  } = useSettingSheet()
  const colorScheme = useColorScheme()
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  // Ref to store the last saved values
  const lastSaved = useRef({ link: '', username: '', password: '' });

  // Keyboard show/hide snap logic
  useEffect(() => {
    const showSub = Keyboard.addListener('keyboardDidShow', () => {
      if (
        !modalClosedByOutsideTap &&
        currentSnapPosition !== '80%' &&
        currentSnapPosition !== 'hidden'
      ) {
        settingSheetRef.current?.snapToPosition('80%', { duration: 150 });
        setCurrentSnapPosition('80%');
      }
    });

    const hideSub = Keyboard.addListener('keyboardDidHide', () => {
      setModalClosedByOutsideTap(false);
      if (currentSnapPosition === '80%') {
        settingSheetRef.current?.snapToPosition('33%', { duration: 150 });
        setCurrentSnapPosition('33%');
      }
    });

    return () => {
      showSub.remove();
      hideSub.remove();
    };
  }, [currentSnapPosition, modalClosedByOutsideTap]);

  const handleSheetChanges = (index: number) => {
    if (index === -1) {
      setCurrentSnapPosition('hidden');
    } else {
      setCurrentSnapPosition('33%');
    }
  };
  useEffect(() => {
    const loadInfo = async () => {
      const storedLink = await AsyncStorage.getItem('skywardLink');
      const storedUser = await AsyncStorage.getItem('skywardUser');
      const storedPass = await AsyncStorage.getItem('skywardPass');

      if (storedLink) setLink(storedLink);
      if (storedUser) setUsername(storedUser);
      if (storedPass) setPassword(storedPass);

      // Store loaded credentials in lastSaved
      lastSaved.current = {
        link: storedLink || '',
        username: storedUser || '',
        password: storedPass || '',
      };
    };

    loadInfo();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);



  const saveInfo = async () => {
    const changed =
      link !== lastSaved.current.link ||
      username !== lastSaved.current.username ||
      password !== lastSaved.current.password;

    if (!changed) return;

    try {
      await AsyncStorage.setItem('skywardUser', username);
      await AsyncStorage.setItem('skywardPass', password);
      await AsyncStorage.setItem('skywardLink', link);

      const authResult = await authenticate();

      lastSaved.current = { link, username, password };
      if (authResult.success) {
        Burnt.toast({
          title: 'Information Verified',
          preset: 'done'
        });
      } else {
        Burnt.toast({
          title: 'Error',
          preset: 'error',
          message: "Couldn't verify details",
        });
      }
    } catch (error) {
      console.error('Failed to save credentials', error);
    }
  }

  return (
      <TouchableWithoutFeedback onPress={() => {
        Keyboard.dismiss();
        settingSheetRef.current?.close();
        setCurrentSnapPosition('hidden');
      }} accessible={false}>
        <View className='flex-1'>
          <Tabs
            screenOptions={{
              tabBarShowLabel: false,
              tabBarItemStyle: {
                flex: 1,
              },
              tabBarStyle: {
                borderTopWidth: 0,
                height: 70,
                paddingBottom: 8,
                position: 'absolute',
              },
              tabBarBackground: () => (
                <View className="flex-1 bg-nav border-t border-gray-200 dark:border-transparent" />
              ),
            }}
          >
            <Tabs.Screen 
              name="index"
              options={{
                title: "Courses",
                headerShown: false,
                tabBarIcon: ({ focused }) => (
                  <View className="items-center justify-center w-[180%] mt-5 h-[80%]">
                    <Ionicons name="school-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                    <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Courses</Text>
                  </View>
                )
              }}
            />
            <Tabs.Screen 
              name="assignments"
              options={{
                title: "Assignments",
                headerShown: false,
                tabBarIcon: ({ focused }) => (
                  <View className="items-center justify-center w-[240%] mt-5 h-[80%]">
                    <Ionicons name="document-text-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                    <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Assignments</Text>
                  </View>
                )
              }}
            />
            <Tabs.Screen 
              name="inbox"
              options={{
                title: "Inbox",
                headerShown: false,
                tabBarIcon: ({ focused }) => (
                  <View className="items-center justify-center w-[180%] mt-5 h-[80%]">
                    <Ionicons name="file-tray-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                    <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Inbox</Text>
                  </View>
                )
              }}
            />
          </Tabs>

          <BottomSheet
            ref={settingSheetRef}
            index={-1}
            snapPoints={["33%"]}
            backgroundStyle={{ backgroundColor: cardColor }}
            overDragResistanceFactor={1}
            onClose={saveInfo}
            enablePanDownToClose={true}
            keyboardBehavior={'extend'}
            onChange={handleSheetChanges}
            backdropComponent={(props) => (
              <TouchableWithoutFeedback onPress={() => {
                Keyboard.dismiss();
                settingSheetRef.current?.close();
                setCurrentSnapPosition('hidden');
                setModalClosedByOutsideTap(true);
              }}>
                <BottomSheetBackdrop
                  {...props}
                  disappearsOnIndex={-1}
                  appearsOnIndex={0}
                />
              </TouchableWithoutFeedback>
            )}
          >
            <TouchableWithoutFeedback onPress={() => {
              Keyboard.dismiss();
              settingSheetRef.current?.snapToPosition('33%', { duration: 150 });
            }}>
              <BottomSheetView className="bg-cardColor p-4 space-y-4">
                <Text className="text-3xl font-bold text-main mb-2">Credentials</Text>

                <View className="space-y-1">
                  <Text className="text-sm font-medium text-main">Skyward Link</Text>
                  <View className="flex-row items-center border border-secondary rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="link-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-main"
                      value={link}
                      onChangeText={setLink}
                      placeholder="https://example.com"
                      placeholderTextColor="#888"
                      autoCapitalize="none"
                    />
                  </View>
                </View>

                <View className="space-y-1">
                  <Text className="text-sm font-medium text-main">Username</Text>
                  <View className="flex-row items-center border border-secondary rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="person-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-main"
                      value={username}
                      onChangeText={setUsername}
                      placeholder="Username"
                      placeholderTextColor="#888"
                      autoCapitalize="none"
                    />
                  </View>
                </View>

                <View className="space-y-1">
                  <Text className="text-sm font-medium text-main">Password</Text>
                  <View className="flex-row items-center border border-secondary rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="lock-closed-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-main"
                      value={password}
                      onChangeText={setPassword}
                      placeholder="Password"
                      placeholderTextColor="#888"
                      secureTextEntry
                    />
                  </View>
                </View>
              </BottomSheetView>
            </TouchableWithoutFeedback>
          </BottomSheet>
        </View>
      </TouchableWithoutFeedback>
  )
}

const _layout = () => {
  return (
    <SettingSheetProvider>
      <BottomSheetModalProvider>
        <GestureHandlerRootView style={{ flex: 1 }}>
          <InnerLayout />
        </GestureHandlerRootView>
      </BottomSheetModalProvider>
    </SettingSheetProvider>
  )
}

export default _layout

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