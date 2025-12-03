const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const CHAT_CHANNELS = {
  messages_oni: {
    role: 'oni',
    title: '鬼チャット',
    targetRole: 'oni',
  },
  messages_runner: {
    role: 'runner',
    title: '逃走者チャット',
    targetRole: 'runner',
  },
  messages_general: {
    role: 'general',
    title: '総合チャット',
  },
};

const INACTIVITY_DAYS = 30;
const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

const SUBCOLLECTION_ACTIVITY_FIELDS = [
  {
    name: 'players',
    orderFields: ['updatedAt', 'joinedAt'],
  },
  {
    name: 'pins',
    orderFields: ['updatedAt', 'createdAt'],
  },
  {
    name: 'captures',
    orderFields: ['createdAt'],
  },
  {
    name: 'events',
    orderFields: ['createdAt'],
  },
  {
    name: 'messages_oni',
    orderFields: ['timestamp'],
  },
  {
    name: 'messages_runner',
    orderFields: ['timestamp'],
  },
  {
    name: 'messages_general',
    orderFields: ['timestamp'],
  },
];

const DEFAULT_GAME_DURATION_SECONDS = 7200;
const DEFAULT_PIN_COUNT = 10;
const DEFAULT_TIMED_EVENT_REQUIRED_RUNNERS = 1;
const YAMANOTE_CENTER = { lat: 35.735, lng: 139.725 };
const YAMANOTE_BOUNDS = {
  south: 35.6,
  west: 139.63,
  north: 35.88,
  east: 139.82,
};
const PIN_DUPLICATE_PRECISION = 6;
const MAX_PIN_COUNT = 20;
const TIMED_EVENT_TIMEOUT_SWEEP_INTERVAL_MS = 15 * 1000;
const TIMED_EVENT_TIMEOUT_SWEEP_COUNT = 4;
const YAMANOTE_STATION_POLYGON = [
  { lat: 35.681236, lng: 139.767125 },
  { lat: 35.673146, lng: 139.763912 },
  { lat: 35.66623, lng: 139.758987 },
  { lat: 35.654998, lng: 139.757531 },
  { lat: 35.645551, lng: 139.747148 },
  { lat: 35.635547, lng: 139.74201 },
  { lat: 35.628479, lng: 139.738758 },
  { lat: 35.6197, lng: 139.728553 },
  { lat: 35.62565, lng: 139.723539 },
  { lat: 35.633998, lng: 139.715828 },
  { lat: 35.646687, lng: 139.710084 },
  { lat: 35.658034, lng: 139.701636 },
  { lat: 35.67022, lng: 139.702042 },
  { lat: 35.683061, lng: 139.702042 },
  { lat: 35.690921, lng: 139.700258 },
  { lat: 35.701306, lng: 139.700044 },
  { lat: 35.712285, lng: 139.703782 },
  { lat: 35.721994, lng: 139.706181 },
  { lat: 35.728926, lng: 139.71038 },
  { lat: 35.731145, lng: 139.728046 },
  { lat: 35.733492, lng: 139.739219 },
  { lat: 35.736453, lng: 139.74801 },
  { lat: 35.738524, lng: 139.760968 },
  { lat: 35.732231, lng: 139.766942 },
  { lat: 35.727772, lng: 139.770987 },
  { lat: 35.72128, lng: 139.778576 },
  { lat: 35.713768, lng: 139.777254 },
  { lat: 35.707118, lng: 139.774219 },
  { lat: 35.698353, lng: 139.773114 },
  { lat: 35.69169, lng: 139.770883 },
  { lat: 35.681236, lng: 139.767125 },
];

async function handleChatNotification({
  snapshot,
  gameId,
  messageId,
  channelKey,
  channelMeta,
}) {
  const data = snapshot.data() || {};
  if (!data || data.type === 'system') {
    return null;
  }

  const rawMessage = (data.message || '').toString().trim();
  if (!rawMessage) {
    return null;
  }

  const senderUid = data.uid || '';
  const senderName = (data.nickname || '').toString().trim() || '仲間';
  const sanitizedMessage = rawMessage.replace(/\s+/g, ' ').slice(0, 120);

  try {
    const recipients = await fetchChatRecipients({
      gameId,
      senderUid,
      targetRole: channelMeta.targetRole,
    });

    if (!recipients) {
      return null;
    }

    const notification = {
      title: channelMeta.title,
      body: `${senderName}: ${sanitizedMessage}`,
    };
    const dataPayload = {
      gameId,
      messageId: messageId || '',
      role: channelMeta.role,
      senderUid,
    };

    await sendChatNotificationBatches({
      gameId,
      channelKey,
      channelMeta,
      notification,
      dataPayload,
      tokens: recipients.tokens,
      tokenOwners: recipients.tokenOwners,
    });
  } catch (error) {
    functions.logger.error('Chat notification handling failed', {
      error,
      gameId,
      channel: channelKey,
    });
  }

  return null;
}

async function fetchChatRecipients({ gameId, senderUid, targetRole }) {
  let playersQuery = db
    .collection('games')
    .doc(gameId)
    .collection('players');
  if (targetRole) {
    playersQuery = playersQuery.where('role', '==', targetRole);
  }
  const playersSnap = await playersQuery.get();

  if (playersSnap.empty) {
    return null;
  }

  const tokens = [];
  const tokenOwners = new Map();

  playersSnap.forEach((doc) => {
    if (doc.id === senderUid) {
      return;
    }
    const playerData = doc.data() || {};
    const fcmTokens = playerData.fcmTokens;
    if (!Array.isArray(fcmTokens)) {
      return;
    }
    fcmTokens.forEach((token) => {
      if (typeof token === 'string' && token.length > 0) {
        tokens.push(token);
        if (!tokenOwners.has(token)) {
          tokenOwners.set(token, doc.id);
        }
      }
    });
  });

  if (tokens.length === 0) {
    return null;
  }

  return { tokens, tokenOwners };
}

async function sendChatNotificationBatches({
  gameId,
  channelKey,
  channelMeta,
  notification,
  dataPayload,
  tokens,
  tokenOwners,
}) {
  const invalidTokens = new Set();
  const chunkSize = 500;

  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      functions.logger.info('Sending chat notification batch', {
        gameId,
        role: channelMeta.role,
        channel: channelKey,
        batchSize: chunk.length,
      });
      const response = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification,
        data: dataPayload,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'chat_messages',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: notification,
              sound: 'default',
            },
          },
        },
      });
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const code = res.error?.code || '';
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            invalidTokens.add(chunk[idx]);
          } else {
            functions.logger.error('Chat notification delivery failed', {
              code,
              error: res.error,
              token: chunk[idx],
              gameId,
              role: channelMeta.role,
              channel: channelKey,
            });
          }
        }
      });
    } catch (error) {
      functions.logger.error('Failed to send chat notifications', {
        error,
        gameId,
        role: channelMeta.role,
        channel: channelKey,
      });
    }
  }

  if (invalidTokens.size > 0) {
    await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
  }
}

exports.onChatMessageCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/{collectionId}/{messageId}')
  .onCreate(async (snapshot, context) => {
    const { gameId, collectionId, messageId } = context.params;
    const channelMeta = CHAT_CHANNELS[collectionId];
    if (!channelMeta) {
      return null;
    }

    return handleChatNotification({
      snapshot,
      gameId,
      messageId,
      channelKey: collectionId,
      channelMeta,
    });
  });

exports.notifyPlayersOnGameStatusChange = functions
  .region('us-central1')
  .firestore.document('games/{gameId}')
  .onUpdate(async (change, context) => {
    const beforeData = change.before.data();
    const afterData = change.after.data();
    if (!afterData) {
      return null;
    }
    const previousStatus = beforeData?.status;
    const currentStatus = afterData.status;
    const shouldNotifyStart =
      currentStatus === 'running' && previousStatus !== 'running';
    const shouldNotifyEnd =
      currentStatus === 'ended' && previousStatus !== 'ended';

    if (!shouldNotifyStart && !shouldNotifyEnd) {
      return null;
    }

    const gameId = context.params.gameId;
    try {
      const playersSnapshot = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

      if (playersSnapshot.empty) {
        functions.logger.info(
          'No players found for game start notification',
          { gameId }
        );
        return null;
      }

      const tokens = [];
      const tokenOwners = new Map();

      playersSnapshot.forEach((doc) => {
        const data = doc.data() || {};
        const playerTokens = data.fcmTokens;
        if (!Array.isArray(playerTokens)) {
          return;
        }
        playerTokens.forEach((token) => {
          if (typeof token === 'string' && token.length > 0) {
            tokens.push(token);
            if (!tokenOwners.has(token)) {
              tokenOwners.set(token, doc.id);
            }
          }
        });
      });

      if (tokens.length === 0) {
        functions.logger.info('No players to notify on status change', {
          gameId,
        });
        return null;
      }

      const invalidTokens = new Set();
      if (shouldNotifyStart) {
        await sendStatusNotificationBatch({
          gameId,
          tokens,
          tokenOwners,
          invalidTokens,
          notification: {
            title: 'ゲームが開始しました',
            body: 'アプリを開いてマップを確認しましょう。',
          },
          dataPayload: {
            type: 'game_start',
            gameId,
          },
          apnsCategory: 'GAME_START',
        });
      }
      if (shouldNotifyEnd) {
        await sendStatusNotificationBatch({
          gameId,
          tokens,
          tokenOwners,
          invalidTokens,
          notification: {
            title: 'ゲームが終了しました',
            body: '結果を確認しましょう。',
          },
          dataPayload: {
            type: 'game_end',
            gameId,
          },
          apnsCategory: 'GAME_END',
        });
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Game status notification handling failed', {
        error,
        gameId,
      });
    }

    return null;
  });

exports.onTimedEventCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/events/{eventId}')
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data || data.type !== 'timed_event') {
      return null;
    }

    const { gameId } = context.params;
    const quarter = toInt(data.quarter ?? data.quarterIndex);
    const requiredRunners = toInt(data.requiredRunners);
    const durationSeconds = toInt(data.eventDurationSeconds);

    try {
      const playersSnapshot = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

      if (playersSnapshot.empty) {
        functions.logger.info('No players for timed event notification', {
          gameId,
        });
        return null;
      }

      const tokens = [];
      const tokenOwners = new Map();
      playersSnapshot.forEach((doc) => {
        const playerData = doc.data() || {};
        const playerTokens = playerData.fcmTokens;
        if (!Array.isArray(playerTokens)) {
          return;
        }
        playerTokens.forEach((token) => {
          if (typeof token === 'string' && token.length > 0) {
            tokens.push(token);
            if (!tokenOwners.has(token)) {
              tokenOwners.set(token, doc.id);
            }
          }
        });
      });

      if (tokens.length === 0) {
        functions.logger.info('No tokens for timed event notification', {
          gameId,
        });
        return null;
      }

      const quarterLabel = getQuarterLabel(quarter);
      const durationLabel = formatDurationLabel(durationSeconds);
      const bodySegments = [
        `${quarterLabel}のイベントが発生しました。`,
      ];
      if (requiredRunners > 0 && durationLabel) {
        bodySegments.push(
          `${durationLabel}以内に${requiredRunners}人で発電所を解除してください。`
        );
      } else {
        bodySegments.push('アプリを開いてマップを確認してください。');
      }

      const notification = {
        title: 'イベント発生',
        body: bodySegments.join(' '),
      };
      const dataPayload = {
        type: 'timed_event',
        gameId,
        quarter: quarter.toString(),
      };

      const invalidTokens = new Set();
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);
        try {
          functions.logger.info('Sending timed event notification batch', {
            gameId,
            batchSize: chunk.length,
          });
          const response = await messaging.sendEachForMulticast({
            tokens: chunk,
            notification,
            data: dataPayload,
            android: {
              priority: 'high',
              notification: {
                sound: 'default',
                channelId: 'map_events',
              },
            },
            apns: {
              headers: {
                'apns-priority': '10',
                'apns-push-type': 'alert',
              },
              payload: {
                aps: {
                  alert: notification,
                  sound: 'default',
                  category: 'TIMED_EVENT',
                },
              },
            },
          });
          response.responses.forEach((res, idx) => {
            if (!res.success) {
              const code = res.error?.code || '';
              if (
                code === 'messaging/registration-token-not-registered' ||
                code === 'messaging/invalid-registration-token'
              ) {
                invalidTokens.add(chunk[idx]);
              } else {
                functions.logger.error(
                  'Timed event notification delivery failed',
                  {
                    code,
                    error: res.error,
                    token: chunk[idx],
                    gameId,
                  }
                );
              }
            }
          });
        } catch (error) {
          functions.logger.error(
            'Failed to send timed event notification batch',
            {
              error,
              gameId,
            }
          );
        }
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Timed event notification handling failed', {
        error,
        gameId,
      });
    }

    return null;
  });

exports.onTimedEventResultCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/events/{eventId}')
  .onCreate(async (snapshot, context) => {
    const data = snapshot.data();
    if (!data || data.type !== 'timed_event_result') {
      return null;
    }

    const rawResult = (data.result || '').toString();
    const result =
      rawResult === 'success' || rawResult === 'failure' ? rawResult : null;
    if (!result) {
      functions.logger.info('Timed event result missing result value', {
        gameId: context.params.gameId,
        eventId: snapshot.id,
      });
      return null;
    }

    const { gameId } = context.params;

    try {
      const playersSnapshot = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .get();

      if (playersSnapshot.empty) {
        functions.logger.info(
          'No players for timed event result notification',
          { gameId }
        );
        return null;
      }

      const tokens = [];
      const tokenOwners = new Map();
      playersSnapshot.forEach((doc) => {
        const playerData = doc.data() || {};
        const playerTokens = playerData.fcmTokens;
        if (!Array.isArray(playerTokens)) {
          return;
        }
        playerTokens.forEach((token) => {
          if (typeof token === 'string' && token.length > 0) {
            tokens.push(token);
            if (!tokenOwners.has(token)) {
              tokenOwners.set(token, doc.id);
            }
          }
        });
      });

      if (tokens.length === 0) {
        functions.logger.info('No tokens for timed event result notification', {
          gameId,
        });
        return null;
      }

      const isSuccess = result === 'success';
      const body = isSuccess
        ? '未解除の残りの発電機の場所が変わりました。'
        : '鬼の捕獲半径が2倍になり、未解除の発電機の場所が変わりました。';

      const invalidTokens = new Set();
      await sendStatusNotificationBatch({
        gameId,
        tokens,
        tokenOwners,
        invalidTokens,
        notification: {
          title: 'イベント終了',
          body,
        },
        dataPayload: {
          type: 'timed_event_result',
          gameId,
          result,
        },
        apnsCategory: 'TIMED_EVENT_RESULT',
      });

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Timed event result notification handling failed', {
        error,
        gameId,
      });
    }

    return null;
  });

async function removeInvalidTokens(gameId, invalidTokens, tokenOwners) {
  const removals = [];
  invalidTokens.forEach((token) => {
    const ownerUid = tokenOwners.get(token);
    if (!ownerUid) {
      return;
    }

    const update = db
      .collection('games')
      .doc(gameId)
      .collection('players')
      .doc(ownerUid)
      .update({
        fcmTokens: admin.firestore.FieldValue.arrayRemove(token),
      })
      .catch((error) => {
        functions.logger.error('Failed to prune invalid token', {
          token,
          ownerUid,
          error,
          gameId,
        });
      });

    removals.push(update);
  });

  if (removals.length > 0) {
    await Promise.all(removals);
  }
}

exports.cleanupInactiveGames = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB',
  })
  .pubsub.schedule('0 3 * * *')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const cutoffMs = Date.now() - INACTIVITY_DAYS * MILLIS_PER_DAY;
    const gamesSnapshot = await db.collection('games').get();
    if (gamesSnapshot.empty) {
      functions.logger.info('No games found for inactivity cleanup');
      return null;
    }

    let evaluated = 0;
    let deleted = 0;
    for (const doc of gamesSnapshot.docs) {
      evaluated += 1;
      try {
        const lastActivity = await getLastActivityForGame(doc);
        const lastActivityMs = lastActivity?.getTime() ?? null;
        if (!lastActivityMs || lastActivityMs < cutoffMs) {
          await db.recursiveDelete(doc.ref);
          deleted += 1;
          functions.logger.info('Deleted inactive game', {
            gameId: doc.id,
            lastActivity: lastActivity?.toISOString() ?? null,
          });
        }
      } catch (error) {
        functions.logger.error('Failed to evaluate game for cleanup', {
          gameId: doc.id,
          error,
        });
      }
    }

    functions.logger.info('Inactive game cleanup completed', {
      evaluatedGames: evaluated,
      deletedGames: deleted,
      inactivityCutoff: new Date(cutoffMs).toISOString(),
    });
    return null;
  });

exports.processGameAutomations = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB',
  })
  .pubsub.schedule('*/1 * * * *')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    const snapshot = await db
      .collection('games')
      .where('status', 'in', ['countdown', 'running'])
      .get();

    if (snapshot.empty) {
      functions.logger.info('No games to automate');
      return null;
    }

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      try {
        if (data.status === 'countdown') {
          await processCountdownGame(doc.id, data);
        } else if (data.status === 'running') {
          await processRunningGame(doc.id, data);
        }
      } catch (error) {
        functions.logger.error('Failed to process game automation', {
          gameId: doc.id,
          status: data.status,
          error,
        });
      }
    }

    return null;
  });

exports.processTimedEventTimeouts = functions
  .region('us-central1')
  .runWith({
    timeoutSeconds: 540,
    memory: '512MB',
  })
  .pubsub.schedule('*/1 * * * *')
  .timeZone('Asia/Tokyo')
  .onRun(async () => {
    for (let i = 0; i < TIMED_EVENT_TIMEOUT_SWEEP_COUNT; i += 1) {
      await sweepActiveTimedEventTimeouts();
      if (i < TIMED_EVENT_TIMEOUT_SWEEP_COUNT - 1) {
        await wait(TIMED_EVENT_TIMEOUT_SWEEP_INTERVAL_MS);
      }
    }
    return null;
  });

async function sweepActiveTimedEventTimeouts() {
  const snapshot = await db
    .collection('games')
    .where('status', '==', 'running')
    .where('timedEventActive', '==', true)
    .get();
  if (snapshot.empty) {
    return;
  }
  for (const doc of snapshot.docs) {
    const data = doc.data() || {};
    try {
      await maybeResolveTimedEventTimeout(doc.id, data);
    } catch (error) {
      functions.logger.error('Failed to resolve timed event timeout sweep', {
        gameId: doc.id,
        error,
      });
    }
  }
}

async function getLastActivityForGame(doc) {
  const data = doc.data() || {};
  const timestamps = [];
  addTimestampIfPresent(timestamps, data.updatedAt);
  addTimestampIfPresent(timestamps, data.createdAt);
  addTimestampIfPresent(timestamps, data.startAt);
  addTimestampIfPresent(timestamps, data.countdownStartAt);

  for (const config of SUBCOLLECTION_ACTIVITY_FIELDS) {
    const ts = await fetchLatestTimestamp(doc.ref, config);
    if (ts) {
      timestamps.push(ts);
    }
  }

  if (timestamps.length === 0) {
    return null;
  }

  let latest = timestamps[0];
  for (const ts of timestamps) {
    if (ts.getTime() > latest.getTime()) {
      latest = ts;
    }
  }
  return latest;
}

async function fetchLatestTimestamp(docRef, config) {
  for (const field of config.orderFields) {
    try {
      const snapshot = await docRef
        .collection(config.name)
        .orderBy(field, 'desc')
        .limit(1)
        .get();
      if (!snapshot.empty) {
        const value = snapshot.docs[0].get(field);
        const date = convertToDate(value);
        if (date) {
          return date;
        }
      }
    } catch (error) {
      functions.logger.error('Failed to fetch latest timestamp', {
        gameId: docRef.id,
        collection: config.name,
        orderField: field,
        error,
      });
    }
  }
  return null;
}

function addTimestampIfPresent(list, value) {
  const date = convertToDate(value);
  if (date) {
    list.push(date);
  }
}

function convertToDate(value) {
  if (!value) {
    return null;
  }
  if (typeof value.toDate === 'function') {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'string') {
    const date = new Date(value);
    if (!isNaN(date.getTime())) {
      return date;
    }
  }
  return null;
}

async function sendStatusNotificationBatch({
  gameId,
  tokens,
  tokenOwners,
  invalidTokens,
  notification,
  dataPayload,
  apnsCategory,
}) {
  const chunkSize = 500;
  for (let i = 0; i < tokens.length; i += chunkSize) {
    const chunk = tokens.slice(i, i + chunkSize);
    try {
      functions.logger.info('Sending status notification batch', {
        gameId,
        batchSize: chunk.length,
        type: dataPayload?.type ?? 'unknown',
      });
      const response = await messaging.sendEachForMulticast({
        tokens: chunk,
        notification,
        data: dataPayload,
        android: {
          priority: 'high',
          notification: {
            sound: 'default',
            channelId: 'map_events',
          },
        },
        apns: {
          headers: {
            'apns-priority': '10',
            'apns-push-type': 'alert',
          },
          payload: {
            aps: {
              alert: notification,
              sound: 'default',
              category: apnsCategory,
            },
          },
        },
      });
      response.responses.forEach((res, idx) => {
        if (!res.success) {
          const code = res.error?.code || '';
          if (
            code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token'
          ) {
            invalidTokens.add(chunk[idx]);
          } else {
            functions.logger.error('Status notification delivery failed', {
              code,
              error: res.error,
              token: chunk[idx],
              gameId,
              type: dataPayload?.type ?? 'unknown',
            });
          }
        }
      });
    } catch (error) {
      functions.logger.error('Failed to send status notification batch', {
        error,
        gameId,
        type: dataPayload?.type ?? 'unknown',
      });
    }
  }
}

function toInt(value) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return 0;
  }
  return Math.trunc(parsed);
}

function wait(durationMs) {
  return new Promise((resolve) => {
    setTimeout(resolve, durationMs);
  });
}

function formatDurationLabel(seconds) {
  const duration = Math.max(0, toInt(seconds));
  if (duration === 0) {
    return '';
  }
  const minutes = Math.floor(duration / 60);
  const remainingSeconds = duration % 60;
  if (minutes > 0 && remainingSeconds > 0) {
    return `${minutes}分${remainingSeconds}秒`;
  }
  if (minutes > 0) {
    return `${minutes}分`;
  }
  return `${remainingSeconds}秒`;
}

function getQuarterLabel(quarter) {
  switch (quarter) {
    case 1:
      return '第1フェーズ';
    case 2:
      return '第2フェーズ';
    case 3:
      return '最終フェーズ';
    default:
      return 'イベント';
  }
}

async function processCountdownGame(gameId, data) {
  const countdownEnd = resolveCountdownEndDate(data);
  if (!countdownEnd) {
    return;
  }
  if (Date.now() < countdownEnd.getTime()) {
    return;
  }
  await startGameFromServer(gameId);
}

function resolveCountdownEndDate(data) {
  const countdownEndAt = convertToDate(data?.countdownEndAt);
  if (countdownEndAt) {
    return countdownEndAt;
  }
  const countdownStartAt = convertToDate(data?.countdownStartAt);
  const durationSeconds = toInt(data?.countdownDurationSec);
  if (!countdownStartAt || durationSeconds <= 0) {
    return null;
  }
  return new Date(countdownStartAt.getTime() + durationSeconds * 1000);
}

async function startGameFromServer(gameId) {
  const gameRef = db.collection('games').doc(gameId);
  const started = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(gameRef);
    if (!snapshot.exists) {
      return false;
    }
    const data = snapshot.data() || {};
    if (data.status !== 'countdown') {
      return false;
    }
    transaction.update(gameRef, {
      status: 'running',
      startAt: admin.firestore.FieldValue.serverTimestamp(),
      timedEventActive: false,
      timedEventActiveStartedAt: null,
      timedEventActiveDurationSec: null,
      timedEventActiveQuarter: null,
      timedEventTargetPinId: null,
      timedEventRequiredRunners: null,
      timedEventResult: null,
      timedEventResultAt: null,
      oniCaptureRadiusMultiplier: 1.0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (started) {
    functions.logger.info('Automatically started game after countdown', {
      gameId,
    });
  }
  return started;
}

async function processRunningGame(gameId, data) {
  const startAt = convertToDate(data?.startAt);
  if (!startAt) {
    return;
  }
  const totalDurationSeconds = Math.max(
    1,
    toInt(data?.gameDurationSec) || DEFAULT_GAME_DURATION_SECONDS,
  );
  const [playersSnapshot, pinsSnapshot] = await Promise.all([
    db.collection('games').doc(gameId).collection('players').get(),
    db.collection('games').doc(gameId).collection('pins').get(),
  ]);

  const players = playersSnapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));
  const pins = pinsSnapshot.docs.map((doc) => ({
    id: doc.id,
    ...doc.data(),
  }));

  const pinCount = toInt(data?.pinCount) || DEFAULT_PIN_COUNT;

  const endedByPins = await maybeEndGameForPins(gameId, pinCount, pins);
  if (endedByPins) {
    return;
  }
  const endedByRunners = await maybeEndGameForRunners(gameId, pinCount, players);
  if (endedByRunners) {
    return;
  }
  const endedByTimeout = await maybeEndGameByTimeout(
    gameId,
    pinCount,
    startAt,
    totalDurationSeconds,
  );
  if (endedByTimeout) {
    return;
  }

  await maybeResolveTimedEventByPinClear(gameId, data, pins);
  await maybeResolveTimedEventTimeout(gameId, data);
  await maybeTriggerTimedEvent({
    gameId,
    gameData: data,
    players,
    pins,
    startAt,
    totalDurationSeconds,
  });
}

async function maybeEndGameByTimeout(gameId, pinCount, startAt, durationSec) {
  if (!startAt || durationSec <= 0) {
    return false;
  }
  const endTimeMs = startAt.getTime() + durationSec * 1000;
  if (Date.now() < endTimeMs) {
    return false;
  }
  await endGameFromServer(gameId, 'draw', pinCount);
  return true;
}

async function maybeEndGameForPins(gameId, pinCount, pins) {
  if (!Array.isArray(pins) || pins.length === 0) {
    return false;
  }
  const hasPendingPin = pins.some((pin) => !isPinCleared(pin));
  if (hasPendingPin) {
    return false;
  }
  await endGameFromServer(gameId, 'runner_victory', pinCount);
  return true;
}

function isPinCleared(pin) {
  if (!pin) {
    return false;
  }
  if (pin.cleared === true) {
    return true;
  }
  const status = (pin.status || '').toString();
  return status === 'cleared';
}

async function maybeEndGameForRunners(gameId, pinCount, players) {
  if (!Array.isArray(players) || players.length === 0) {
    return false;
  }
  const activeRunners = players.filter(
    (player) => player.role === 'runner' && player.active !== false,
  );
  if (activeRunners.length === 0) {
    return false;
  }
  const hasStandingRunner = activeRunners.some(
    (runner) => (runner.status || 'active') === 'active',
  );
  if (hasStandingRunner) {
    return false;
  }
  await endGameFromServer(gameId, 'oni_victory', pinCount);
  return true;
}

async function maybeTriggerTimedEvent({
  gameId,
  gameData,
  players,
  pins,
  startAt,
  totalDurationSeconds,
}) {
  if (gameData?.timedEventActive) {
    return;
  }
  const elapsedSeconds = Math.floor(
    (Date.now() - startAt.getTime()) / 1000,
  );
  if (elapsedSeconds <= 0) {
    return;
  }
  const triggered = new Set(
    Array.isArray(gameData?.timedEventQuarters)
      ? gameData.timedEventQuarters.map((value) => toInt(value))
      : [],
  );
  const quarterDuration = totalDurationSeconds / 4;
  for (let quarter = 1; quarter <= 3; quarter += 1) {
    if (triggered.has(quarter)) {
      continue;
    }
    const thresholdSeconds = Math.ceil(quarterDuration * quarter);
    if (elapsedSeconds >= thresholdSeconds) {
      const metadata = buildTimedEventMetadata({
        quarterIndex: quarter,
        totalDurationSeconds,
        players,
        pins,
      });
      const triggered = await recordTimedEventTriggerFromServer({
        gameId,
        ...metadata,
      });
      if (triggered) {
        gameData.timedEventActive = true;
        gameData.timedEventTargetPinId = metadata.targetPinId ?? null;
        break;
      }
    }
  }
}

function buildTimedEventMetadata({
  quarterIndex,
  totalDurationSeconds,
  players,
  pins,
}) {
  const totalRunnerCount = Array.isArray(players)
    ? players.filter((player) => player.role === 'runner').length
    : 0;
  const requiredRunners = totalRunnerCount > 0
    ? Math.floor(Math.random() * Math.max(1, Math.ceil(totalRunnerCount / 2))) + 1
    : DEFAULT_TIMED_EVENT_REQUIRED_RUNNERS;
  const baseDurationSeconds = Math.floor(totalDurationSeconds / 8);
  const truncatedDurationSeconds = Math.floor(baseDurationSeconds / 60) * 60;
  const eventDurationSeconds = Math.max(1, truncatedDurationSeconds);
  const percentProgress = Math.min(100, quarterIndex * 25);
  const computedSeconds = Math.round((totalDurationSeconds / 4) * quarterIndex);
  const clampedSeconds = Math.max(
    0,
    Math.min(computedSeconds, totalDurationSeconds),
  );
  const eventTimeLabel = formatTimedEventTimeMark(clampedSeconds);
  const targetPinId = pickTimedEventTargetPinId(pins);
  return {
    quarterIndex,
    requiredRunners,
    eventDurationSeconds,
    percentProgress,
    eventTimeLabel,
    totalRunnerCount,
    targetPinId,
  };
}

function formatTimedEventTimeMark(seconds) {
  if (seconds <= 0) {
    return '直後';
  }
  const hours = Math.floor(seconds / 3600);
  const minutes = Math.floor((seconds % 3600) / 60);
  if (hours > 0) {
    if (minutes === 0) {
      return `${hours}時間`;
    }
    return `${hours}時間${minutes}分`;
  }
  if (minutes > 0) {
    return `${minutes}分`;
  }
  return `${seconds % 60}秒`;
}

function pickTimedEventTargetPinId(pins) {
  if (!Array.isArray(pins) || pins.length === 0) {
    return null;
  }
  const available = pins.filter((pin) => {
    if (!pin) {
      return false;
    }
    const status = (pin.status || '').toString();
    const isPending = status === 'pending';
    return isPending && pin.cleared !== true;
  });
  if (available.length === 0) {
    return null;
  }
  const index = Math.floor(Math.random() * available.length);
  return available[index]?.id ?? null;
}

async function recordTimedEventTriggerFromServer({
  gameId,
  quarterIndex,
  requiredRunners,
  eventDurationSeconds,
  percentProgress,
  eventTimeLabel,
  totalRunnerCount,
  targetPinId,
}) {
  const gameRef = db.collection('games').doc(gameId);
  const triggered = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(gameRef);
    if (!snapshot.exists) {
      return false;
    }
    const data = snapshot.data() || {};
    if (data.status !== 'running') {
      return false;
    }
    const triggered = new Set(
      Array.isArray(data.timedEventQuarters)
        ? data.timedEventQuarters.map((value) => toInt(value))
        : [],
    );
    if (triggered.has(quarterIndex)) {
      return false;
    }
    transaction.update(gameRef, {
      timedEventQuarters: admin.firestore.FieldValue.arrayUnion(quarterIndex),
      timedEventActive: true,
      timedEventActiveStartedAt: admin.firestore.FieldValue.serverTimestamp(),
      timedEventActiveDurationSec: eventDurationSeconds,
      timedEventActiveQuarter: quarterIndex,
      timedEventTargetPinId: targetPinId ?? null,
      timedEventRequiredRunners: requiredRunners,
      timedEventResult: null,
      timedEventResultAt: null,
      oniCaptureRadiusMultiplier: 1.0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const eventRef = gameRef.collection('events').doc();
    transaction.set(eventRef, {
      type: 'timed_event',
      quarter: quarterIndex,
      requiredRunners,
      eventDurationSeconds,
      percentProgress,
      eventTimeLabel,
      totalRunnerCount,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (triggered) {
    functions.logger.info('Triggered timed event', {
      gameId,
      quarterIndex,
      requiredRunners,
      eventDurationSeconds,
      targetPinId: targetPinId ?? null,
    });
  }
  return Boolean(triggered);
}

async function maybeResolveTimedEventTimeout(gameId, data) {
  if (!data?.timedEventActive) {
    return;
  }
  const startedAt = convertToDate(data.timedEventActiveStartedAt);
  const durationSec = toInt(data.timedEventActiveDurationSec);
  if (!startedAt || durationSec <= 0) {
    return;
  }
  const endsAt = startedAt.getTime() + durationSec * 1000;
  if (Date.now() < endsAt) {
    return;
  }
  const resolved = await resolveTimedEventFromServer(
    gameId,
    false,
    data.timedEventTargetPinId || null,
  );
  if (resolved) {
    data.timedEventActive = false;
    data.timedEventTargetPinId = null;
  }
}

async function maybeResolveTimedEventByPinClear(gameId, data, pins) {
  if (!data?.timedEventActive) {
    return;
  }
  const targetPinId = data.timedEventTargetPinId;
  if (!targetPinId) {
    return;
  }
  const targetPin = Array.isArray(pins)
    ? pins.find((pin) => pin.id === targetPinId)
    : null;
  if (!targetPin) {
    return;
  }
  if (!isPinCleared(targetPin)) {
    return;
  }
  const resolved = await resolveTimedEventFromServer(gameId, true, targetPinId);
  if (resolved) {
    data.timedEventActive = false;
    data.timedEventTargetPinId = null;
  }
}

async function resolveTimedEventFromServer(gameId, success, expectedTargetPinId) {
  const gameRef = db.collection('games').doc(gameId);
  const resolved = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(gameRef);
    if (!snapshot.exists) {
      return false;
    }
    const data = snapshot.data() || {};
    if (!data.timedEventActive) {
      return false;
    }
    if (
      expectedTargetPinId &&
      data.timedEventTargetPinId &&
      data.timedEventTargetPinId !== expectedTargetPinId
    ) {
      return false;
    }
    transaction.update(gameRef, {
      timedEventActive: false,
      timedEventActiveStartedAt: null,
      timedEventActiveDurationSec: null,
      timedEventActiveQuarter: null,
      timedEventTargetPinId: null,
      timedEventRequiredRunners: null,
      timedEventResult: success ? 'success' : 'failure',
      timedEventResultAt: admin.firestore.FieldValue.serverTimestamp(),
      oniCaptureRadiusMultiplier: success ? 1.0 : 2.0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    const eventRef = gameRef.collection('events').doc();
    transaction.set(eventRef, {
      type: 'timed_event_result',
      result: success ? 'success' : 'failure',
      quarter: data.timedEventActiveQuarter ?? null,
      requiredRunners: data.timedEventRequiredRunners ?? null,
      eventDurationSeconds: data.timedEventActiveDurationSec ?? null,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      resultAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      quarter: data.timedEventActiveQuarter ?? null,
      success,
    };
  });
  if (resolved) {
    try {
      const randomized = await randomizePendingPinLocations(gameId);
      functions.logger.info('Randomized pending pins after timed event', {
        gameId,
        randomized,
      });
    } catch (error) {
      functions.logger.error('Failed to randomize pending pins after timed event', {
        error,
        gameId,
      });
    }
    functions.logger.info('Resolved timed event automatically', {
      gameId,
      quarter: resolved.quarter,
      success: resolved.success,
    });
    return true;
  }
  return false;
}

async function endGameFromServer(gameId, result, pinCount) {
  const gameRef = db.collection('games').doc(gameId);
  const resolved = await db.runTransaction(async (transaction) => {
    const snapshot = await transaction.get(gameRef);
    if (!snapshot.exists) {
      return null;
    }
    const data = snapshot.data() || {};
    if (data.status !== 'running') {
      return null;
    }
    const resolvedPinCount = toInt(pinCount) || toInt(data.pinCount) || DEFAULT_PIN_COUNT;
    transaction.update(gameRef, {
      status: 'ended',
      endResult: result,
      timedEventActive: false,
      timedEventActiveStartedAt: null,
      timedEventActiveDurationSec: null,
      timedEventActiveQuarter: null,
      timedEventTargetPinId: null,
      timedEventRequiredRunners: null,
      timedEventResult: null,
      timedEventResultAt: null,
      oniCaptureRadiusMultiplier: 1.0,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return {
      pinCount: resolvedPinCount,
    };
  });
  if (!resolved) {
    return;
  }
  await reviveDownedRunners(gameId);
  if (resolved.pinCount > 0) {
    await reseedPinsWithRandomLocations(gameId, resolved.pinCount);
  }
  functions.logger.info('Automatically ended game', {
    gameId,
    result,
  });
}

async function reviveDownedRunners(gameId) {
  const playersRef = db.collection('games').doc(gameId).collection('players');
  const snapshot = await playersRef
    .where('role', '==', 'runner')
    .where('status', '==', 'downed')
    .get();
  if (snapshot.empty) {
    return;
  }
  const batch = db.batch();
  snapshot.docs.forEach((doc) => {
    batch.update(doc.ref, { status: 'active' });
  });
  await batch.commit();
}

async function reseedPinsWithRandomLocations(gameId, targetCount) {
  const sanitizedCount = Math.max(
    0,
    Math.min(toInt(targetCount), MAX_PIN_COUNT),
  );
  const pinsRef = db.collection('games').doc(gameId).collection('pins');
  const snapshot = await pinsRef.get();
  const batch = db.batch();
  let hasChanges = false;
  snapshot.docs.forEach((doc) => {
    batch.delete(doc.ref);
    hasChanges = true;
  });
  if (sanitizedCount > 0) {
    const locations = generatePinLocations(sanitizedCount);
    for (const location of locations) {
      const docRef = pinsRef.doc();
      batch.set(docRef, {
        lat: location.lat,
        lng: location.lng,
        type: 'yellow',
        status: 'pending',
        cleared: false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      hasChanges = true;
    }
  }
  if (hasChanges) {
    await batch.commit();
  }
}

async function randomizePendingPinLocations(gameId) {
  const pinsRef = db.collection('games').doc(gameId).collection('pins');
  const snapshot = await pinsRef.get();
  if (snapshot.empty) {
    return 0;
  }
  const reservedKeys = new Set();
  const pendingDocs = [];
  snapshot.docs.forEach((doc) => {
    const data = doc.data() || {};
    const lat = typeof data.lat === 'number' ? data.lat : null;
    const lng = typeof data.lng === 'number' ? data.lng : null;
    if (isPinCleared(data)) {
      if (lat !== null && lng !== null) {
        reservedKeys.add(formatPinLocationKey(lat, lng));
      }
      return;
    }
    pendingDocs.push(doc);
  });
  if (pendingDocs.length === 0) {
    return 0;
  }
  const locations = generatePinLocations(pendingDocs.length, reservedKeys);
  const updates = Math.min(locations.length, pendingDocs.length);
  if (updates === 0) {
    return 0;
  }
  const batch = db.batch();
  for (let i = 0; i < updates; i += 1) {
    const doc = pendingDocs[i];
    const location = locations[i];
    if (!location || !doc?.ref) {
      continue;
    }
    batch.update(doc.ref, {
      lat: location.lat,
      lng: location.lng,
      status: 'pending',
      cleared: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
  await batch.commit();
  return updates;
}

function generatePinLocations(count, existingKeys) {
  const locations = [];
  const usedKeys = new Set(existingKeys || []);
  const maxAttempts = Math.max(count * 200, 400);
  let attempts = 0;
  while (locations.length < count && attempts < maxAttempts) {
    attempts += 1;
    const candidate = randomPointInYamanotePolygon(40);
    if (!candidate) {
      continue;
    }
    const key = formatPinLocationKey(candidate.lat, candidate.lng);
    if (!usedKeys.has(key)) {
      usedKeys.add(key);
      locations.push(candidate);
    }
  }
  let fallbackOffset = 0;
  while (locations.length < count && fallbackOffset < count * 2) {
    const lat = YAMANOTE_CENTER.lat;
    const lng = YAMANOTE_CENTER.lng + fallbackOffset * 0.0001;
    fallbackOffset += 1;
    const key = formatPinLocationKey(lat, lng);
    if (!usedKeys.has(key)) {
      usedKeys.add(key);
      locations.push({ lat, lng });
    }
  }
  return locations;
}

function formatPinLocationKey(lat, lng) {
  return `${lat.toFixed(PIN_DUPLICATE_PRECISION)}:${lng.toFixed(
    PIN_DUPLICATE_PRECISION,
  )}`;
}

function getRandomInRange(min, max) {
  return min + Math.random() * (max - min);
}

function randomPointInYamanotePolygon(maxAttempts = 200) {
  for (let attempt = 0; attempt < maxAttempts; attempt += 1) {
    const lat = getRandomInRange(YAMANOTE_BOUNDS.south, YAMANOTE_BOUNDS.north);
    const lng = getRandomInRange(YAMANOTE_BOUNDS.west, YAMANOTE_BOUNDS.east);
    if (isPointInsideYamanotePolygon(lat, lng)) {
      return { lat, lng };
    }
  }
  return null;
}

function isPointInsideYamanotePolygon(lat, lng) {
  return isPointInsidePolygon(lat, lng, YAMANOTE_STATION_POLYGON);
}

function isPointInsidePolygon(lat, lng, polygon) {
  if (!Array.isArray(polygon) || polygon.length === 0) {
    return false;
  }
  let inside = false;
  for (let i = 0, j = polygon.length - 1; i < polygon.length; j = i, i += 1) {
    const xi = polygon[i].lng;
    const yi = polygon[i].lat;
    const xj = polygon[j].lng;
    const yj = polygon[j].lat;
    const denominator = yj - yi;
    if (Math.abs(denominator) <= 1e-12) {
      continue;
    }
    const intersects =
      yi > lat !== yj > lat &&
      lng < ((xj - xi) * (lat - yi)) / denominator + xi;
    if (intersects) {
      inside = !inside;
    }
  }
  return inside;
}
