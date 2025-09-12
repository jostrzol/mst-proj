import type { PageServerLoad } from './$types';

import { TUNE_READ_RATE } from '$env/static/private';

export const load: PageServerLoad = () => {
	globalThis.client.setOptions({
		readCount: 4,
		intervalMs: 1000 / parseInt(TUNE_READ_RATE),
	});
};
