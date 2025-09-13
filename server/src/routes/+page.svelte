<script lang="ts">
	import { getSettings } from 'svelte-ux';
	const { showDrawer } = getSettings();

	$showDrawer = true;
</script>

<div class="mb-40 p-4 text-left">
	<h1 class="mb-4 text-center text-3xl font-bold">
		This is a control panel for the third scenario.
	</h1>
	<ul class="ml-6 list-outside list-disc space-y-2 text-left">
		<li class="pl-2">
			<div>
				If you started a tuning process using:
				<br />
				<code class="bg-surface-100 rounded px-2 py-1 font-mono text-sm"
					>task scenarios-3-pid-tune</code
				>
				<br />
				navigate to the&nbsp;<a href={'/tune'} class="text-primary font-bold">Tune</a> panel.
			</div>
		</li>

		<li class="pl-2">
			<div>
				If you started a third scenario program using:
				<br />
				<code class="bg-surface-100 rounded px-2 py-1 font-mono text-sm"
					>task scenarios-run PROJECT=3-pid[-bm] LANGUAGE=...</code
				>
				<br />
				navigate to the&nbsp;<a href={'/control'} class="text-primary font-bold">Control</a> panel.
			</div>
		</li>
	</ul>
</div>
