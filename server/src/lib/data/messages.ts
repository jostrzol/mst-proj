export type Message =
	| ReadMessage
	| WriteMessage
	| {
			type: 'connected';
			data?: never;
	  }
	| {
			type: 'recovered';
			data?: never;
	  };

export type ReadMessage = {
	type: 'read';
	timestamp: number;
	data: number[];
};

export type WriteMessage = {
	type: 'write';
	data: number[];
};

// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace Message {
	export function parse(message: string): Message {
		return JSON.parse(message);
	}
	export function serialize(message: Message): string {
		return JSON.stringify(message);
	}
}
