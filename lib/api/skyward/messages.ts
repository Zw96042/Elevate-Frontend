// Skyward messages API - Direct Skyward calls (no backend)
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes, Message } from '../../types/api';
import { logger, Modules, log } from '../../utils/logger';

/**
 * Fetch all messages from Skyward directly
 */
export async function fetchMessages(
  sessionCodes: SkywardSessionCodes,
  baseUrl: string
): Promise<Message[]> {
  const startTime = Date.now();
  log.api.request(Modules.API_MESSAGES, 'sfhome01.w');
  
  let allMessagesHtml = '';
  let lastMessageId: string | null = null;
  let keepLoading = true;
  let count = 0;

  try {
    // Initial fetch
    const initialPostData = new URLSearchParams({ ...sessionCodes });
    const initialUrl = baseUrl + 'sfhome01.w';
    
    const initialResponse = await axios.post(initialUrl, initialPostData.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    });

    if (
      initialResponse.data.includes('Your session has expired') ||
      initialResponse.data.includes('Your session has timed out')
    ) {
      const error = new Error('Session expired');
      (error as any).code = 'SESSION_EXPIRED';
      throw error;
    }

    allMessagesHtml += initialResponse.data;
    lastMessageId = extractLastMessageId(initialResponse.data);
    logger.debug(Modules.API_MESSAGES, 'Initial batch loaded');

    // Load more messages (up to 4 batches)
    while (keepLoading && lastMessageId && count < 4) {
      const postData = new URLSearchParams({
        action: 'moreMessages',
        lastMessageRowId: lastMessageId,
        ishttp: 'true',
        sessionid: sessionCodes.sessionid,
        encses: sessionCodes.encses,
        dwd: sessionCodes.dwd,
        wfaacl: sessionCodes.wfaacl,
        'javascript.filesAdded':
          'jquery.1.8.2.js,qsfmain001.css,sfhome001.css,qsfmain001.min.js,sfhome001.js',
        requestId: Date.now().toString(),
      });

      const url = `${baseUrl}httploader.p?file=sfhome01.w`;

      const headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': 'Mozilla/5.0 (compatible; BetterSkywardClient/1.0)',
      };

      const resp = await axios.post(url, postData.toString(), { headers });

      if (!resp.data || resp.data.trim().length === 0) {
        keepLoading = false;
      } else {
        allMessagesHtml += resp.data;
        const newLastId = extractLastMessageId(resp.data);
        if (!newLastId || newLastId === lastMessageId) {
          keepLoading = false;
        } else {
          lastMessageId = newLastId;
        }
      }
      count++;
      logger.debug(Modules.API_MESSAGES, `Loaded batch ${count}`);
    }

    const messages = parseMessages(allMessagesHtml);
    const duration = Date.now() - startTime;
    log.api.success(Modules.API_MESSAGES, 'sfhome01.w', duration);
    logger.info(Modules.API_MESSAGES, `Parsed ${messages.length} messages from ${count + 1} batches`);
    
    return messages;
  } catch (error) {
    const duration = Date.now() - startTime;
    log.api.error(Modules.API_MESSAGES, 'sfhome01.w', duration, error);
    throw error;
  }
}

/**
 * Fetch more messages (pagination)
 */
export async function fetchMoreMessages(
  sessionCodes: SkywardSessionCodes,
  baseUrl: string,
  lastMessageId: string,
  limit: number = 10
): Promise<Message[]> {
  const startTime = Date.now();
  logger.debug(Modules.API_MESSAGES, `Fetching more messages (limit: ${limit})`);
  
  const allHtml: string[] = [];
  let currentLastId: string | null = lastMessageId;
  let totalLoaded = 0;
  let keepLoading = true;
  let batchCount = 0;

  try {
    while (keepLoading && currentLastId && totalLoaded < limit) {
      const postData = new URLSearchParams({
        action: 'moreMessages',
        lastMessageRowId: currentLastId,
        ishttp: 'true',
        sessionid: sessionCodes.sessionid,
        encses: sessionCodes.encses,
        dwd: sessionCodes.dwd,
        wfaacl: sessionCodes.wfaacl,
        'javascript.filesAdded':
          'jquery.1.8.2.js,qsfmain001.css,sfhome001.css,qsfmain001.min.js,sfhome001.js',
        requestId: Date.now().toString(),
      });

      const url = `${baseUrl}httploader.p?file=sfhome01.w`;
      const headers = {
        'Content-Type': 'application/x-www-form-urlencoded',
        'X-Requested-With': 'XMLHttpRequest',
        'User-Agent': 'Mozilla/5.0 (compatible; BetterSkywardClient/1.0)',
      };

      const resp = await axios.post(url, postData.toString(), { headers });
      
      if (!resp.data || resp.data.trim().length === 0) break;
      
      if (resp.data.includes('logout')) {
        const error = new Error('Session Expired');
        (error as any).code = 'SESSION_EXPIRED';
        throw error;
      }

      allHtml.push(resp.data);
      batchCount++;

      const newLastId = extractLastMessageId(resp.data);
      if (!newLastId || newLastId === currentLastId) break;

      currentLastId = newLastId;
      totalLoaded += parseMessages(resp.data).length;
    }

    const combinedHtml = allHtml.join('');
    const messages = parseMessages(combinedHtml);
    const duration = Date.now() - startTime;
    
    logger.success(Modules.API_MESSAGES, `Loaded ${messages.length} more messages in ${batchCount} batches (${duration}ms)`);
    return messages;
  } catch (error) {
    const duration = Date.now() - startTime;
    logger.error(Modules.API_MESSAGES, `Failed to fetch more messages (${duration}ms)`, error);
    throw error;
  }
}

// Helper functions

function extractLastMessageId(rawResponse: string): string | null {
  const cdataMatch = rawResponse.match(/<output><!\[CDATA\[(.*?)\]\]><\/output>/s);
  let htmlFragment = rawResponse;
  if (cdataMatch && cdataMatch[1]) {
    htmlFragment = cdataMatch[1];
  }

  const root = parse(htmlFragment);
  const messages = root.querySelectorAll('li.feedItem.allowRemove');
  if (messages.length === 0) return null;

  const lastMsg = messages[messages.length - 1];
  const msgWrap = lastMsg.querySelector('.messageWrap');
  return msgWrap ? msgWrap.getAttribute('data-wall-id') : null;
}

function parseMessages(html: string): Message[] {
  const root = parse(html);

  // Map to hold content pieces keyed by spanId
  const contentMap = new Map<string, Array<{ content: string; index: number }>>();

  // Extract message content from JavaScript
  const globalRegex =
    /\$\('<var>(?:<div class=\\?'msgDetail\\?'[^>]*>)?([\s\S]*?)(?:<\/div><\/div>)?<\/var>'\)\.appendTo\('#(messageText_[^']+)'\);/g;

  for (const match of html.matchAll(globalRegex)) {
    const fullHtml = match[1];
    const spanId = match[2];

    const parsed = parse(`<div class='msgDetail'>${fullHtml}</div>`);
    const msgElem = parsed.querySelector('.msgDetail');

    // Convert anchor tags to markdown
    msgElem &&
      msgElem.querySelectorAll('a').forEach((a) => {
        const text = a.text.trim();
        const href = a.getAttribute('href');
        if (href) {
          a.replaceWith(parse(`[${text}](${href})`));
        }
      });

    // Preserve bold text
    msgElem &&
      msgElem.querySelectorAll('b').forEach((b) => {
        b.insertAdjacentHTML('beforebegin', '**');
        b.insertAdjacentHTML('afterend', '**');
      });

    // Convert list items
    msgElem &&
      msgElem.querySelectorAll('li').forEach((li) => {
        li.insertAdjacentHTML('beforebegin', '\t• ');
        li.insertAdjacentHTML('afterend', '\n');
      });

    // Add line breaks
    msgElem &&
      msgElem.querySelectorAll('div').forEach((div) => {
        const content = div.innerText.trim();
        if (content === '\xa0' || content === '') {
          div.replaceWith(parse('<div>__LINE_BREAK__</div>'));
        } else {
          div.insertAdjacentHTML('afterend', '__LINE_BREAK__');
        }
      });

    msgElem &&
      msgElem.querySelectorAll('p').forEach((p) => {
        const content = p.innerText.trim();
        if (content === '\xa0' || content === '') {
          p.replaceWith(parse('<div>__LINE_BREAK__</div>'));
        } else {
          p.insertAdjacentHTML('afterend', '__LINE_BREAK__');
        }
      });

    const cleaned = msgElem
      ? msgElem.textContent
          .replace(/__LINE_BREAK__/g, '\n')
          .replace(/\n{2,}/g, '\n\n')
          .trim()
      : '';

    if (!contentMap.has(spanId)) contentMap.set(spanId, []);
    contentMap.get(spanId)!.push({ content: cleaned, index: match.index });
  }

  const messages: Message[] = [];

  const allMessageItems = root.querySelectorAll('li.feedItem.allowRemove');
  allMessageItems.forEach((li) => {
    const msgWrap = li.querySelector('.messageWrap');
    if (!msgWrap) return;

    const rawClassAttr = msgWrap.getAttribute('class') || '';

    // Extract class name
    const classLink = msgWrap.querySelector('.messageHead > .text > a[data-type="class"]');
    let className = 'Administrator';
    if (classLink) {
      const matchClass = classLink.text.match(/\(([^/]+)\//);
      if (matchClass && matchClass[1]) {
        className = matchClass[1].trim();
      }
    } else if (rawClassAttr.includes('message_general')) {
      className = 'Administrator';
    }

    const fromLink = msgWrap.querySelector('.messageHead > .text > a[data-type="teacher"]');
    const from = fromLink
      ? fromLink.text.trim()
      : className === 'Administrator'
      ? 'Administrator'
      : '';

    const dateElem = msgWrap.querySelector('.messageBody > .date');
    const date = dateElem ? dateElem.text.trim() : '';

    const subjectElem = msgWrap.querySelector('.messageBody > .text > .Subject');
    let subject = subjectElem ? subjectElem.text.trim() : '';

    if (!subject) {
      if (className === 'Administrator') {
        subject = 'Administrator Message';
      } else {
        const fallbackHeader = msgWrap.querySelector('.messageBody > .text > .NoHeader');
        if (fallbackHeader) {
          subject = fallbackHeader.text.trim();
        }
      }
    }

    const spanElem = msgWrap.querySelector('.messageBody > .text > span[id^="messageText_"]');
    let content = '';
    if (spanElem) {
      const spanId = spanElem.id;
      if (contentMap.has(spanId)) {
        content = contentMap
          .get(spanId)!
          .sort((a, b) => a.index - b.index)
          .map((item) => item.content)
          .join('\n\n');
      }
    }

    const messageRowId = msgWrap.getAttribute('data-wall-id') || '';

    messages.push({ className, messageRowId, subject, from, date, content });
  });

  return messages;
}
