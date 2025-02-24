import modbus from 'jsmodbus';
import net from 'net';

export type Options = net.SocketConnectOpts & {
	unitId: number;
	intervalMs?: number;
	retryMs?: number;
	retries?: number;
	onMessage?: (reading: { timestamp: number; data: number[] }) => void;
	onConnected?: () => void;
};

export class ModbusClient {
	#options: Options;
	#client?: modbus.ModbusTCPClient;
	#intervalHandle?: NodeJS.Timeout;
	#retryNumber: number = 0;
	#isError: boolean = false;

	constructor(options: Options) {
		this.#options = options;
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

	async startReading(address: number = 0, count: number = 2) {
		if (this.#intervalHandle) return;

		const loop = async () => {
			try {
				if (this.#isError) return;

				const client = await this.client();

				const result = await client.readInputRegisters(address, count);
				const receivedAt = result.metrics.receivedAt.valueOf();
				const buffer = result.response.body.valuesAsBuffer;
				const floats = [...Array(count)]
					.keys()
					.map((i) => buffer.readFloatBE(i * 4))
					.toArray();

				const reading = { timestamp: receivedAt, data: floats };
				this.#options.onMessage?.call(null, reading);
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

	async writeRegistersFloat32(address: number, values: number[]) {
		if (this.#isError) return;

		const client = await this.client();
		const floats = Float32Array.of(...values);
		const data = Buffer.from(floats.buffer);
		data.swap32(); // convert to Big Endian
		console.log('sending', values, ' = ', data);
		await client.writeMultipleRegisters(address, data);
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
