import { getStoredSkywardCredentials } from './utils/secure-skyward-storage';
import { logger, Modules } from './utils/logger';

const SKYWARD_LINK = 'https://skyward-eisdprod.iscorp.com/scripts/wsisa.dll/WService=wsedueanesisdtx/';

export class SkywardAuth {
  static async get(): Promise<SkywardAuthInfo | null> {
    try {
      const credentials = await getStoredSkywardCredentials();
      if (!credentials?.username || !credentials.password) {
        console.warn('[SkywardAuth] Missing credentials');
        return null;
      }

      return {
        link: SKYWARD_LINK,
        username: credentials.username,
        password: credentials.password,
      };
    } catch (err) {
      logger.error(Modules.AUTH, 'Error retrieving credentials', err);
      return null;
    }
  }

  static async hasCredentials(): Promise<boolean> {
    try {
      const credentials = await getStoredSkywardCredentials();
      return !!(credentials?.username && credentials.password);
    } catch (err) {
      logger.error(Modules.AUTH, 'Error checking credentials', err);
      return false;
    }
  }
}
