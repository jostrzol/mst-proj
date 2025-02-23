import { ModbusClient } from '$lib/server';
import type { ServerInit } from '@sveltejs/kit';

import {
	CONTROLLER_MODBUS_UNIT_ID,
	CONTROLLER_HOST,
	CONTROLLER_PORT,
	CONTROLLER_SAMPLE_RATE,
	CONTROLLER_BATCH_SIZE,
	READ_RATE,
} from '$env/static/private';
import { _sendToAll } from './routes/ws/+server';

export let client: ModbusClient;

export const init: ServerInit = async () => {
	client = new ModbusClient({
		host: CONTROLLER_HOST,
		sampleRate: parseInt(CONTROLLER_SAMPLE_RATE),
		port: parseInt(CONTROLLER_PORT),
		unitId: parseInt(CONTROLLER_MODBUS_UNIT_ID),
		batchSize: parseInt(CONTROLLER_BATCH_SIZE),
		intervalMs: 1000 / parseInt(READ_RATE),
		onMessage: (readings) => _sendToAll({ type: 'readings', data: readings }),
		onConnected: () => _sendToAll({ type: 'connected' }),
	});
	client.startReadingCurrentFrequency();

	process.on('sveltekit:shutdown', client.close);
};
