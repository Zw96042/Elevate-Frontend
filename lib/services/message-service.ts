// Message service - handles all message operations
import { fetchMessages, fetchMoreMessages, getRequiredSessionData, handleAPIError } from '../api';
import { AuthService } from './auth-service';
import { RequestDeduplicator } from '../utils/request-deduplicator';
import { Message } from '../types/api';
import { logger, Modules, log } from '../utils/logger';

export interface MessageResult {
  messages: Message[];
  success: boolean;
  error?: string;
}

const MESSAGES_REQUEST_KEY = 'skyward_messages';

export class MessageService {
  /**
   * Load messages with automatic retry on session expiration
   */
  static async loadMessages(retryCount = 0): Promise<MessageResult> {
    const endTimer = logger.time(Modules.MESSAGE, 'loadMessages');
    
    if (retryCount > 1) {
      logger.error(Modules.MESSAGE, 'Max retry attempts reached');
      return { messages: [], success: false, error: 'Max retry attempts reached' };
    }

    try {
      // Check session first
      const hasSession = await AuthService.hasValidSession();
      if (!hasSession) {
        logger.info(Modules.MESSAGE, 'No valid session, authenticating...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          logger.error(Modules.MESSAGE, 'Authentication failed', authResult.error);
          return { messages: [], success: false, error: authResult.error };
        }
        return this.loadMessages(retryCount + 1);
      }

      // Use request deduplication
      const result = await RequestDeduplicator.deduplicate(MESSAGES_REQUEST_KEY, async () => {
        try {
          const { sessionCodes, baseUrl } = await getRequiredSessionData();
          const data = await fetchMessages(sessionCodes, baseUrl);

          // Sort by date
          const sorted = data.sort(
            (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime()
          );

          logger.success(Modules.MESSAGE, `Loaded ${sorted.length} messages`);
          return { messages: sorted, success: true };
        } catch (error: any) {
          return handleAPIError(error, 'MessageService.loadMessages');
        }
      });
      
      endTimer();
      return result;
    } catch (error: any) {
      // Handle session expiration
      if (error.code === 'SESSION_EXPIRED' && retryCount === 0) {
        logger.warn(Modules.MESSAGE, 'Session expired, re-authenticating...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          logger.error(Modules.MESSAGE, 'Re-authentication failed', authResult.error);
          return { messages: [], success: false, error: authResult.error };
        }
        return this.loadMessages(retryCount + 1);
      }

      logger.error(Modules.MESSAGE, 'Failed to load messages', error);
      endTimer();
      return { messages: [], success: false, error: error.message };
    }
  }

  /**
   * Load more messages (pagination)
   */
  static async loadMoreMessages(
    lastMessageId: string,
    limit: number = 10,
    retryCount = 0
  ): Promise<MessageResult> {
    logger.debug(Modules.MESSAGE, `Loading more messages (limit: ${limit})`);
    
    if (retryCount > 1) {
      logger.error(Modules.MESSAGE, 'Max retry attempts reached for pagination');
      return { messages: [], success: false, error: 'Max retry attempts reached' };
    }

    try {
      // Check session first
      const hasSession = await AuthService.hasValidSession();
      if (!hasSession) {
        logger.info(Modules.MESSAGE, 'No valid session for pagination, authenticating...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          return { messages: [], success: false, error: authResult.error };
        }
        return this.loadMoreMessages(lastMessageId, limit, retryCount + 1);
      }

      const { sessionCodes, baseUrl } = await getRequiredSessionData();
      const data = await fetchMoreMessages(sessionCodes, baseUrl, lastMessageId, limit);

      logger.success(Modules.MESSAGE, `Loaded ${data.length} more messages`);
      return { messages: data, success: true };
    } catch (error: any) {
      // Handle session expiration
      if (error.code === 'SESSION_EXPIRED' && retryCount === 0) {
        logger.warn(Modules.MESSAGE, 'Session expired during pagination, re-authenticating...');
        const authResult = await AuthService.authenticate();
        if (!authResult.success) {
          return { messages: [], success: false, error: authResult.error };
        }
        return this.loadMoreMessages(lastMessageId, limit, retryCount + 1);
      }

      logger.error(Modules.MESSAGE, 'Failed to load more messages', error);
      return { messages: [], success: false, error: error.message };
    }
  }
}
