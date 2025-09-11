import { Message } from '$lib/data/messages';
import { addClient, removeClient, modbusSend } from '$lib/server/sse';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = () => {
	const stream = new ReadableStream({
		start(controller) {
			addClient(controller);
		},
		cancel(controller) {
			removeClient(controller);
		},
	});

	return new Response(stream, {
		headers: {
			'Content-Type': 'text/event-stream',
			'Cache-Control': 'no-cache',
			Connection: 'keep-alive',
		},
	});
};

export const POST: RequestHandler = async ({ request }) => {
	const body = await request.text();
	const message = Message.parse(body);

	if (message.type === 'write') {
		modbusSend(message);
		return new Response('OK');
	}

	return new Response('Invalid message type', { status: 400 });
};
