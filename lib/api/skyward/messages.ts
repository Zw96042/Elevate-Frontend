// Skyward messages API - Direct Skyward calls (no backend)
import axios from 'axios';
import { parse } from 'node-html-parser';
import { SkywardSessionCodes, Message } from '../../types/api';
import { logger, Modules, log } from '../../utils/logger';
import { safeMessageURL } from '../../utils/message-links';

/**
 * Fetch all messages from Skyward directly
 */
export async function fetchMessages(
  sessionCodes: SkywardSessionCodes,
  baseUrl: string
): Promise<Message[]> {
  const startTime = Date.now();
  log.api.request(Modules.API_MESSAGES, 'sfhome01.w');
  
  try {
    // Return the first page immediately. Older pages are loaded through the
    // UI's explicit pagination path instead of blocking initial rendering.
    const initialPostData = new URLSearchParams({ ...sessionCodes });
    const initialUrl = baseUrl + 'sfhome01.w';
    
    const initialResponse = await axios.post(initialUrl, initialPostData.toString(), {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      timeout: 30000,
    });

    if (
      initialResponse.data.includes('Your session has expired') ||
      initialResponse.data.includes('Your session has timed out')
    ) {
      const error = new Error('Session expired');
      (error as any).code = 'SESSION_EXPIRED';
      throw error;
    }

    const messages = parseMessages(initialResponse.data, 'initial');
    const duration = Date.now() - startTime;
    log.api.success(Modules.API_MESSAGES, 'sfhome01.w', duration);
    logger.info(Modules.API_MESSAGES, `Parsed ${messages.length} messages from the initial batch`);
    
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

      const resp = await axios.post(url, postData.toString(), { headers, timeout: 30000 });
      
      if (!resp.data || resp.data.trim().length === 0) break;
      
      if (resp.data.includes('logout')) {
        const error = new Error('Session Expired');
        (error as any).code = 'SESSION_EXPIRED';
        throw error;
      }

      const fragment = extractMessageFragment(resp.data);
      allHtml.push(fragment);
      batchCount++;

      const parsedBatch = parseMessages(fragment, 'pagination');
      const newLastId = extractLastMessageId(fragment);
      if (!newLastId || newLastId === currentLastId) break;

      currentLastId = newLastId;
      totalLoaded += parsedBatch.length;
    }

    const combinedHtml = allHtml.join('');
    const messages = combinedHtml ? parseMessages(combinedHtml, 'pagination') : [];
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
  return msgWrap ? msgWrap.getAttribute('data-wall-id') ?? null : null;
}

function extractMessageFragment(rawResponse: string): string {
  if (/<output\b/i.test(rawResponse)) {
    const match = rawResponse.match(/<output><!\[CDATA\[([\s\S]*?)\]\]><\/output>/i);
    if (!match) throw new Error('Skyward message response was incomplete');
    return match[1];
  }
  return rawResponse;
}

export function parseMessages(
  html: string,
  context: 'initial' | 'pagination' = 'initial'
): Message[] {
  const root = parse(html);

  // Map to hold content pieces keyed by spanId
  const contentMap = new Map<string, Array<{ content: string; index: number }>>();

  // Extract message content from JavaScript
  const globalRegex =
    /\$\('<var>(?:<div class=\\?'msgDetail\\?'[^>]*>)?([\s\S]*?)(?:<\/div><\/div>)?<\/var>'\)\.appendTo\('#(messageText_[^']+)'\);/g;

  for (const match of html.matchAll(globalRegex)) {
    const fullHtml = match[1];
    const spanId = match[2];
    const cleaned = renderMessageBody(fullHtml);

    if (!contentMap.has(spanId)) contentMap.set(spanId, []);
    contentMap.get(spanId)!.push({ content: cleaned, index: match.index });
  }

  const messages: Message[] = [];

  const allMessageItems = root.querySelectorAll('li.feedItem.allowRemove');
  if (allMessageItems.length === 0) {
    if (context === 'pagination' && html.trim() === '') return [];
    const hasFeedAnchor =
      root.querySelector('#messageFeed') !== null ||
      root.querySelector('#messageWall') !== null ||
      root.querySelector('#messageCenter') !== null ||
      root.querySelector('.messageFeed') !== null ||
      root.querySelector('.messageList') !== null;
    if (context === 'initial' && hasFeedAnchor) return [];
    throw new Error('Skyward message feed was not found');
  }

  allMessageItems.forEach((li) => {
    const msgWrap = li.querySelector('.messageWrap');
    if (!msgWrap) throw new Error('Skyward message item was missing its wrapper');
    const messageRowId = msgWrap.getAttribute('data-wall-id') || '';
    if (!messageRowId) throw new Error('Skyward message item was missing its identity');
    if (
      !msgWrap.querySelector('.messageHead') ||
      !msgWrap.querySelector('.messageBody') ||
      !msgWrap.querySelector('.messageBody > .text')
    ) {
      throw new Error('Skyward message item was structurally incomplete');
    }

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

    messages.push({ className, messageRowId, subject, from, date, content });
  });

  if (messages.length !== allMessageItems.length) {
    throw new Error('Skyward message feed could not be parsed completely');
  }

  return messages;
}

export function renderMessageBody(fullHtml: string): string {
  const parsed = parse(`<div class='msgDetail'>${fullHtml}</div>`);
  const msgElem = parsed.querySelector('.msgDetail');
  if (!msgElem) return '';

  msgElem.querySelectorAll('a').forEach((anchor) => {
    const text = anchor.text.trim();
    const href = anchor.getAttribute('href');
    const safeURL = href ? safeMessageURL(href) : null;
    const replacement = safeURL ? `[${text}](${safeURL})` : text;
    anchor.replaceWith(parse(escapeHTML(replacement)));
  });

  msgElem.querySelectorAll('b').forEach((bold) => {
    bold.insertAdjacentHTML('beforebegin', '**');
    bold.insertAdjacentHTML('afterend', '**');
  });

  msgElem.querySelectorAll('li').forEach((item) => {
    item.insertAdjacentHTML('beforebegin', '\t• ');
    item.insertAdjacentHTML('afterend', '\n');
  });

  for (const selector of ['div', 'p']) {
    msgElem.querySelectorAll(selector).forEach((block) => {
      const content = block.innerText.trim();
      if (content === '\xa0' || content === '') {
        block.replaceWith(parse('<div>__LINE_BREAK__</div>'));
      } else {
        block.insertAdjacentHTML('afterend', '__LINE_BREAK__');
      }
    });
  }

  return msgElem.textContent
    .replace(/__LINE_BREAK__/g, '\n')
    .replace(/\n{2,}/g, '\n\n')
    .trim();
}

function escapeHTML(value: string): string {
  return value
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
