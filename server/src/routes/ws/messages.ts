export type WsMessage =
	| {
			type: 'read';
			data: Reading;
	  }
	| {
			type: 'write';
			data: {
				targetFrequency: number;
				proportionalFactor: number;
				integrationTime: number;
				differentiationTime: number;
			};
	  }
	| {
			type: 'connected';
			data?: never;
	  };

export interface Reading {
	frequency: number;
	controlSignal: number;
	timestamp: number;
}

// eslint-disable-next-line @typescript-eslint/no-namespace
export namespace WsMessage {
	export function parse(message: string): WsMessage {
		return JSON.parse(message);
	}
	export function serialize(message: WsMessage): string {
		return JSON.stringify(message);
	}
}
