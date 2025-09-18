import { View, Text, useColorScheme, TextInput, TouchableWithoutFeedback, Platform, Keyboard, TouchableOpacity, Linking, DeviceEventEmitter } from 'react-native'
import React, { useEffect, useState, useRef, useMemo } from 'react'
import { Tabs } from 'expo-router'
import { Ionicons } from '@expo/vector-icons'
import BottomSheet, { BottomSheetBackdrop, BottomSheetModalProvider, BottomSheetView } from '@gorhom/bottom-sheet'
import { colors } from '@/utils/colorTheme'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { authenticate } from '@/lib/authHandler'
import { CredentialManager } from '@/lib/core/CredentialManager';
import * as Burnt from "burnt";

const InnerLayout = () => {
  const [gradeLevel, setGradeLevel] = useState('');
  const [currentSnapPosition, setCurrentSnapPosition] = useState<'hidden' | '35%' | '75%'>('hidden');
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);
  const [link, setLink] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const settingSheetRef = useRef<BottomSheet>(null);
  const colorScheme = useColorScheme()
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  // Ref to store the last saved values for auto-save detection
  const lastSaved = useRef({ link: '', username: '', password: '', gradeLevel: '' });
  const autoSaveTimeout = useRef<NodeJS.Timeout | null>(null);

  // Keyboard show/hide snap logic
  useEffect(() => {
    const showSub = Keyboard.addListener('keyboardDidShow', () => {
      if (
        !modalClosedByOutsideTap &&
        currentSnapPosition !== '75%' &&
        currentSnapPosition !== 'hidden'
      ) {
        settingSheetRef.current?.snapToPosition('75%', { duration: 150 });
        setCurrentSnapPosition('75%');
      }
    });

    const hideSub = Keyboard.addListener('keyboardDidHide', () => {
      setModalClosedByOutsideTap(false);
      if (currentSnapPosition === '75%') {
        settingSheetRef.current?.snapToIndex(0, { duration: 150 });
        setCurrentSnapPosition('35%');
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
      DeviceEventEmitter.emit('settingsSheetClosed');
    } else {
      setCurrentSnapPosition('35%');
    }
  };

  // Load credentials on mount
  useEffect(() => {
    const loadInfo = async () => {
      // First try to load from CredentialManager
      const authInfo = await CredentialManager.getAuthInfo();
      
      if (authInfo && CredentialManager.validateAuthInfo(authInfo)) {
        // Use credentials from CredentialManager
        setLink(authInfo.link);
        setUsername(authInfo.username);
        setPassword(authInfo.password);
        
        // Still load grade level from old storage
        const storedGrade = await AsyncStorage.getItem('gradeLevel');
        if (storedGrade) setGradeLevel(storedGrade);
        
        lastSaved.current = {
          link: authInfo.link,
          username: authInfo.username,
          password: authInfo.password,
          gradeLevel: storedGrade || '',
        };
      } else {
        // Fall back to old storage format
        const storedLink = await AsyncStorage.getItem('skywardLink');
        const storedUser = await AsyncStorage.getItem('skywardUser');
        const storedPass = await AsyncStorage.getItem('skywardPass');
        const storedGrade = await AsyncStorage.getItem('gradeLevel');

        if (storedLink) setLink(storedLink);
        if (storedUser) setUsername(storedUser);
        if (storedPass) setPassword(storedPass);
        if (storedGrade) setGradeLevel(storedGrade);

        // Store loaded credentials in lastSaved
        lastSaved.current = {
          link: storedLink || '',
          username: storedUser || '',
          password: storedPass || '',
          gradeLevel: storedGrade || '',
        };
        
        // If we found old credentials, migrate them to new format
        if (storedUser && storedPass && storedLink) {
          await CredentialManager.storeAuthInfo({
            username: storedUser,
            password: storedPass,
            link: storedLink
          });
        }
      }
    };

    loadInfo();
  }, []);

  // Listen for settings modal open events
  useEffect(() => {
    const subscription = DeviceEventEmitter.addListener('openSettingsModal', () => {
      settingSheetRef.current?.snapToIndex(0);
      setCurrentSnapPosition('35%');
    });

    return () => subscription.remove();
  }, []);

  // Auto-save function
  const autoSave = async () => {
    const changed =
      username !== lastSaved.current.username ||
      password !== lastSaved.current.password ||
      link !== lastSaved.current.link ||
      gradeLevel !== lastSaved.current.gradeLevel;

    if (!changed) return;

    try {
      // Store in old format for backward compatibility
      await AsyncStorage.setItem('skywardUser', username);
      await AsyncStorage.setItem('skywardPass', password);
      await AsyncStorage.setItem('skywardLink', link || "https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/");
      await AsyncStorage.setItem('gradeLevel', gradeLevel);

      // Store in new CredentialManager format
      await CredentialManager.storeAuthInfo({
        username: username,
        password: password,
        link: link || "https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/"
      });

      lastSaved.current = { link, username, password, gradeLevel };

      // Only authenticate and show toast if we have both username and password
      // Skip authentication during auto-save to reduce error noise
      if (username && password && username.length > 2 && password.length > 2) {
        // Only auto-authenticate if credentials look complete
        console.log('Auto-save: Credentials stored, skipping authentication test to reduce errors');
      }
    } catch (error) {
      console.error('Auto-save error:', error);
    }
  };

  // Manual test connection function
  const testConnection = async () => {
    if (!username || !password) {
      Burnt.toast({
        title: 'Missing Information',
        preset: 'error',
        duration: 1
      });
      return;
    }

    try {
      Burnt.toast({
        title: 'Testing Connection...',
        preset: 'none',
        duration: 1
      });

      const authResult = await authenticate();

      if (authResult.success) {
        Burnt.toast({
          title: 'Connection Successful!',
          preset: 'done',
          duration: 1
        });
        DeviceEventEmitter.emit('credentialsAdded');
      } else {
        Burnt.toast({
          title: 'Connection Failed',
          preset: 'error',
          duration: 2
        });
      }
    } catch (error: any) {
      if (error.message?.includes('Invalid user or pass')) {
        Burnt.toast({
          title: 'Invalid Credentials',
          preset: 'error',
          duration: 2
        });
      } else {
        Burnt.toast({
          title: 'Connection Error',
          preset: 'error',
          duration: 2
        });
      }
    }
  };
  useEffect(() => {
    if (autoSaveTimeout.current) {
      clearTimeout(autoSaveTimeout.current);
    }
    
    // Only auto-save if we have some content
    if (username || password || gradeLevel) {
      autoSaveTimeout.current = setTimeout(() => {
        autoSave();
      }, 1500) as any; // Save 1.5 seconds after user stops typing
    }

    return () => {
      if (autoSaveTimeout.current) {
        clearTimeout(autoSaveTimeout.current);
      }
    };
  }, [username, password, link, gradeLevel]);

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
              name="gpa"
              options={{
                title: "GPA",
                headerShown: false,
                tabBarIcon: ({ focused }) => (
                  <View className="items-center justify-center w-[240%] mt-5 h-[80%]">
                    <Ionicons name="document-text-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                    <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>GPA</Text>
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
                    <Ionicons name="mail-outline" size={22} color={focused ? '#2A52BE' : '#A8B5DB'} />
                    <Text style={{ color: focused ? '#2A52BE' : '#A8B5DB', fontSize: 12, marginTop: 5 }}>Inbox</Text>
                  </View>
                )
              }}
            />
          </Tabs>

          <BottomSheet
            ref={settingSheetRef}
            index={-1}
            snapPoints={["35%"]}
            backgroundStyle={{ backgroundColor: cardColor }}
            overDragResistanceFactor={1}
            enableDynamicSizing={false}
            enablePanDownToClose={true}
            keyboardBehavior={'extend'}
            onChange={handleSheetChanges}
            detached={true}
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
              settingSheetRef.current?.snapToIndex(0, { duration: 350 });
            }}>
              <BottomSheetView className="bg-cardColor px-8 rounded-2xl">
                <Text className="text-2xl text-main">Settings</Text>
                <View className='my-4 border-slate-600 border-[0.5px]'></View>
                
                <View className="pb-3">
                  <Text className="text-base font-medium text-main">School District</Text>
                  <View className="flex-row items-center rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="school-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-gray-400"
                      value="Eanes ISD"
                      editable={false}
                      placeholderTextColor="#888"
                      selectTextOnFocus={false}
                    />
                  </View>
                  <TouchableOpacity onPress={() => Linking.openURL("https://docs.google.com/forms/d/e/1FAIpQLSdqtqDEwLQY03KHS_LZDpjOjTcP_j8MCIizaMRMHTS6T5tOzQ/viewform?usp=dialog")} className='self-start'>
                    <Text className='text-blue-400 decoration-solid text-sm font-semibold mt-1'>Don't see your district?</Text>
                  </TouchableOpacity>
                </View>

                <View className="pb-3">
                  <Text className="font-medium text-main">Username</Text>
                  <View className="flex-row items-center rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="person-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-main"
                      value={username}
                      onChangeText={setUsername}
                      placeholder="Username"
                      placeholderTextColor="#888"
                      autoCapitalize="none"
                      autoComplete='off'
                      autoCorrect={false}
                      spellCheck={false}
                      textContentType="none"
                    />
                  </View>
                </View>

                <View className="pb-3">
                  <Text className="font-medium text-main">Password</Text>
                  <View className="flex-row items-center rounded-md px-3 py-2 bg-primary">
                    <Ionicons name="lock-closed-outline" size={18} color="#888" style={{ marginRight: 8 }} />
                    <TextInput
                      className="flex-1 text-main"
                      value={password}
                      onChangeText={setPassword}
                      placeholder="Password"
                      placeholderTextColor="#888"
                      secureTextEntry={!showPassword}
                      autoCapitalize="none"
                      autoCorrect={false}
                      spellCheck={false}
                      textContentType="none"
                      autoComplete="off"
                    />
                    <TouchableOpacity onPress={() => setShowPassword(prev => !prev)}>
                      <Ionicons
                        name={showPassword ? 'eye-off-outline' : 'eye-outline'}
                        size={18}
                        color="#888"
                        style={{ marginLeft: 8 }}
                      />
                    </TouchableOpacity>
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
    <BottomSheetModalProvider>
      <GestureHandlerRootView style={{ flex: 1 }}>
        <InnerLayout />
      </GestureHandlerRootView>
    </BottomSheetModalProvider>
  )
}

export default _layout
