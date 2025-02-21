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
import { _peers } from './routes/ws/+server';

let client: ModbusClient | undefined;

export const init: ServerInit = async () => {
  if (client) return;

  client = new ModbusClient({
    host: CONTROLLER_HOST,
    sampleRate: parseInt(CONTROLLER_SAMPLE_RATE),
    port: parseInt(CONTROLLER_PORT),
    unitId: parseInt(CONTROLLER_MODBUS_UNIT_ID),
    onMessage: (readings) => {
      _peers.forEach((peer) => peer.send(JSON.stringify(readings)));
    },
    batchSize: parseInt(CONTROLLER_BATCH_SIZE),
    intervalMs: 1000 / parseInt(READ_RATE),
  });
  client.startReading();

  process.on('sveltekit:shutdown', client.close);
};
