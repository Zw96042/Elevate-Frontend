import AsyncStorage from '@react-native-async-storage/async-storage';

export class SkywardAuth {
  static async get(): Promise<SkywardAuthInfo | null> {
    try {
      const [link, username, password] = await Promise.all([
        // AsyncStorage.getItem('skywardLink'),
        "https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/",
        AsyncStorage.getItem('skywardUser'),
        AsyncStorage.getItem('skywardPass'),
      ]);
// https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/
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

      const valid =
        typeof link === 'string' && link.trim().length > 0 &&
        typeof username === 'string' && username.trim().length > 0 &&
        typeof password === 'string' && password.trim().length > 0;

      return valid;
    } catch (err) {
      console.error('[SkywardAuth] Error checking credentials:', err);
      return false;
    }
  }
}