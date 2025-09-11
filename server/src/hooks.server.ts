import { ModbusClient, type Options } from '$lib/server';
import { sendToAll } from '$lib/server/sse';
import type { ServerInit } from '@sveltejs/kit';

import {
	CONTROLLER_HOST,
	CONTROLLER_MODBUS_UNIT_ID,
	CONTROLLER_PORT,
	READ_RATE,
} from '$env/static/private';

import { building } from '$app/environment';

export let client: ModbusClient;

export const init: ServerInit = async () => {
	if (building) return;

	const options: Options = {
		host: CONTROLLER_HOST,
		port: parseInt(CONTROLLER_PORT),
		unitId: parseInt(CONTROLLER_MODBUS_UNIT_ID),
		intervalMs: 1000 / parseInt(READ_RATE),
		onMessage: ({ timestamp, data: [frequency, controlSignal] }) => {
			sendToAll({ type: 'read', data: { timestamp, frequency, controlSignal } });
		},
		onConnected: () => sendToAll({ type: 'connected' }),
		onRecovered: () => sendToAll({ type: 'recovered' }),
	};
	console.info('Modbus server options:', options);
	client = new ModbusClient(options);
	client.startReading();

	process.on('sveltekit:shutdown', client.close);
};
