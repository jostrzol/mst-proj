import { useServer } from 'vite-sveltekit-node-ws';
import { WsMessage, type WsWriteMessage } from '$lib/ws/messages';
import WebSocket, { WebSocketServer } from 'ws';
import * as http from 'node:http';
import { client } from '../../../hooks.server';

export const peers = new Set<WebSocket>();

export function sendToAll(message: WsMessage) {
	const body = WsMessage.serialize(message);
	// console.log('peers:', peers.size);
	peers.forEach((peer) => peer.send(body));
}
export function wsServer() {
	useServer((server) => {
		console.debug('Initializing websocket server');
		const wss = new WebSocketServer({ server: server as unknown as http.Server });
		wss.on('connection', async (ws) => {
			console.debug('Websocket connected');
			peers.add(ws);

			ws.on('message', (message) => {
				const msg = WsMessage.parse(message.toString());
				if (msg.type === 'write') {
					modbusSend(msg);
				} else console.error('Undefined WS message:', message);
			});
			ws.on('close', () => {
				console.debug('Websocket closed');
				peers.delete(ws);

				if (peers.size === 0) {
					console.info('Sending reset message');
					modbusSend(resetMessage);
				}
			});
			ws.on('error', (error) => {
				console.debug('Websocket error:', error);
			});
		});
	});
}

const resetMessage: WsWriteMessage = {
	type: 'write',
	data: {
		integrationTime: 0.5,
		differentiationTime: 0.65,
		proportionalFactor: 0.07,
		targetFrequency: 0,
	},
};

function modbusSend(msg: WsWriteMessage) {
	const data = msg.data;
	// JSON cannot convey infinity values -- convert them to nulls
	if (data.integrationTime == null) data.integrationTime = Infinity;
	const values = Object.values(msg.data);
	client.writeRegistersFloat32(0, values);
}
