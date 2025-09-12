import { Message, type WriteMessage } from '$lib/data/messages';
import { client } from '../../hooks.server';

const clients = new Map<string, ReadableStreamDefaultController>();

export function sendToAll(message: Message) {
	const data = Message.serialize(message);
	clients.forEach((controller, uid) => {
		try {
			controller.enqueue(`data: ${data}\n\n`);
		} catch {
			clients.delete(uid);
		}
	});
}

export function addClient(uid: string, controller: ReadableStreamDefaultController) {
	console.debug('SSE: client connected');
	clients.set(uid, controller);
}

export function removeClient(uid: string) {
	console.debug('SSE: client disconnected');
	clients.delete(uid);
}

export function modbusSend(message: WriteMessage) {
	const data = message.data;
	// JSON cannot convey infinity values -- convert them to nulls
	if (data.integrationTime == null) data.integrationTime = Infinity;
	const values = Object.values(message.data);
	client.writeRegistersFloat32(0, values);
}
