import AsyncStorage from '@react-native-async-storage/async-storage';

export class SkywardAuth {
  static async get(): Promise<SkywardAuthInfo | null> {
    try {
      const [link, username, password] = await Promise.all([
        AsyncStorage.getItem('skywardLink'),
        AsyncStorage.getItem('skywardUser'),
        AsyncStorage.getItem('skywardPass'),
      ]);

      if (!link || !username || !password) {
        console.warn('[SkywardAuth] Missing credentials');
        return null;
      }

      return { link, username, password };
    } catch (err) {
      console.error('[SkywardAuth] Error retrieving credentials:', err);
      return null;
    }
  }

  static async hasCredentials(): Promise<boolean> {
    try {
      const [link, username, password] = await Promise.all([
        AsyncStorage.getItem('skywardLink'),
        AsyncStorage.getItem('skywardUser'),
        AsyncStorage.getItem('skywardPass'),
      ]);
    //   console.log(link, username, password)
      return !!(link && username && password);
    } catch (err) {
      console.error('[SkywardAuth] Error checking credentials:', err);
      return false;
    }
  }
}