const functions = require('firebase-functions');
const admin = require('firebase-admin');

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

const CHAT_CHANNELS = {
  messages_oni: {
    role: 'oni',
    title: '鬼チャット',
  },
  messages_runner: {
    role: 'runner',
    title: '逃走者チャット',
  },
};

exports.onChatMessageCreated = functions
  .region('us-central1')
  .firestore.document('games/{gameId}/{collectionId}/{messageId}')
  .onCreate(async (snapshot, context) => {
    const { gameId, collectionId, messageId } = context.params;
    const channelMeta = CHAT_CHANNELS[collectionId];
    if (!channelMeta) {
      return null;
    }

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
      const playersSnap = await db
        .collection('games')
        .doc(gameId)
        .collection('players')
        .where('role', '==', channelMeta.role)
        .get();

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
        if (Array.isArray(fcmTokens)) {
          fcmTokens.forEach((token) => {
            if (typeof token === 'string' && token.length > 0) {
              tokens.push(token);
              if (!tokenOwners.has(token)) {
                tokenOwners.set(token, doc.id);
              }
            }
          });
        }
      });

      if (tokens.length === 0) {
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

      const invalidTokens = new Set();
      const chunkSize = 500;
      for (let i = 0; i < tokens.length; i += chunkSize) {
        const chunk = tokens.slice(i, i + chunkSize);
        try {
          functions.logger.info('Sending chat notification batch', {
            gameId,
            role: channelMeta.role,
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
                });
              }
            }
          });
        } catch (error) {
          functions.logger.error('Failed to send chat notifications', {
            error,
            gameId,
            role: channelMeta.role,
          });
        }
      }

      if (invalidTokens.size > 0) {
        await removeInvalidTokens(gameId, invalidTokens, tokenOwners);
      }
    } catch (error) {
      functions.logger.error('Chat notification handling failed', {
        error,
        gameId,
        collectionId,
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
