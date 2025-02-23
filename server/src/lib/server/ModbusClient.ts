import modbus from 'jsmodbus';
import net from 'net';
import type { Reading } from '../../routes/ws/messages';

const MAX_U16 = (1 << 16) - 1;

export type Options = net.SocketConnectOpts & {
	unitId: number;
	sampleRate: number;
	batchSize?: number;
	intervalMs?: number;
	retryMs?: number;
	retries?: number;
	onMessage?: (readings: Reading[]) => void;
	onConnected?: () => void;
};

export class ModbusClient {
	#options: Options;
	#client?: modbus.ModbusTCPClient;
	#intervalHandle?: NodeJS.Timeout;
	#sampleIntervalMs: number;
	#retryNumber: number = 0;
	#isError: boolean = false;

	constructor(options: Options) {
		this.#options = options;
		this.#sampleIntervalMs = 1000 / options.sampleRate;
	}

	private get batch_size() {
		return this.#options.batchSize || 1;
	}

	private get interval_ms() {
		return this.#options.intervalMs || 100;
	}

	private get retry_ms() {
		return this.#options.retryMs || 1000;
	}

	private get retries() {
		return this.#options.retries || 5;
	}

	private async client() {
		if (this.#client) return this.#client;

		console.info('Connecting to modbus server with options:', this.#options);
		const socket = new net.Socket();
		this.#client = new modbus.client.TCP(socket, this.#options.unitId);
		const promise = new Promise((resolve, reject) => {
			socket.on('connect', resolve);
			socket.on('error', reject);
			socket.connect(this.#options);
		});
		this.#retryNumber = 0;
		await promise;
		this.#options.onConnected?.call(null);
		return this.#client;
	}

	async startReadingCurrentFrequency() {
		if (this.#intervalHandle) return;

		const loop = async () => {
			try {
				if (this.#isError) return;

				const client = await this.client();

				const result = await client.readInputRegisters(1, this.batch_size);
				const receivedAt = result.metrics.receivedAt.valueOf();
				const data = result.response.body.valuesAsArray;
				const readings = [...data.reverse()]
					.filter((value) => value < MAX_U16)
					.map((value, i) => ({
						value: value,
						timestamp: receivedAt - i * this.#sampleIntervalMs,
					}));

				this.#options.onMessage?.call(null, readings);
			} catch (e) {
				console.error('Error while reading modbus:', e);

				if (this.#isError) return;
				this.#isError = true;
				if (this.#retryNumber++ < this.retries) {
					console.info(`Retrying in ${this.retry_ms} ms`);
				} else {
					console.info(`Restarting modbus client in ${this.retry_ms} ms`);
					this.closeClient();
				}
				await new Promise((r) => setTimeout(r, this.retry_ms));
				this.#isError = false;
			}
		};

		this.#intervalHandle = setInterval(loop, this.interval_ms);
	}

	async sendRegisters(address: number, values: number[]) {
		if (this.#isError) return;

		const client = await this.client();
		await client.writeMultipleRegisters(address, values);
	}

	close() {
		this.clearInterval();
		this.closeClient();
	}

	private clearInterval() {
		if (this.#intervalHandle) clearInterval(this.#intervalHandle);
		this.#intervalHandle = undefined;
	}

	private closeClient() {
		if (this.#client) this.#client.socket.destroy();
		this.#client = undefined;
	}
}
