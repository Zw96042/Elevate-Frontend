import { View, Text, useColorScheme, TextInput, TouchableWithoutFeedback, Platform, Keyboard, TouchableOpacity, Linking, DeviceEventEmitter, Switch, Pressable } from 'react-native'
import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react'
import { NativeTabs, Icon, Label } from 'expo-router/unstable-native-tabs'
import { Ionicons } from '@expo/vector-icons'
import { SettingSheetProvider, useSettingSheet } from '@/context/SettingSheetContext'
import BottomSheet, { BottomSheetBackdrop, BottomSheetModalProvider, BottomSheetView } from '@gorhom/bottom-sheet'
import { colors } from '@/utils/colorTheme'
import { GestureHandlerRootView } from 'react-native-gesture-handler'
import AsyncStorage from '@react-native-async-storage/async-storage'
import { AuthService, DataService } from '@/lib/services'
import { getStoredSkywardCredentials, saveStoredSkywardCredentials } from '@/lib/utils/secure-skyward-storage'
import * as Burnt from "burnt";
import { shouldEnableShowoffMode } from '@/utils/showoffMode';
import { useUnifiedData } from '@/context/UnifiedDataContext';

const InnerLayout = () => {
  const { clearCache: clearAcademicCache } = useUnifiedData();
  const [gradeLevel, setGradeLevel] = useState('');
  const [currentSnapPosition, setCurrentSnapPosition] = useState<'hidden' | '35%' | '75%'>('hidden');
  const [modalClosedByOutsideTap, setModalClosedByOutsideTap] = useState(false);
  const {
    settingSheetRef,
    link,
    setLink,
    username,
    setUsername,
    password,
    setPassword,
    showoffMode,
    setShowoffMode,
  } = useSettingSheet()
  const colorScheme = useColorScheme()
  const [showPassword, setShowPassword] = useState(false);
  const cardColor = colorScheme === 'dark' ? colors.cardColor.dark : colors.cardColor.light;

  // Ref to store the last saved values
  const lastSaved = useRef({ link: '', username: '', password: '', gradeLevel: '', showoffMode: false });

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
  useEffect(() => {
    const loadInfo = async () => {
      try {
        const [storedLink, storedCredentials, storedGrade, storedShowoffMode] = await Promise.all([
          AsyncStorage.getItem('skywardLink'),
          getStoredSkywardCredentials(),
          AsyncStorage.getItem('gradeLevel'),
          AsyncStorage.getItem('showoffMode'),
        ]);

        if (storedLink) setLink(storedLink);
        if (storedCredentials?.username) setUsername(storedCredentials.username);
        if (storedCredentials?.password) setPassword(storedCredentials.password);
        if (storedGrade) setGradeLevel(storedGrade);
        if (storedShowoffMode) setShowoffMode(storedShowoffMode === 'true');

        // Store loaded credentials in lastSaved
        lastSaved.current = {
          link: storedLink || '',
          username: storedCredentials?.username || '',
          password: storedCredentials?.password || '',
          gradeLevel: storedGrade || '',
          showoffMode: storedShowoffMode === 'true',
        };
      } catch (error) {
        console.error('Failed to load credentials', error);
      }
    };

    loadInfo();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);



  const saveInfo = async () => {
    const credentialsChanged =
      username !== lastSaved.current.username ||
      password !== lastSaved.current.password;
    const preferencesChanged =
      gradeLevel !== lastSaved.current.gradeLevel ||
      showoffMode !== lastSaved.current.showoffMode;

    if (!credentialsChanged && !preferencesChanged) return;

    try {
      if (credentialsChanged) {
        await Promise.all([
          AuthService.clearSession(),
          DataService.clearCache(),
        ]);
        DeviceEventEmitter.emit('credentialsInvalid');
        await saveStoredSkywardCredentials({ username, password });
        // Publishing the new Keychain identity is the account boundary. Advance
        // both generations again immediately so work that began during the
        // secure write cannot commit old-account sessions or academic data.
        await Promise.all([
          AuthService.clearSession(),
          DataService.clearCache(),
        ]);
      }
      await AsyncStorage.multiSet([
        ['skywardLink', "https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/"], // TODO: Change back to add more districts
        ['gradeLevel', gradeLevel],
        ['showoffMode', showoffMode.toString()],
      ]);

      lastSaved.current = { link, username, password, gradeLevel, showoffMode };

      if (!credentialsChanged) return;

      const authResult = await AuthService.authenticate();

      if (authResult.success) {
        Burnt.toast({
          title: 'Information Verified',
          preset: 'done',
          duration: 0.75
        });
        DeviceEventEmitter.emit('credentialsAdded');
      } else {
        Burnt.toast({
          title: 'Error',
          preset: 'error',
          message: "Couldn't verify details",
          duration: 1
        });
        DeviceEventEmitter.emit('credentialsInvalid');
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
          <NativeTabs>
            <NativeTabs.Trigger name="index">
              <Label>Courses</Label>
              <Icon sf={"graduationcap"} />
            </NativeTabs.Trigger>
            <NativeTabs.Trigger name="gpa">
              <Label>GPA</Label>
              <Icon sf={"text.document"} />
            </NativeTabs.Trigger>
            <NativeTabs.Trigger name="inbox">
              <Label>Inbox</Label>
              <Icon sf={"envelope"} />
            </NativeTabs.Trigger>
          </NativeTabs>

          <BottomSheet
            ref={settingSheetRef}
            index={-1}
            snapPoints={["35%"]}
            backgroundStyle={{ backgroundColor: cardColor }}
            overDragResistanceFactor={1}
            enableDynamicSizing={false}
            onClose={saveInfo}
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
                <Pressable
                  onLongPress={async () => {
                    await clearAcademicCache();

                    Burnt.toast({
                      title: 'Cache Cleared',
                      preset: 'done',
                      haptic: 'success',
                      duration: 1
                    });
                  }}
                >
                  <Text className="text-2xl text-main">Settings</Text>
                </Pressable>
                <View className='my-4 border-slate-600 border-[0.5px]'></View>
                <View className="pb-3 ">
                  <Text className="text-base font-medium text-main">School District</Text>
                  <View className="flex-row items-center rounded-md px-3 py-2 bg-primary ">
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
                    <Text className='text-blue-400 decoration-solid text-sm font-semibold mt-1'>Don&apos;t see your district?</Text>
                  </TouchableOpacity>
                </View>
                {/* Grade Level block */}
                {/* <View className="h-[1px] bg-accent opacity-20 mb-5" /> */}

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
                      autoComplete="username"
                      autoCorrect={false}
                      spellCheck={false}
                      textContentType="username"
                    />
                  </View>
                </View>

                <View className="pb-[62px]">
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
                      textContentType="password"
                      autoComplete="password"
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

                {/* Showoff Mode Toggle - only show for username 96042 */}
                {shouldEnableShowoffMode(username) && (
                  <View className="pb-[62px] mt-[-40px]">
                    <View className="flex-row items-center justify-between">
                      <View className="flex-1">
                        <Text className="font-medium text-main">Display Mode</Text>
                      </View>
                      <Switch
                        value={showoffMode}
                        onValueChange={setShowoffMode}
                        trackColor={{ false: '#767577', true: '#81b0ff' }}
                        thumbColor={showoffMode ? '#f5dd4b' : '#f4f3f4'}
                      />
                    </View>
                  </View>
                )}
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
