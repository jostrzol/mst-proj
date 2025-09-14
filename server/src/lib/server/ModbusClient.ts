import modbus, { UserRequestError } from 'jsmodbus';
import net from 'net';

export type MutableOptions = {
	readCount?: number;
	intervalMs?: number;
	retryMs?: number;
	retries?: number;
};
export type Options = net.SocketConnectOpts &
	MutableOptions & {
		unitId: number;
		onMessage?: (reading: { timestamp: number; data: number[] }) => void;
		onConnected?: () => void;
		onRecovered?: () => void;
	};

export class ModbusClient {
	#options: Options;
	#client?: modbus.ModbusTCPClient;
	#intervalHandle?: NodeJS.Timeout;
	#retryNumber: number = 0;
	#isError: boolean = false;
	#wasError: boolean = false;

	constructor(options: Options) {
		this.#options = options;
	}

	setOptions(options: MutableOptions) {
		console.log('MODBUS: update options:', options);
		this.#options = Object.assign({}, this.#options, options);
	}

	private get intervalMs() {
		return this.#options.intervalMs || 100;
	}

	private get retryMs() {
		return this.#options.retryMs || 1000;
	}

	private get retries() {
		return this.#options.retries || 5;
	}

	private async client() {
		if (this.#client) return this.#client;

		console.info('MODBUS: Connecting...');
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

	async startReading(address: number = 0) {
		if (this.#intervalHandle) return;

		const loop = async () => {
			try {
				if (this.#isError) return;

				const client = await this.client();

				const readCount = this.#options.readCount || 2;
				const result = await client.readInputRegisters(
					address,
					readCount * 2 /* count * sizeof(float) / sizeof(uint16) */,
				);
				const receivedAt = result.metrics.receivedAt.valueOf();
				const buffer = result.response.body.valuesAsBuffer;
				const floats = [...Array(readCount)]
					.keys()
					.map((i) => buffer.readFloatBE(i * 4))
					.toArray();

				const reading = { timestamp: receivedAt, data: floats };
				this.#options.onMessage?.call(null, reading);
				this.clearWasError();
			} catch (e) {
				if (isErrnoException(e) && ['EAI_AGAIN', 'ENOTFOUND'].includes(e.code || '')) {
					console.info('MODBUS: Cannot resolve hostname');
				} else if (e instanceof UserRequestError && e.err === 'Offline') {
					console.info('MODBUS: Cannot reach');
				} else if (e instanceof UserRequestError && e.err === 'Timeout') {
					console.info('MODBUS: Connection timed out');
				} else if (e instanceof UserRequestError && e.err === 'OutOfSync') {
					console.info('MODBUS: Lost connection');
				} else {
					console.error('MODBUS: ERROR reading:', e);
				}

				if (this.#isError) return;
				this.#isError = this.#wasError = true;
				if (this.#retryNumber++ >= this.retries) this.closeClient();

				await new Promise((r) => setTimeout(r, this.retryMs));
				this.#isError = false;
			}
		};

		this.#intervalHandle = setInterval(loop, this.intervalMs);
	}

	async writeRegistersFloat32(address: number, values: number[]) {
		if (this.#isError) return;

		try {
			const client = await this.client();
			const floats = Float32Array.of(...values);
			const data = Buffer.from(floats.buffer);
			data.swap32(); // convert to Big Endian
			await client.writeMultipleRegisters(address, data);
			this.clearWasError();
		} catch (e) {
			console.error('MODBUS: ERROR writing:', e);
			this.#wasError = true;
		}
	}

	private clearWasError() {
		if (!this.#wasError) return;

		this.#wasError = false;
		console.error('MODBUS: Connected!');
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

const isErrnoException = (value: unknown): value is NodeJS.ErrnoException => {
	return typeof value === 'object' && value !== null && 'errno' in value;
};
