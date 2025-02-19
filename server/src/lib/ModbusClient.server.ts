import modbus from 'jsmodbus'
import net from 'net'

export type Options = net.SocketConnectOpts & {
  unit_id: number
  batch_size?: number
  interval_ms?: number
  retry_ms?: number
}

export class ModbusClient {
  #options: Options
  #client?: modbus.ModbusTCPClient
  #intervalHandle?: NodeJS.Timeout

  constructor(options: Options) {
    this.#options = options;
  }

  private get batch_size() {
    return this.#options.batch_size || 16
  }

  private get interval_ms() {
    return this.#options.interval_ms || 200
  }

  private get retry_ms() {
    return this.#options.retry_ms || 1000
  }

  private connect() {
    const socket = net.createConnection(this.#options);
    this.#client = new modbus.client.TCP(socket, this.#options.unit_id)
    return this.#client;
  }

  async start_reading() {
    if (this.#intervalHandle) return
    let client = this.#client || this.connect()

    this.#intervalHandle = setInterval(async () => {
      try {
        const result = await client.readDiscreteInputs(1, this.batch_size)
        console.log(result)
      } catch (e) {
        console.error(e)
        await new Promise(r => setTimeout(r, this.retry_ms));
        client = this.connect()
      }
    }, this.interval_ms)
  }

  close() {
    if (this.#intervalHandle) clearInterval(this.#intervalHandle)
    if (this.#client) this.#client.socket.destroy()
  }
}
