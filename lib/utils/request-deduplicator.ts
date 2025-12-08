// Prevents duplicate concurrent requests
import { logger, Modules } from './logger';

export class RequestDeduplicator {
  private static pendingRequests = new Map<string, Promise<any>>();

  /**
   * Execute a request with deduplication
   * If the same key is already pending, return the existing promise
   */
  static async deduplicate<T>(
    key: string,
    requestFn: () => Promise<T>
  ): Promise<T> {
    // Check if request is already pending
    if (this.pendingRequests.has(key)) {
      logger.debug(Modules.DEDUP, `Reusing pending request: ${key}`);
      return this.pendingRequests.get(key) as Promise<T>;
    }

    // Create new request
    logger.debug(Modules.DEDUP, `Starting new request: ${key}`);
    const promise = requestFn()
      .finally(() => {
        // Clean up after request completes
        this.pendingRequests.delete(key);
        logger.debug(Modules.DEDUP, `Request completed: ${key}`);
      });

    this.pendingRequests.set(key, promise);
    return promise;
  }

  /**
   * Clear all pending requests
   */
  static clear(): void {
    const count = this.pendingRequests.size;
    this.pendingRequests.clear();
    logger.info(Modules.DEDUP, `Cleared ${count} pending requests`);
  }

  /**
   * Clear a specific pending request
   */
  static clearKey(key: string): void {
    this.pendingRequests.delete(key);
    logger.debug(Modules.DEDUP, `Cleared pending request: ${key}`);
  }
}
