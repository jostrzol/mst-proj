import { ModbusClient, type Options } from '$lib/server';
import type { ServerInit } from '@sveltejs/kit';

import {
	CONTROLLER_MODBUS_UNIT_ID,
	CONTROLLER_HOST,
	CONTROLLER_PORT,
	READ_RATE,
} from '$env/static/private';
import { _sendToAll } from './routes/ws/+server';

export let client: ModbusClient;

export const init: ServerInit = async () => {
	const options: Options = {
		host: CONTROLLER_HOST,
		port: parseInt(CONTROLLER_PORT),
		unitId: parseInt(CONTROLLER_MODBUS_UNIT_ID),
		intervalMs: 1000 / parseInt(READ_RATE),
		onMessage: ({ timestamp, data: [frequency, controlSignal] }) => {
			_sendToAll({ type: 'read', data: { timestamp, frequency, controlSignal } });
		},
		onConnected: () => _sendToAll({ type: 'connected' }),
		onRecovered: () => _sendToAll({ type: 'recovered' }),
	};
	console.info('Modbus server options:', options);
	client = new ModbusClient(options);
	client.startReading();

	process.on('sveltekit:shutdown', client.close);
};
