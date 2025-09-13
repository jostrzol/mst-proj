import type { PageServerLoad } from './$types';

import { READ_RATE } from '$env/static/private';

export const load: PageServerLoad = () => {
	globalThis.client.setOptions({
		readCount: 2,
		intervalMs: 1000 / parseInt(READ_RATE),
	});
};
