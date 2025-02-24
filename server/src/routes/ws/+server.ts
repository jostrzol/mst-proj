import { type Peer, type Socket } from '@sveltejs/kit';
import { client } from '../../hooks.server';
import { WsMessage } from './messages';

const _peers = new Set<Peer>();

export function _sendToAll(message: WsMessage) {
  const body = WsMessage.serialize(message);
  _peers.forEach((peer) => peer.send(body));
}

export const socket: Socket = {
  open(peer) {
    _peers.add(peer);
  },

  message(_, message) {
    const msg = WsMessage.parse(message.rawData as string);
    if (msg.type === 'write') {
      const data = msg.data;
      // JSON cannot convey infinity values
      if (data.integrationTime == null) data.integrationTime = Infinity;
      const values = Object.values(msg.data);
      client.writeRegistersFloat32(0, values);
    } else console.error('Undefined WS message:', message);
  },

  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  close(peer, _) {
    _peers.delete(peer);
  },

  error(peer, error) {
    console.error('Closing websocket peer due to error:', error);
    _peers.delete(peer);
  },
};
