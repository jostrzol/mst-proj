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
	data: Reading;
};

export type WriteMessage = {
	type: 'write';
	data: {
		targetFrequency: number;
		proportionalFactor: number;
		integrationTime: number;
		differentiationTime: number;
	};
};

export interface Reading {
	frequency: number;
	controlSignal: number;
	timestamp: number;
}

// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace Message {
	export function parse(message: string): Message {
		return JSON.parse(message);
	}
	export function serialize(message: Message): string {
		return JSON.stringify(message);
	}
}
