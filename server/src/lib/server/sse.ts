import { Message, type WriteMessage } from '$lib/data/messages';
import { client } from '../../hooks.server';

const clients = new Set<ReadableStreamDefaultController>();

export function sendToAll(message: Message) {
	const data = Message.serialize(message);
	clients.forEach((controller) => {
		try {
			controller.enqueue(`data: ${data}\n\n`);
		} catch {
			clients.delete(controller);
		}
	});
}

const resetMessage: WriteMessage = {
	type: 'write',
	data: {
		integrationTime: 0.5,
		differentiationTime: 0.65,
		proportionalFactor: 0.07,
		targetFrequency: 0,
	},
};

export function addClient(controller: ReadableStreamDefaultController) {
	console.debug('SSE client connected');
	clients.add(controller);
}

export function removeClient(controller: ReadableStreamDefaultController) {
	console.debug('SSE client disconnected');
	clients.delete(controller);

	if (clients.size === 0) {
		console.info('Sending reset message');
		modbusSend(resetMessage);
	}
}

export function modbusSend(message: WriteMessage) {
	const data = message.data;
	// JSON cannot convey infinity values -- convert them to nulls
	if (data.integrationTime == null) data.integrationTime = Infinity;
	const values = Object.values(message.data);
	client.writeRegistersFloat32(0, values);
}
