import { Message, type WriteMessage } from '$lib/data/messages';

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
	// JSON cannot convey infinity values -- they are sent as nulls
	const data = message.data.map((value) => (value == null ? Infinity : value));
	globalThis.client.writeRegistersFloat32(0, data);
}
