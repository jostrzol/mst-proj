import type { Reading } from '$lib/Reading'
import modbus from 'jsmodbus'
import net from 'net'

const MAX_U16 = 2 << 16 - 1

export type Options = net.SocketConnectOpts & {
  unitId: number
  sample_rate: number
  batch_size?: number
  interval_ms?: number
  retry_ms?: number
  onMessage?: (readings: Reading[]) => void
}

export class ModbusClient {
  #options: Options
  #client?: modbus.ModbusTCPClient
  #intervalHandle?: NodeJS.Timeout
  #sample_interval_ms: number

  constructor(options: Options) {
    this.#options = options;
    this.#sample_interval_ms = 1000 / options.sample_rate
  }

  private get batch_size() {
    return this.#options.batch_size || 1
  }

  private get interval_ms() {
    return this.#options.interval_ms || 100
  }

  private get retry_ms() {
    return this.#options.retry_ms || 5000
  }

  private async client() {
    if (this.#client) return this.#client

    console.info("Connecting to modbus server with options:", this.#options)
    const socket = new net.Socket();
    this.#client = new modbus.client.TCP(socket, this.#options.unitId)
    const promise = new Promise((resolve, reject) => {
      socket.on("connect", resolve)
      socket.on("error", reject)
      socket.connect(this.#options)
    })
    await promise
    return this.#client;
  }

  async startReading() {
    if (this.#intervalHandle) return

    const loop = async () => {
      try {
        const client = await this.client()

        const result = await client.readInputRegisters(1, this.batch_size)
        const receivedAt = result.metrics.receivedAt.valueOf()
        const data = result.response.body.valuesAsArray
        const readings = [...data]
          .filter(value => value < MAX_U16)
          .map((value, i) => ({
            value: value,
            timestamp: receivedAt - i * this.#sample_interval_ms,
          }))

        this.#options.onMessage?.call(null, readings)
      } catch (e) {
        console.error("Error while reading modbus:", e)
        console.info(`Restarting modbus server in ${this.retry_ms} ms`)
        this.close()
        await new Promise(r => setTimeout(r, this.retry_ms));
        this.startReading()
      }
    }

    this.#intervalHandle = setInterval(loop, this.interval_ms)
  }

  close() {
    if (this.#intervalHandle) clearInterval(this.#intervalHandle)
    this.#intervalHandle = undefined
    if (this.#client) this.#client.socket.destroy()
    this.#client = undefined
  }
}
