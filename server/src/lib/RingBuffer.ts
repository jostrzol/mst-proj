import { createSubscriber } from "svelte/reactivity";

export type TypedNumberArray =
  | Uint8Array
  | Uint8ClampedArray
  | Int16Array
  | Uint16Array
  | Int32Array
  | Uint32Array
  | Float32Array
  | Float64Array
  | BigInt64Array
  | BigUint64Array
  ;
type NumberType<T extends TypedNumberArray> = Exclude<ReturnType<T["at"]>, undefined>;

export class RingBuffer<T extends TypedNumberArray> {
  #buffer: T;
  #head_i: number = 0;
  #length: number = 0;
  #update: (() => void) | null = null
  #subscribe: (() => void) | null = null

  constructor(Class: new (size: number) => T, size: number) {
    this.#buffer = new Class(size)
    this.#subscribe = createSubscriber(update => {
      this.#update = update
      return () => this.#update = this.#subscribe = null
    })
  }

  push(item: number) {
    this.#buffer[this.#head_i] = item;
    this.#head_i = (this.#head_i + 1) % this.#buffer.length
    this.#length = Math.min(this.#buffer.length, this.#length + 1)

    this.#update?.call(this)
  }

  get length() {
    return this.#length
  }

  *[Symbol.iterator](): Iterator<NumberType<T>> {
    this.#subscribe?.call(this);

    yield* Array(this.#length).keys().map(i => this.#buffer[this.real_index(i)] as any);
  }

  at(index: number): NumberType<T> | undefined {
    this.#subscribe?.call(this);

    return index > this.#length ? undefined : this.#buffer[this.real_index(index)] as any;
  }

  private real_index(index: number) {
    return (this.#head_i + index) % this.#length;
  }
}
