import AsyncStorage from '@react-native-async-storage/async-storage';

export const getSkywardCredentials = async () => {
  const user = await AsyncStorage.getItem('skywardUser');
  const pass = await AsyncStorage.getItem('skywardPass');
  const link = await AsyncStorage.getItem('skywardLink');

  return { user, pass, link };
};

export const credentialsAreSet = async () => {
  const { user, pass, link } = await getSkywardCredentials();
  return !!(user && pass && link);
};